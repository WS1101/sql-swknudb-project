\encoding UTF8
\set ON_ERROR_STOP on
-- 14_pbl3_survey_insight.sql : 1번(만족도 품질·재참여) 분석 함수의 pbl3 버전
-- 원본: schema/10_survey_insight.sql, schema/11_survey_participation_link.sql (1번 담당)
--
-- 원칙
--   - 원본 analytics 함수는 건드리지 않는다. 같은 이름·같은 반환 형식의 함수를 pbl3 스키마에 둔다.
--     → analysis/db.py는 source='pbl3'일 때 스키마 이름만 pbl3로 바꿔 호출하면 된다.
--   - 품질 판정 로직(빠른 응답·동일 점수·감점·의심 판정)은 원본을 그대로 옮겼다.
--   - 바뀐 것은 데이터 위치뿐이다: public 설문 → pbl3 설문, survey_response_observation → pbl3.survey_response.started_at,
--     합성 출석/기회 → pbl3.program_participant / pbl3.mv_candidate
--   - 재참여 정의 한 가지만 다르다 (아래 fn_survey_followup 주석 참고).

BEGIN;
SET LOCAL search_path = pbl3, public;

-- 1. 품질 기준 (원본 analytics.survey_insight_setting과 동일)
DROP TABLE IF EXISTS pbl3.survey_insight_setting CASCADE;
CREATE TABLE pbl3.survey_insight_setting (
    setting_id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (setting_id = 1),
    absolute_seconds DOUBLE PRECISION NOT NULL DEFAULT 2 CHECK (absolute_seconds > 0 AND absolute_seconds < 600),
    relative_fraction DOUBLE PRECISION NOT NULL DEFAULT .25 CHECK (relative_fraction > 0 AND relative_fraction < 1),
    relative_percentile DOUBLE PRECISION NOT NULL DEFAULT .1 CHECK (relative_percentile > 0 AND relative_percentile < 1),
    min_cohort INT NOT NULL DEFAULT 10 CHECK (min_cohort >= 2),
    min_questions INT NOT NULL DEFAULT 4 CHECK (min_questions >= 2),
    speed_mode TEXT NOT NULL DEFAULT 'either' CHECK (speed_mode IN ('absolute','relative','either','both')),
    fast_penalty INT NOT NULL DEFAULT 40 CHECK (fast_penalty BETWEEN 0 AND 100),
    straight_penalty INT NOT NULL DEFAULT 15 CHECK (straight_penalty BETWEEN 0 AND 100),
    interaction_penalty INT NOT NULL DEFAULT 20 CHECK (interaction_penalty BETWEEN 0 AND 100),
    suspicious_below INT NOT NULL DEFAULT 70 CHECK (suspicious_below BETWEEN 0 AND 100)
);
INSERT INTO pbl3.survey_insight_setting (setting_id) VALUES (1);

-- 관찰 범위: pbl3 데이터는 2025-03-01 ~ 기준일 전체가 생성되어 있다
DROP TABLE IF EXISTS pbl3.participation_coverage CASCADE;
CREATE TABLE pbl3.participation_coverage (
    data_source TEXT PRIMARY KEY CHECK (data_source = 'pbl3'),
    observed_from TIMESTAMPTZ NOT NULL,
    observed_through TIMESTAMPTZ NOT NULL,
    evidence TEXT NOT NULL,
    CHECK (observed_from <= observed_through)
);
INSERT INTO pbl3.participation_coverage
SELECT 'pbl3', TIMESTAMPTZ '2025-03-01 00:00+09', (as_of_date + TIME '23:59') AT TIME ZONE 'Asia/Seoul',
       'pbl3 생성기: 기준일까지 모든 회차의 신청·출석·대상 학생 생성 완료'
  FROM pbl3.generation_meta;

-- 2. 프로그램 (원본 v_survey_insight_program)
CREATE OR REPLACE VIEW pbl3.v_survey_insight_program AS
SELECT p.program_id, p.program_name, p.program_date, 'pbl3'::TEXT AS data_source,
       (SELECT count(DISTINCT pp.student_no)
          FROM pbl3.program_participant pp
          JOIN pbl3.program_session s ON s.session_id = pp.session_id
         WHERE s.program_id = p.program_id AND pp.attendance_status = 'ATTENDED') AS attendance_count
  FROM pbl3.program p;

-- 3. 응답 단위 기초 (원본 v_survey_insight_base와 같은 컬럼)
--   pbl3는 (조사, 학생) UNIQUE라 모든 응답이 최신 응답이다
CREATE OR REPLACE VIEW pbl3.v_survey_insight_base AS
SELECT r.response_id, r.survey_id, s.program_id, p.program_name, p.data_source,
       r.student_no, r.dept_code_at_response AS dept_code, r.grade_at_response AS grade,
       r.responded_at AS submitted_at, r.started_at,
       extract(epoch FROM r.responded_at - r.started_at)::DOUBLE PRECISION AS duration_seconds,
       r.is_completed,
       r.is_completed AS is_latest,
       (SELECT count(*) FROM pbl3.survey_question q WHERE q.survey_id = r.survey_id AND q.question_type = 'SCALE') AS expected_questions,
       (SELECT count(*) FROM pbl3.survey_question q WHERE q.survey_id = r.survey_id) AS expected_all,
       -- 주관식은 선택 문항이라 응답 여부와 관계없이 채운 것으로 본다
       count(d.question_id) FILTER (WHERE q.question_type = 'SCALE' AND d.score BETWEEN 1 AND 5)
         + (SELECT count(*) FROM pbl3.survey_question q2 WHERE q2.survey_id = r.survey_id AND q2.question_type = 'TEXT') AS answered_all,
       count(d.score) FILTER (WHERE q.question_type = 'SCALE' AND d.score BETWEEN 1 AND 5) AS score_count,
       sum(d.score) FILTER (WHERE q.question_type = 'SCALE') AS score_sum,
       avg(d.score) FILTER (WHERE q.question_type = 'SCALE')::DOUBLE PRECISION AS mean_score,
       var_pop(d.score) FILTER (WHERE q.question_type = 'SCALE')::DOUBLE PRECISION AS score_variance,
       min(d.score) FILTER (WHERE q.question_type = 'SCALE') AS min_score,
       max(d.score) FILTER (WHERE q.question_type = 'SCALE') AS max_score,
       sv.session_id
  FROM pbl3.survey_response r
  JOIN pbl3.survey sv ON sv.survey_id = r.survey_id
  JOIN pbl3.program_session s ON s.session_id = sv.session_id
  JOIN pbl3.v_survey_insight_program p ON p.program_id = s.program_id
  LEFT JOIN pbl3.survey_response_detail d ON d.response_id = r.response_id
  LEFT JOIN pbl3.survey_question q ON q.question_id = d.question_id
 GROUP BY r.response_id, s.program_id, p.program_name, p.data_source, sv.session_id;

-- 4. 응답별 품질 (원본 analytics.fn_survey_quality와 동일 로직)
CREATE OR REPLACE FUNCTION pbl3.fn_survey_quality(p_config JSONB DEFAULT '{}', p_source TEXT DEFAULT 'pbl3')
RETURNS TABLE (
    response_id BIGINT, survey_id INT, program_id INT, program_name VARCHAR(100),
    student_no VARCHAR(20), dept_code VARCHAR(10), grade SMALLINT, submitted_at TIMESTAMPTZ,
    is_latest BOOLEAN, is_valid BOOLEAN, score_count BIGINT, score_sum BIGINT, mean_score DOUBLE PRECISION,
    score_variance DOUBLE PRECISION, duration_seconds DOUBLE PRECISION, seconds_per_question DOUBLE PRECISION,
    cohort_count BIGINT, survey_mean_seconds DOUBLE PRECISION, survey_median_seconds DOUBLE PRECISION,
    time_percentile DOUBLE PRECISION, absolute_fast BOOLEAN, relative_fast BOOLEAN, is_fast BOOLEAN,
    is_straight BOOLEAN, quality_score INT, is_suspicious BOOLEAN, response_type TEXT, reasons TEXT
) LANGUAGE plpgsql STABLE SET search_path = pg_catalog, pbl3 AS $$
DECLARE c pbl3.survey_insight_setting;
BEGIN
    IF p_source IS DISTINCT FROM 'pbl3' OR p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
        RAISE EXCEPTION 'invalid source/config' USING ERRCODE='22023';
    END IF;
    IF p_config - ARRAY['absolute_seconds','relative_fraction','relative_percentile','min_cohort','min_questions',
        'speed_mode','fast_penalty','straight_penalty','interaction_penalty','suspicious_below'] <> '{}'::JSONB THEN
        RAISE EXCEPTION 'unknown configuration key' USING ERRCODE='22023';
    END IF;
    SELECT * INTO c FROM jsonb_populate_record(NULL::pbl3.survey_insight_setting,
        (SELECT to_jsonb(x) FROM pbl3.survey_insight_setting x WHERE setting_id=1) || p_config);
    IF c.absolute_seconds IS NULL OR NOT (c.absolute_seconds>0 AND c.absolute_seconds<600)
      OR c.relative_fraction IS NULL OR NOT (c.relative_fraction>0 AND c.relative_fraction<1)
      OR c.relative_percentile IS NULL OR NOT (c.relative_percentile>0 AND c.relative_percentile<1)
      OR c.min_cohort IS NULL OR c.min_cohort<2 OR c.min_questions IS NULL OR c.min_questions<2
      OR c.speed_mode IS NULL OR c.speed_mode NOT IN ('absolute','relative','either','both')
      OR c.fast_penalty IS NULL OR c.fast_penalty NOT BETWEEN 0 AND 100
      OR c.straight_penalty IS NULL OR c.straight_penalty NOT BETWEEN 0 AND 100
      OR c.interaction_penalty IS NULL OR c.interaction_penalty NOT BETWEEN 0 AND 100
      OR c.suspicious_below IS NULL OR c.suspicious_below NOT BETWEEN 0 AND 100 THEN
        RAISE EXCEPTION 'invalid quality thresholds' USING ERRCODE='22023';
    END IF;
    RETURN QUERY
    WITH b AS (
        SELECT x.*, (x.is_completed AND isfinite(x.submitted_at) AND x.expected_questions>0 AND x.expected_questions=x.score_count
               AND x.expected_all=x.answered_all) AS valid
        FROM pbl3.v_survey_insight_base x
    ), timed AS (
        SELECT x.response_id,x.survey_id,x.duration_seconds,
          percent_rank() OVER (PARTITION BY x.survey_id ORDER BY x.duration_seconds) AS pct
        FROM b x WHERE x.valid AND x.is_latest AND x.duration_seconds IS NOT NULL AND x.duration_seconds>=0
    ), stats AS (
        SELECT t.survey_id,count(*) AS n,avg(t.duration_seconds) AS mean_t,
          percentile_cont(.5) WITHIN GROUP(ORDER BY t.duration_seconds) AS median_t
        FROM timed t GROUP BY t.survey_id
    ), signals AS (
        SELECT x.*, coalesce(st.n,0) AS n,st.mean_t,st.median_t,t.pct,
          x.duration_seconds/nullif(x.score_count,0) AS per_question,
          coalesce(x.duration_seconds/nullif(x.score_count,0)<c.absolute_seconds,false) AS abs_fast,
          coalesce(st.n>=c.min_cohort AND t.pct<=c.relative_percentile
                   AND x.duration_seconds<st.median_t*c.relative_fraction,false) AS rel_fast,
          coalesce(x.score_count>=c.min_questions AND x.min_score=x.max_score,false) AS straight
        FROM b x LEFT JOIN timed t ON t.response_id=x.response_id LEFT JOIN stats st ON st.survey_id=x.survey_id
    ), classified AS (
        SELECT x.*, CASE c.speed_mode WHEN 'absolute' THEN x.abs_fast WHEN 'relative' THEN x.rel_fast
          WHEN 'both' THEN x.abs_fast AND x.rel_fast ELSE x.abs_fast OR x.rel_fast END AS fast,
          (x.valid AND x.duration_seconds IS NOT NULL AND x.duration_seconds>=0
           AND x.score_count>=c.min_questions
           AND (c.speed_mode IN ('absolute','either') OR x.n>=c.min_cohort)) AS sufficient
        FROM signals x
    ), scored AS (
        SELECT x.*,CASE WHEN x.sufficient THEN greatest(0,100
          -CASE WHEN x.fast THEN c.fast_penalty ELSE 0 END
          -CASE WHEN x.straight THEN c.straight_penalty ELSE 0 END
          -CASE WHEN x.fast AND x.straight THEN c.interaction_penalty ELSE 0 END) END AS quality
        FROM classified x
    )
    SELECT x.response_id,x.survey_id,x.program_id,x.program_name,x.student_no,x.dept_code,x.grade,x.submitted_at,
      x.is_latest,x.valid,x.score_count,x.score_sum,x.mean_score,x.score_variance,x.duration_seconds,x.per_question,
      x.n,x.mean_t,x.median_t,x.pct,x.abs_fast,x.rel_fast,x.fast,x.straight,x.quality,
      coalesce(x.quality<c.suspicious_below,false),
      CASE WHEN NOT x.valid THEN '미완료 또는 유효하지 않은 응답'
           WHEN NOT x.sufficient THEN '분석 정보 부족'
           WHEN x.fast AND x.straight THEN '빠른 응답 + 동일 점수 반복'
           WHEN x.fast THEN '빠른 응답 의심'
           WHEN x.straight THEN '동일 점수 반복 의심' ELSE '정상 범위 응답' END,
      concat_ws('; ',
        CASE WHEN NOT x.valid THEN '미완료/점수 문항 누락/점수 없음: 집계 제외' END,
        CASE WHEN x.duration_seconds IS NULL THEN '시간 정보 없음: 품질 점수 미산출' END,
        CASE WHEN x.score_count<c.min_questions THEN '점수 문항 부족: 패턴 판단 보류' END,
        CASE WHEN x.n<c.min_cohort THEN '시간 표본 부족: 상대 기준 사용 불가' END,
        CASE WHEN x.fast THEN '빠른 응답 신호 (산출 가능 시 -'||c.fast_penalty||')' END,
        CASE WHEN x.straight THEN '동일 점수 반복: 실제 만족일 수 있음 (산출 가능 시 -'||c.straight_penalty||')' END,
        CASE WHEN x.fast AND x.straight THEN '두 신호 동시 발생 (산출 가능 시 -'||c.interaction_penalty||')' END,
        CASE WHEN x.duration_seconds>3600 THEN '장시간 열림: 실제 집중 시간과 다를 수 있음' END)
    FROM scored x;
END $$;

-- 5. 프로그램별 원본/제외/가중 평균 (원본과 동일. attendance_count는 pbl3 출석으로 채움)
CREATE OR REPLACE FUNCTION pbl3.fn_survey_summary(p_config JSONB DEFAULT '{}', p_source TEXT DEFAULT 'pbl3')
RETURNS TABLE(program_id INT,program_name VARCHAR(100),attendance_count BIGINT,response_count BIGINT,
    suspicious_count BIGINT,unknown_count BIGINT,original_mean DOUBLE PRECISION,
    filtered_mean DOUBLE PRECISION,weighted_mean DOUBLE PRECISION,suspicious_ratio DOUBLE PRECISION,
    mean_change DOUBLE PRECISION)
LANGUAGE sql STABLE SET search_path = pg_catalog, pbl3 AS $$
WITH q AS (SELECT * FROM pbl3.fn_survey_quality(p_config,p_source) WHERE is_latest AND is_valid),
agg AS (
 SELECT q.program_id,count(*) AS n,count(*) FILTER(WHERE is_suspicious) AS ns,
 count(*) FILTER(WHERE quality_score IS NULL) AS nu,
 sum(score_sum)::DOUBLE PRECISION/nullif(sum(score_count),0) AS original,
 sum(score_sum) FILTER(WHERE NOT is_suspicious)::DOUBLE PRECISION/
    nullif(sum(score_count) FILTER(WHERE NOT is_suspicious),0) AS filtered,
 sum(score_sum*coalesce(quality_score/100.0,1))/nullif(sum(score_count*coalesce(quality_score/100.0,1)),0) AS weighted
 FROM q GROUP BY q.program_id
)
SELECT p.program_id,p.program_name,p.attendance_count,coalesce(a.n,0),coalesce(a.ns,0),coalesce(a.nu,0),
 a.original,a.filtered,a.weighted::DOUBLE PRECISION,a.ns::DOUBLE PRECISION/nullif(a.n,0),a.filtered-a.original
FROM pbl3.v_survey_insight_program p LEFT JOIN agg a USING(program_id)
WHERE p_source = 'pbl3'
$$;

-- 6. 응답×문항분류 점수 (원본 v_survey_insight_category)
CREATE OR REPLACE VIEW pbl3.v_survey_insight_category AS
SELECT b.response_id, b.program_id, b.data_source, q.category_code, c.category_name,
       sum(d.score) AS score_sum, count(d.score) AS score_count
  FROM pbl3.v_survey_insight_base b
  JOIN pbl3.survey_response_detail d ON d.response_id = b.response_id
  JOIN pbl3.survey_question q ON q.question_id = d.question_id
  JOIN pbl3.survey_question_category c ON c.category_code = q.category_code
 WHERE b.is_latest AND b.is_completed AND q.question_type = 'SCALE'
 GROUP BY b.response_id, b.program_id, b.data_source, q.category_code, c.category_name;

-- 7. 출석 학생 수 (원본 v_program_attendance_count)
CREATE OR REPLACE VIEW pbl3.v_program_attendance_count AS
SELECT program_id, data_source, attendance_count FROM pbl3.v_survey_insight_program;

-- 8. 응답 후 90일 재참여 (원본 analytics.fn_survey_followup 구조 유지)
--   원본과 다른 점 하나: 원본은 프로그램이 1회짜리라 "다른 프로그램" 출석만 재참여로 셌다.
--   pbl3는 프로그램이 여러 회차이므로, 응답 이후의 "다음 회차(같은 프로그램 포함)" 출석을 재참여로 센다.
--   p_include_same_program = FALSE 로 주면 원본 정의(다른 프로그램만)로 계산한다.
--   기회(분모) = 응답 이후 90일 안에 열린 회차 중 그 학생이 대상이었던 회차 (pbl3.mv_candidate)
CREATE OR REPLACE FUNCTION pbl3.fn_survey_followup(p_asof TIMESTAMPTZ, p_source TEXT DEFAULT 'pbl3',
                                                   p_include_same_program BOOLEAN DEFAULT TRUE)
RETURNS TABLE(response_id BIGINT,followup_status TEXT,rejoined BOOLEAN,opportunity_count BIGINT)
LANGUAGE sql STABLE SET search_path = pg_catalog, pbl3 AS $$
WITH b AS (
    SELECT x.response_id, x.student_no, x.program_id, x.submitted_at, x.submitted_at + interval '90 days' AS horizon
      FROM pbl3.v_survey_insight_base x
     WHERE p_source = 'pbl3' AND x.is_latest AND x.is_completed
), ev AS (
    SELECT c.student_no, c.program_id, c.session_id,
           (c.session_date + c.start_time) AT TIME ZONE 'Asia/Seoul' AS scheduled_at,
           c.attended
      FROM pbl3.mv_candidate c
     WHERE c.session_status = 'COMPLETED'
), facts AS (
    SELECT b.response_id, b.submitted_at, b.horizon,
           EXISTS (SELECT 1 FROM ev
                    WHERE ev.student_no = b.student_no AND ev.attended
                      AND (p_include_same_program OR ev.program_id <> b.program_id)
                      AND ev.scheduled_at > b.submitted_at AND ev.scheduled_at <= least(b.horizon, p_asof)) AS positive,
           (SELECT count(*) FROM ev
             WHERE ev.student_no = b.student_no
               AND (p_include_same_program OR ev.program_id <> b.program_id)
               AND ev.scheduled_at > b.submitted_at AND ev.scheduled_at <= least(b.horizon, p_asof)) AS opportunities
      FROM b
), states AS (
    SELECT f.*, CASE
        WHEN p_asof IS NULL OR NOT isfinite(p_asof) OR f.submitted_at < c.observed_from THEN '기록 범위 불명'
        WHEN least(c.observed_through, p_asof) < f.horizon THEN '관찰 기간 부족'
        WHEN f.opportunities = 0 THEN '후속 기회 없음'
        ELSE '관찰 완료' END AS state
      FROM facts f
     CROSS JOIN pbl3.participation_coverage c
)
SELECT s.response_id, s.state,
       CASE WHEN s.state = '관찰 완료' THEN s.positive END,
       s.opportunities
  FROM states s
$$;

-- db.py가 연결 여부를 확인할 때 쓰는 표 (pbl3는 항상 연결 상태)
DROP TABLE IF EXISTS pbl3.survey_participation_setting CASCADE;
CREATE TABLE pbl3.survey_participation_setting (
    setting_id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (setting_id = 1),
    attendance_connected BOOLEAN NOT NULL DEFAULT TRUE,
    opportunity_connected BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO pbl3.survey_participation_setting (setting_id) VALUES (1);

GRANT SELECT ON ALL TABLES IN SCHEMA pbl3 TO analytics_reader;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pbl3 TO analytics_reader;
COMMIT;
