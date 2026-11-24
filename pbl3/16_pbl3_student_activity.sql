\encoding UTF8
\set ON_ERROR_STOP on
-- 16_pbl3_student_activity.sql : 학생 활동 조회 (사업단 자문 요청)
--   "학번을 치면 학기별로 얼마나 참여했고 마일리지를 얼마나 쌓았는지 그래프로"
--   새 테이블 없이 기존 출석·회차·학기·마일리지 기준으로 계산하는 뷰
--
--   v_student_term_activity  학생 × 학기: 출석 회차, 참여 프로그램, 노쇼, 예상 적립 마일리지
--
-- 마일리지: pbl3에는 마일리지 신청·승인 기록이 없으므로
--   "프로그램에 처음 출석한 학기에 그 프로그램의 참여 마일리지를 1회 적립"으로 추정한다.
--   실제 운영에서는 public.mileage_application(APPROVED)으로 바꾼다.

BEGIN;
SET LOCAL search_path = pbl3, public;

DROP VIEW IF EXISTS pbl3.v_student_term_activity;
CREATE VIEW pbl3.v_student_term_activity AS
WITH att AS (
    SELECT pp.student_no, s.program_id, s.session_date, pp.attendance_status, t.term_id
      FROM pbl3.program_participant pp
      JOIN pbl3.program_session s ON s.session_id = pp.session_id
      JOIN pbl3.academic_term t ON s.session_date BETWEEN t.start_date AND t.end_date
), first_att AS (
    SELECT DISTINCT ON (student_no, program_id) student_no, program_id, term_id
      FROM att WHERE attendance_status = 'ATTENDED'
     ORDER BY student_no, program_id, session_date
), mil AS (
    SELECT f.student_no, f.term_id, sum(COALESCE(mc.participation_mileage, 0)) AS mileage_est
      FROM first_att f LEFT JOIN pbl3.mileage_criteria mc USING (program_id)
     GROUP BY 1, 2
), agg AS (
    SELECT student_no, term_id,
           count(*) FILTER (WHERE attendance_status = 'ATTENDED')                      AS attended_sessions,
           count(DISTINCT program_id) FILTER (WHERE attendance_status = 'ATTENDED')    AS programs_attended,
           count(*) FILTER (WHERE attendance_status = 'NO_SHOW')                       AS no_show
      FROM att GROUP BY 1, 2
)
SELECT st.student_no, t.term_id, t.term_year, t.term_code,
       COALESCE(a.attended_sessions, 0) AS attended_sessions,
       COALESCE(a.programs_attended, 0) AS programs_attended,
       COALESCE(a.no_show, 0)           AS no_show,
       COALESCE(m.mileage_est, 0)       AS mileage_est
  FROM pbl3.student st
 CROSS JOIN pbl3.academic_term t
  LEFT JOIN agg a ON a.student_no = st.student_no AND a.term_id = t.term_id
  LEFT JOIN mil m ON m.student_no = st.student_no AND m.term_id = t.term_id
 WHERE t.start_date <= (SELECT as_of_date FROM pbl3.generation_meta)
   AND t.end_date >= st.admission_date
   -- 졸업·자퇴 이후 학기는 제외 (활동이 없는 것이 당연하므로)
   AND NOT (st.enrollment_status IN ('GRADUATED', 'WITHDRAWN') AND t.start_date > st.status_change_date);

COMMENT ON VIEW pbl3.v_student_term_activity IS
    '학생×학기 활동. 마일리지는 출석 기준 추정치(프로그램당 첫 출석 학기에 1회)';

GRANT SELECT ON pbl3.v_student_term_activity TO analytics_reader;
COMMIT;
