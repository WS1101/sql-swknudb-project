\encoding UTF8
\set ON_ERROR_STOP on
-- 12_pbl3_views.sql : 팀 공통 분석 뷰 (pbl3만 읽음, 정답지 pbl3_truth는 사용하지 않음)
-- 담당: 서우진
--   mv_candidate          회차 × 대상 학생 1행. 2번(참여 원인) 모델 입력, 4번(학생) 집계 재료
--   v_session_overview    회차 1행. 대상 인원·수업 충돌률·신청·출석·만족도·비용
--   v_response_scored     응답 1행. 문항분류별 점수 가로 펼침 + 일괄 응답 표시 (1번)
--   v_program_cost        프로그램 1행. 비용·고유 출석자·만족 출석자·재참여자 단가 (3번)
--   v_student_activity    학생 1행. 참여 이력·이탈 신호 (4번)

BEGIN;
SET LOCAL search_path = pbl3, public;

DROP MATERIALIZED VIEW IF EXISTS pbl3.mv_candidate CASCADE;

-- ---------------------------------------------------------------------
-- 회차 × 대상 학생
--   대상: 회차 일자에 1~4학년이고 휴학·자퇴 상태가 아닌 학생
--   모든 컬럼은 그 회차 "이전"에 관측 가능한 정보만 사용 (예측에 미래 정보가 새지 않도록)
--   SCHEDULED 회차도 포함 → registered/attended가 NULL인 행이 예측 대상
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW pbl3.mv_candidate AS
WITH sess AS (
    SELECT s.*, p.program_type_code, p.series_key,
           COALESCE(mc.participation_mileage, 0) AS mileage,
           t.term_id, t.term_code,
           pbl3.fn_near_exam(s.session_date) AS near_exam,
           pbl3.fn_in_semester(s.session_date) AS in_semester,
           prev.session_id AS prev_session_id
      FROM pbl3.program_session s
      JOIN pbl3.program p ON p.program_id = s.program_id
      LEFT JOIN pbl3.mileage_criteria mc ON mc.program_id = s.program_id
      JOIN pbl3.academic_term t ON s.session_date BETWEEN t.start_date AND t.end_date
      LEFT JOIN pbl3.program_session prev ON prev.program_id = s.program_id AND prev.session_no = s.session_no - 1
), prev_avg AS (
    SELECT sv.session_id, avg(d.score) AS avg_content
      FROM pbl3.survey sv
      JOIN pbl3.survey_response rs ON rs.survey_id = sv.survey_id AND rs.is_completed
      JOIN pbl3.survey_response_detail d ON d.response_id = rs.response_id
      JOIN pbl3.survey_question q ON q.question_id = d.question_id AND q.category_code = 'CONTENT'
     GROUP BY sv.session_id
), own_content AS (
    SELECT sv.session_id, rs.student_no, d.score
      FROM pbl3.survey sv
      JOIN pbl3.survey_response rs ON rs.survey_id = sv.survey_id AND rs.is_completed
      JOIN pbl3.survey_response_detail d ON d.response_id = rs.response_id
      JOIN pbl3.survey_question q ON q.question_id = d.question_id AND q.category_code = 'CONTENT'
), hist AS (
    SELECT pp.student_no, s.session_date, pp.attendance_status
      FROM pbl3.program_participant pp
      JOIN pbl3.program_session s ON s.session_id = pp.session_id
)
SELECT se.session_id, st.student_no,
       se.program_id, se.program_type_code, se.series_key, se.session_no, se.session_date, se.session_status,
       se.term_id, se.term_code,
       st.dept_code, d.track_type, d.campus_code AS student_campus, st.admission_type, g.grade_at,
       EXTRACT(ISODOW FROM se.session_date)::INT              AS weekday_iso,
       EXTRACT(HOUR FROM se.start_time)::INT                  AS start_hour,
       se.start_time, se.delivery_mode = 'ONLINE'             AS is_online,
       se.mileage, se.near_exam, se.in_semester,
       EXISTS (SELECT 1 FROM pbl3.course_timetable ct
                WHERE ct.dept_code = st.dept_code AND ct.grade = g.grade_at AND ct.term_id = se.term_id
                  AND ct.weekday_iso = EXTRACT(ISODOW FROM se.session_date)
                  AND se.start_time < ct.end_time AND se.end_time > ct.start_time) AS class_conflict,
       (se.delivery_mode = 'OFFLINE' AND d.campus_code <> se.campus_code)        AS cross_campus,
       -- 직전 회차 관련 (관측 가능 정보)
       COALESCE(pp_prev.attendance_status = 'ATTENDED', FALSE) AS prev_attended,
       oc.score                                               AS prev_own_content,
       pa.avg_content                                         AS prev_session_avg_content,
       -- 과거 참여 이력 (이 회차 이전)
       h.past_attended, h.past_registered, h.past_no_show, h.days_since_last_attended,
       NOT EXISTS (SELECT 1 FROM pbl3.student_info_change_request r
                    WHERE r.student_no = st.student_no AND r.field_name = 'sms_opt_in'
                      AND r.new_value = 'false' AND r.status = 'APPROVED'
                      AND r.processed_at < se.session_date)   AS sms_opt_in_at,
       -- 결과 (SCHEDULED 회차는 NULL)
       CASE WHEN se.session_status = 'COMPLETED' THEN pp.student_no IS NOT NULL END              AS registered,
       CASE WHEN se.session_status = 'COMPLETED' THEN COALESCE(pp.attendance_status = 'ATTENDED', FALSE) END AS attended
  FROM sess se
 CROSS JOIN pbl3.student st
  JOIN pbl3.department d ON d.dept_code = st.dept_code
 CROSS JOIN LATERAL (SELECT pbl3.fn_grade_at(st.admission_date, st.admission_type, se.session_date) AS grade_at) g
  LEFT JOIN pbl3.program_participant pp      ON pp.session_id = se.session_id AND pp.student_no = st.student_no
  LEFT JOIN pbl3.program_participant pp_prev ON pp_prev.session_id = se.prev_session_id AND pp_prev.student_no = st.student_no
  LEFT JOIN own_content oc ON oc.session_id = se.prev_session_id AND oc.student_no = st.student_no
  LEFT JOIN prev_avg pa    ON pa.session_id = se.prev_session_id
 CROSS JOIN LATERAL (
    SELECT count(*) FILTER (WHERE hh.attendance_status = 'ATTENDED') AS past_attended,
           count(*)                                                AS past_registered,
           count(*) FILTER (WHERE hh.attendance_status = 'NO_SHOW')  AS past_no_show,
           se.session_date - max(hh.session_date) FILTER (WHERE hh.attendance_status = 'ATTENDED') AS days_since_last_attended
      FROM hist hh
     WHERE hh.student_no = st.student_no AND hh.session_date < se.session_date) h
 WHERE g.grade_at IS NOT NULL
   AND NOT (st.enrollment_status IN ('WITHDRAWN', 'ON_LEAVE') AND st.status_change_date <= se.session_date);

CREATE UNIQUE INDEX ix_p3_mv_candidate ON pbl3.mv_candidate (session_id, student_no);
CREATE INDEX ix_p3_mv_candidate_student ON pbl3.mv_candidate (student_no);

COMMENT ON MATERIALIZED VIEW pbl3.mv_candidate IS
    '회차×대상학생. 회차 이전 관측 정보만 포함. 데이터 재생성 후 REFRESH MATERIALIZED VIEW 필요';

-- ---------------------------------------------------------------------
-- 회차 요약
-- ---------------------------------------------------------------------
CREATE VIEW pbl3.v_session_overview AS
WITH c AS (
    SELECT session_id, count(*) AS eligible,
           avg(class_conflict::INT) AS conflict_rate,
           avg(cross_campus::INT)   AS cross_campus_rate
      FROM pbl3.mv_candidate GROUP BY session_id
), pp AS (
    SELECT session_id,
           count(*) AS registered,
           count(*) FILTER (WHERE attendance_status = 'ATTENDED')  AS attended,
           count(*) FILTER (WHERE attendance_status = 'NO_SHOW')   AS no_show,
           count(*) FILTER (WHERE attendance_status = 'CANCELLED') AS cancelled
      FROM pbl3.program_participant GROUP BY session_id
), sc AS (
    SELECT sv.session_id, count(DISTINCT rs.response_id) AS responses,
           avg(d.score) FILTER (WHERE q.category_code = 'CONTENT')    AS avg_content,
           avg(d.score) FILTER (WHERE q.category_code = 'INSTRUCTOR') AS avg_instructor,
           avg(d.score) FILTER (WHERE q.category_code = 'OPERATION')  AS avg_operation,
           avg(d.score) FILTER (WHERE q.category_code = 'FACILITY')   AS avg_facility,
           avg(d.score) FILTER (WHERE q.category_code = 'SCHEDULE')   AS avg_schedule
      FROM pbl3.survey sv
      JOIN pbl3.survey_response rs ON rs.survey_id = sv.survey_id AND rs.is_completed
      JOIN pbl3.survey_response_detail d ON d.response_id = rs.response_id
      JOIN pbl3.survey_question q ON q.question_id = d.question_id AND q.question_type = 'SCALE'
     GROUP BY sv.session_id
), cost AS (
    SELECT session_id, sum(amount) AS approved_cost
      FROM pbl3.expenditure WHERE status = 'APPROVED' GROUP BY session_id
)
SELECT s.session_id, s.program_id, p.program_name, p.program_type_code, p.series_key,
       s.session_no, s.session_date, EXTRACT(ISODOW FROM s.session_date)::INT AS weekday_iso,
       s.start_time, s.end_time, s.delivery_mode, s.campus_code, s.session_status, p.capacity,
       pbl3.fn_near_exam(s.session_date)   AS near_exam,
       pbl3.fn_in_semester(s.session_date) AS in_semester,
       c.eligible, round(c.conflict_rate, 3) AS conflict_rate, round(c.cross_campus_rate, 3) AS cross_campus_rate,
       COALESCE(pp.registered, 0) AS registered, COALESCE(pp.attended, 0) AS attended,
       COALESCE(pp.no_show, 0) AS no_show, COALESCE(pp.cancelled, 0) AS cancelled,
       round(pp.attended::NUMERIC / NULLIF(pp.registered, 0), 3) AS show_rate,
       round(pp.attended::NUMERIC / NULLIF(c.eligible, 0), 4)    AS participation_rate,
       COALESCE(sc.responses, 0) AS responses,
       round(sc.avg_content, 2) AS avg_content, round(sc.avg_instructor, 2) AS avg_instructor,
       round(sc.avg_operation, 2) AS avg_operation, round(sc.avg_facility, 2) AS avg_facility,
       round(sc.avg_schedule, 2) AS avg_schedule,
       cost.approved_cost
  FROM pbl3.program_session s
  JOIN pbl3.program p ON p.program_id = s.program_id
  LEFT JOIN c    ON c.session_id = s.session_id
  LEFT JOIN pp   ON pp.session_id = s.session_id
  LEFT JOIN sc   ON sc.session_id = s.session_id
  LEFT JOIN cost ON cost.session_id = s.session_id;

-- ---------------------------------------------------------------------
-- 응답 1행: 분류별 점수 + 일괄 응답 여부 + 다음 회차 재참여 여부
-- ---------------------------------------------------------------------
CREATE VIEW pbl3.v_response_scored AS
SELECT rs.response_id, sv.session_id, sv.program_id, s.session_no, rs.student_no,
       rs.grade_at_response, rs.dept_code_at_response, rs.responded_at, rs.is_completed,
       max(d.score) FILTER (WHERE q.category_code = 'CONTENT')    AS content,
       max(d.score) FILTER (WHERE q.category_code = 'INSTRUCTOR') AS instructor,
       max(d.score) FILTER (WHERE q.category_code = 'OPERATION')  AS operation,
       max(d.score) FILTER (WHERE q.category_code = 'FACILITY')   AS facility,
       max(d.score) FILTER (WHERE q.category_code = 'SCHEDULE')   AS schedule,
       max(d.text_answer)                                         AS text_answer,
       rs.is_completed AND count(d.score) = 5 AND min(d.score) = max(d.score) AS is_straightline,
       -- 다음 회차가 있었는가, 그 회차에 출석했는가 (1번 재참여 분석용)
       nxt.session_id IS NOT NULL AND nxt.session_status = 'COMPLETED' AS has_next_session,
       CASE WHEN nxt.session_status = 'COMPLETED'
            THEN EXISTS (SELECT 1 FROM pbl3.program_participant x
                          WHERE x.session_id = nxt.session_id AND x.student_no = rs.student_no
                            AND x.attendance_status = 'ATTENDED') END AS returned_next
  FROM pbl3.survey_response rs
  JOIN pbl3.survey sv ON sv.survey_id = rs.survey_id
  JOIN pbl3.program_session s ON s.session_id = sv.session_id
  LEFT JOIN pbl3.program_session nxt ON nxt.program_id = s.program_id AND nxt.session_no = s.session_no + 1
  LEFT JOIN pbl3.survey_response_detail d ON d.response_id = rs.response_id
  LEFT JOIN pbl3.survey_question q ON q.question_id = d.question_id
 GROUP BY rs.response_id, sv.session_id, sv.program_id, s.session_no, nxt.session_id, nxt.session_status;

-- ---------------------------------------------------------------------
-- 프로그램 비용 효율 (3번)
--   만족 출석자: 완료 응답의 척도 5문항 평균 4 이상 (일괄 응답 제외)
--   재참여자: 같은 프로그램에 2회 이상 출석
-- ---------------------------------------------------------------------
CREATE VIEW pbl3.v_program_cost AS
WITH cost AS (
    SELECT program_id, sum(amount) AS approved_cost
      FROM pbl3.expenditure WHERE status = 'APPROVED' GROUP BY program_id
), att AS (
    SELECT s.program_id, pp.student_no, count(*) AS sessions_attended
      FROM pbl3.program_participant pp
      JOIN pbl3.program_session s ON s.session_id = pp.session_id
     WHERE pp.attendance_status = 'ATTENDED'
     GROUP BY s.program_id, pp.student_no
), sat AS (
    SELECT program_id, student_no,
           avg((content + instructor + operation + facility + schedule) / 5.0) AS avg_score
      FROM pbl3.v_response_scored
     WHERE is_completed AND NOT is_straightline
     GROUP BY program_id, student_no
)
SELECT p.program_id, p.program_name, p.program_type_code, p.series_key, p.organizer,
       (SELECT count(*) FROM pbl3.program_session s WHERE s.program_id = p.program_id AND s.session_status = 'COMPLETED') AS sessions_completed,
       c.approved_cost,
       count(a.student_no)                                    AS unique_attendees,
       COALESCE(sum(a.sessions_attended), 0)                  AS attendance_records,
       count(a.student_no) FILTER (WHERE a.sessions_attended >= 2) AS returning_attendees,
       count(st.student_no) FILTER (WHERE st.avg_score >= 4)  AS satisfied_attendees,
       round(avg(st.avg_score), 2)                            AS avg_satisfaction,
       round(c.approved_cost / NULLIF(sum(a.sessions_attended), 0))                     AS cost_per_attendance,
       round(c.approved_cost / NULLIF(count(a.student_no), 0))                          AS cost_per_unique_attendee,
       round(c.approved_cost / NULLIF(count(st.student_no) FILTER (WHERE st.avg_score >= 4), 0)) AS cost_per_satisfied,
       round(c.approved_cost / NULLIF(count(a.student_no) FILTER (WHERE a.sessions_attended >= 2), 0)) AS cost_per_returning
  FROM pbl3.program p
  LEFT JOIN cost c ON c.program_id = p.program_id
  LEFT JOIN att a  ON a.program_id = p.program_id
  LEFT JOIN sat st ON st.program_id = a.program_id AND st.student_no = a.student_no
 GROUP BY p.program_id, c.approved_cost;

-- ---------------------------------------------------------------------
-- 학생 활동 요약 (4번)
-- ---------------------------------------------------------------------
CREATE VIEW pbl3.v_student_activity AS
WITH h AS (
    SELECT pp.student_no,
           count(*) AS registered,
           count(*) FILTER (WHERE pp.attendance_status = 'ATTENDED') AS attended,
           count(*) FILTER (WHERE pp.attendance_status = 'NO_SHOW')  AS no_show,
           count(DISTINCT s.program_id) FILTER (WHERE pp.attendance_status = 'ATTENDED') AS programs_attended,
           min(s.session_date) FILTER (WHERE pp.attendance_status = 'ATTENDED') AS first_attended,
           max(s.session_date) FILTER (WHERE pp.attendance_status = 'ATTENDED') AS last_attended,
           count(*) FILTER (WHERE pp.attendance_status = 'ATTENDED' AND s.session_date >= DATE '2026-09-01') AS attended_this_term
      FROM pbl3.program_participant pp
      JOIN pbl3.program_session s ON s.session_id = pp.session_id
     GROUP BY pp.student_no
), r AS (
    SELECT student_no, count(*) AS responses, count(*) FILTER (WHERE NOT is_completed) AS incomplete_responses
      FROM pbl3.survey_response GROUP BY student_no
), sms AS (
    SELECT student_no, min(processed_at)::DATE AS sms_opt_out_date
      FROM pbl3.student_info_change_request
     WHERE field_name = 'sms_opt_in' AND new_value = 'false' AND status = 'APPROVED'
     GROUP BY student_no
)
SELECT st.student_no, st.dept_code, d.dept_name, d.track_type, d.campus_code,
       st.grade, st.admission_type, st.admission_date, st.enrollment_status, st.status_change_date,
       st.sms_opt_in, sms.sms_opt_out_date,
       COALESCE(h.registered, 0) AS registered, COALESCE(h.attended, 0) AS attended,
       COALESCE(h.no_show, 0) AS no_show, COALESCE(h.programs_attended, 0) AS programs_attended,
       h.first_attended, h.last_attended, COALESCE(h.attended_this_term, 0) AS attended_this_term,
       COALESCE(r.responses, 0) AS survey_responses, COALESCE(r.incomplete_responses, 0) AS incomplete_responses
  FROM pbl3.student st
  JOIN pbl3.department d ON d.dept_code = st.dept_code
  LEFT JOIN h   ON h.student_no = st.student_no
  LEFT JOIN r   ON r.student_no = st.student_no
  LEFT JOIN sms ON sms.student_no = st.student_no;

GRANT SELECT ON ALL TABLES IN SCHEMA pbl3 TO analytics_reader;
COMMIT;
