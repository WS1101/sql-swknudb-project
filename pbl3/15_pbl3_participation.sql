\encoding UTF8
\set ON_ERROR_STOP on
-- 15_pbl3_participation.sql : 2번 참여 저조 원인 분해·시간대 추천 (서우진)
--
-- 구성
--   v_p2_whatif          대상 회차 × 같은 주의 후보 시간대(평일 5일 × 5개 시각) × 대상 학생
--                        → 모델이 "이 시간으로 옮기면 몇 명이 신청할까"를 계산하는 입력
--   p2_model_run         모델 실행 기록 (학습 기간, 검증 성능)
--   p2_effect            요인별 효과 (로지스틱 회귀 계수, 승산비)
--   p2_session_factor    회차별 요인 분해: "이 요인이 없었다면 몇 명 더 신청했을까"
--   p2_slot_forecast     후보 시간대별 예상 신청·출석 인원
--   v_p2_recommendation  회차별 현재 시간 vs 추천 시간 (시연용)
--
-- 결과 테이블은 analysis/participation_model.py가 채운다 (run_participation.sh).
-- 이 파일은 reset_pbl3.sql에서 함께 실행되며, 재실행하면 결과가 비워진다.

BEGIN;
SET LOCAL search_path = pbl3, public;

DROP VIEW IF EXISTS pbl3.v_p2_recommendation CASCADE;
DROP TABLE IF EXISTS pbl3.p2_slot_forecast, pbl3.p2_session_factor, pbl3.p2_effect, pbl3.p2_model_run CASCADE;
DROP MATERIALIZED VIEW IF EXISTS pbl3.mv_p2_whatif CASCADE;
DROP TABLE IF EXISTS pbl3.p2_whatif_target CASCADE;

-- ---------------------------------------------------------------------
-- 시간대 시뮬레이션 대상 회차
--   예정 회차 전부 + 시간 변경으로 참여가 줄어든 알고리즘 특강 4~8회차 (사후 검증용)
-- ---------------------------------------------------------------------
CREATE TABLE pbl3.p2_whatif_target (
    session_id INT PRIMARY KEY REFERENCES pbl3.program_session (session_id),
    reason     VARCHAR(100) NOT NULL
);
INSERT INTO pbl3.p2_whatif_target
SELECT s.session_id, '예정 회차: 시간대 추천'
  FROM pbl3.program_session s WHERE s.session_status = 'SCHEDULED'
UNION ALL
SELECT s.session_id, '사후 분석: 시간 변경 이후 회차'
  FROM pbl3.program_session s JOIN pbl3.program p USING (program_id)
 WHERE p.series_key = 'ALGO_CT' AND s.session_no >= 4;

-- ---------------------------------------------------------------------
-- 후보 시간대 × 대상 학생
--   - 날짜: 원래 회차와 같은 주의 월~금
--   - 시각: 10:30, 13:00, 14:30, 16:00, 18:30 (원래 진행 시간 길이 유지)
--   - 학생: 원래 회차의 대상 학생 (mv_candidate)
--   - 직전 회차 정보: 완료 회차는 실제 값, 예정 회차는 "마지막으로 진행된 회차" 값을 이어서 사용
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW pbl3.mv_p2_whatif AS
WITH tgt AS (
    SELECT s.session_id, s.program_id, s.session_no, s.session_date, s.start_time, s.end_time,
           s.end_time - s.start_time AS dur, s.delivery_mode, s.campus_code, s.session_status,
           last_done.session_id AS last_done_id
      FROM pbl3.p2_whatif_target t
      JOIN pbl3.program_session s ON s.session_id = t.session_id
      LEFT JOIN LATERAL (
          SELECT d.session_id FROM pbl3.program_session d
           WHERE d.program_id = s.program_id AND d.session_status = 'COMPLETED' AND d.session_no < s.session_no
           ORDER BY d.session_no DESC LIMIT 1) last_done ON TRUE
), slot AS (
    SELECT tgt.*, wd, st,
           tgt.session_date - (EXTRACT(ISODOW FROM tgt.session_date)::INT - wd) AS slot_date
      FROM tgt
     CROSS JOIN generate_series(1, 5) wd
     CROSS JOIN (VALUES (TIME '10:30'), (TIME '13:00'), (TIME '14:30'), (TIME '16:00'), (TIME '18:30')) v(st)
), last_avg AS (
    SELECT session_id, avg(content) AS avg_content
      FROM pbl3.v_response_scored WHERE is_completed GROUP BY session_id
)
SELECT sl.session_id, sl.wd AS weekday_iso, sl.st AS start_time, sl.slot_date,
       (sl.wd = EXTRACT(ISODOW FROM sl.session_date) AND sl.st = sl.start_time) AS is_current,
       c.student_no, c.program_id, c.program_type_code, c.session_no, c.grade_at, c.track_type,
       c.admission_type, c.is_online, c.mileage, c.cross_campus,
       c.past_attended, c.past_registered, c.past_no_show, c.days_since_last_attended, c.sms_opt_in_at,
       pbl3.fn_class_conflict(c.dept_code, c.grade_at, sl.slot_date, sl.st, (sl.st + sl.dur)::TIME) AS class_conflict,
       pbl3.fn_near_exam(sl.slot_date)   AS near_exam,
       pbl3.fn_in_semester(sl.slot_date) AS in_semester,
       EXTRACT(HOUR FROM sl.st)::INT     AS start_hour,
       CASE WHEN sl.session_status = 'COMPLETED' THEN c.prev_attended
            ELSE COALESCE(ld.attended, FALSE) END                     AS prev_attended,
       CASE WHEN sl.session_status = 'COMPLETED' THEN c.prev_own_content
            ELSE lr.content END                                       AS prev_own_content,
       CASE WHEN sl.session_status = 'COMPLETED' THEN c.prev_session_avg_content
            ELSE la.avg_content END                                   AS prev_session_avg_content,
       c.registered AS actual_registered, c.attended AS actual_attended
  FROM slot sl
  JOIN pbl3.mv_candidate c ON c.session_id = sl.session_id
  LEFT JOIN pbl3.mv_candidate ld ON ld.session_id = sl.last_done_id AND ld.student_no = c.student_no
  LEFT JOIN pbl3.v_response_scored lr ON lr.session_id = sl.last_done_id AND lr.student_no = c.student_no AND lr.is_completed
  LEFT JOIN last_avg la ON la.session_id = sl.last_done_id;

CREATE INDEX ix_p2_whatif_session ON pbl3.mv_p2_whatif (session_id, weekday_iso, start_time);

-- ---------------------------------------------------------------------
-- 결과 테이블
-- ---------------------------------------------------------------------
CREATE TABLE pbl3.p2_model_run (
    run_id            INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    model_name        VARCHAR(60)  NOT NULL,
    train_until       DATE         NOT NULL,          -- 이 날짜 이전 회차로 학습
    n_train           INT          NOT NULL,
    n_test            INT          NOT NULL,
    test_auc          NUMERIC(5,3),                   -- 학생 단위 신청 예측 AUC (학습 이후 회차)
    test_session_mae  NUMERIC(8,2),                   -- 회차별 신청 인원 예측 평균 오차(명)
    test_session_mape NUMERIC(6,3),
    note              TEXT
);

CREATE TABLE pbl3.p2_effect (
    run_id      INT          NOT NULL REFERENCES pbl3.p2_model_run (run_id),
    feature     VARCHAR(60)  NOT NULL,
    label       VARCHAR(60)  NOT NULL,
    coef        NUMERIC(8,4) NOT NULL,                -- 로지스틱 회귀 계수 (신청 logit)
    odds_ratio  NUMERIC(8,4) NOT NULL,
    CONSTRAINT pk_p2_effect PRIMARY KEY (run_id, feature)
);

CREATE TABLE pbl3.p2_session_factor (
    run_id             INT          NOT NULL REFERENCES pbl3.p2_model_run (run_id),
    session_id         INT          NOT NULL REFERENCES pbl3.program_session (session_id),
    factor             VARCHAR(40)  NOT NULL,
    label              VARCHAR(60)  NOT NULL,
    affected_students  INT          NOT NULL,         -- 이 요인이 해당되는 대상 학생 수
    predicted_now      NUMERIC(8,2) NOT NULL,         -- 현재 조건의 예상 신청 인원
    predicted_without  NUMERIC(8,2) NOT NULL,         -- 이 요인만 없앤 경우의 예상 신청 인원
    lost_registrations NUMERIC(8,2) NOT NULL,         -- 이 요인 때문에 잃은 신청 인원
    CONSTRAINT pk_p2_session_factor PRIMARY KEY (run_id, session_id, factor)
);

CREATE TABLE pbl3.p2_slot_forecast (
    run_id               INT          NOT NULL REFERENCES pbl3.p2_model_run (run_id),
    session_id           INT          NOT NULL REFERENCES pbl3.program_session (session_id),
    weekday_iso          SMALLINT     NOT NULL,
    start_time           TIME         NOT NULL,
    slot_date            DATE         NOT NULL,
    is_current           BOOLEAN      NOT NULL,
    eligible             INT          NOT NULL,
    conflict_rate        NUMERIC(5,3) NOT NULL,
    near_exam            BOOLEAN      NOT NULL,
    predicted_registered NUMERIC(8,2) NOT NULL,
    predicted_attended   NUMERIC(8,2) NOT NULL,
    CONSTRAINT pk_p2_slot_forecast PRIMARY KEY (run_id, session_id, weekday_iso, start_time)
);

-- 최신 실행의 회차별 현재 시간 vs 추천 시간 (정원 이내에서 예상 출석이 가장 많은 시간)
CREATE VIEW pbl3.v_p2_recommendation AS
WITH r AS (SELECT max(run_id) AS run_id FROM pbl3.p2_model_run),
f AS (
    SELECT f.*, p.capacity,
           least(f.predicted_registered, p.capacity) * f.predicted_attended / NULLIF(f.predicted_registered, 0) AS capped_attended,
           -- 예정 회차는 기준일 이후 날짜만 추천. 예상 인원이 같으면(반올림 기준) 원래 날짜에 가까운 쪽
           row_number() OVER (PARTITION BY f.session_id
                              ORDER BY (s.session_status = 'COMPLETED' OR f.slot_date > g.as_of_date) DESC,
                                       round(least(f.predicted_registered, p.capacity) * f.predicted_attended
                                             / NULLIF(f.predicted_registered, 0)) DESC NULLS LAST,
                                       abs(f.slot_date - s.session_date)) AS rk
      FROM pbl3.p2_slot_forecast f
      JOIN r USING (run_id)
      JOIN pbl3.program_session s ON s.session_id = f.session_id
      JOIN pbl3.program p ON p.program_id = s.program_id
     CROSS JOIN pbl3.generation_meta g
)
SELECT s.session_id, p.program_name, s.session_no, s.session_status, t.reason,
       cur.slot_date AS cur_date, cur.weekday_iso AS cur_weekday, cur.start_time AS cur_time,
       cur.conflict_rate AS cur_conflict_rate, cur.near_exam AS cur_near_exam,
       round(cur.predicted_registered, 1) AS cur_pred_registered,
       round(cur.capped_attended, 1)      AS cur_pred_attended,
       ov.registered AS actual_registered, ov.attended AS actual_attended,
       best.slot_date AS best_date, best.weekday_iso AS best_weekday, best.start_time AS best_time,
       best.conflict_rate AS best_conflict_rate,
       round(best.predicted_registered, 1) AS best_pred_registered,
       round(best.capped_attended, 1)      AS best_pred_attended,
       round(best.capped_attended - cur.capped_attended, 1) AS gain_attended
  FROM pbl3.p2_whatif_target t
  JOIN pbl3.program_session s ON s.session_id = t.session_id
  JOIN pbl3.program p ON p.program_id = s.program_id
  JOIN f cur  ON cur.session_id = s.session_id AND cur.is_current
  JOIN f best ON best.session_id = s.session_id AND best.rk = 1
  LEFT JOIN pbl3.v_session_overview ov ON ov.session_id = s.session_id AND s.session_status = 'COMPLETED';

COMMENT ON VIEW pbl3.v_p2_recommendation IS '최신 모델 실행 기준 회차별 현재 시간과 예상 출석이 가장 많은 시간';

-- 정답 복원 채점 (pbl3_truth: 분석 계정은 볼 수 없음)
--   모델이 추정한 계수를 생성기에 심은 계수와 나란히 놓는다
DROP VIEW IF EXISTS pbl3_truth.v_p2_recovery;
CREATE VIEW pbl3_truth.v_p2_recovery AS
WITH r AS (SELECT max(run_id) AS run_id FROM pbl3.p2_model_run),
truth AS (
    SELECT * FROM pbl3_truth.coef k CROSS JOIN LATERAL (VALUES
        ('class_conflict',     k.reg_class_conflict),
        ('near_exam',          k.reg_near_exam),
        ('vacation',           k.reg_vacation),
        ('fatigue',            k.reg_session_fatigue),
        ('cross_campus',       k.reg_cross_campus),
        ('is_online',          k.reg_online),
        ('friday',             k.reg_friday),
        ('evening',            k.reg_evening),
        ('mileage',            k.reg_mileage_per_pt),
        ('prev_avg_content_c', k.reg_prev_content),
        ('prev_attended',      k.reg_returning),
        ('prev_own_content_c', k.ret_content)) v(feature, truth_coef)
)
SELECT e.feature, e.label, t.truth_coef, e.coef AS estimated_coef,
       round(e.coef - t.truth_coef, 3) AS error
  FROM pbl3.p2_effect e
  JOIN r USING (run_id)
  JOIN truth t USING (feature)
 ORDER BY abs(t.truth_coef) DESC;

GRANT SELECT ON ALL TABLES IN SCHEMA pbl3 TO analytics_reader;
COMMIT;
