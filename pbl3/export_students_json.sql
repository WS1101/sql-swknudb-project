\encoding UTF8
\set ON_ERROR_STOP on
-- 학생 활동 조회 화면 데이터: pbl3.v_student_term_activity → docs/data/students.json
--   저장소 루트에서:  psql -d swknu_db -XAtq -f pbl3/export_students_json.sql
--   이름·연락처는 내보내지 않는다 (학번·학과·학년만)
\o docs/data/students.json
WITH terms AS (
    SELECT term_id, term_year, term_code,
           right(term_year::TEXT, 2) || CASE term_code WHEN '1' THEN '-1학기' WHEN '2' THEN '-2학기'
                                                       WHEN 'S' THEN ' 여름' ELSE ' 겨울' END AS label
      FROM pbl3.academic_term
     WHERE start_date <= (SELECT as_of_date FROM pbl3.generation_meta)
), stu AS (
    SELECT s.student_no, d.dept_name, s.grade, s.admission_type, s.enrollment_status,
           to_char(s.admission_date, 'YYYY') AS adm_year,
           CASE WHEN s.enrollment_status = 'GRADUATED' THEN '졸업' ELSE s.grade || '학년' END AS grp
      FROM pbl3.student s JOIN pbl3.department d USING (dept_code)
), tot AS (
    SELECT a.student_no, sum(attended_sessions) AS att, sum(mileage_est) AS mil, sum(no_show) AS ns
      FROM pbl3.v_student_term_activity a GROUP BY 1
), ranked AS (
    SELECT stu.*, tot.att, tot.mil, tot.ns,
           round(100 * (1 - percent_rank() OVER (PARTITION BY stu.grp ORDER BY tot.att))) AS top_pct
      FROM stu JOIN tot USING (student_no)
), grp_avg AS (
    SELECT r.grp, a.term_id, round(avg(a.attended_sessions), 2) AS avg_att
      FROM pbl3.v_student_term_activity a JOIN ranked r USING (student_no)
     GROUP BY 1, 2
)
SELECT json_build_object(
  'asOf', (SELECT as_of_date FROM pbl3.generation_meta),
  'terms', (SELECT json_agg(json_build_object('id', term_id, 'label', label) ORDER BY term_year, term_id) FROM terms),
  'groupAvg', (SELECT json_object_agg(grp, js) FROM (
                 SELECT grp, json_object_agg(term_id, avg_att) AS js FROM grp_avg GROUP BY grp) g),
  'students', (SELECT json_agg(json_build_object(
       'no', r.student_no, 'dept', r.dept_name, 'grp', r.grp, 'adm', r.adm_year,
       'tr', r.admission_type = 'TRANSFER', 'st', r.enrollment_status,
       'att', r.att, 'mil', r.mil, 'ns', r.ns, 'top', r.top_pct,
       'terms', (SELECT json_agg(json_build_array(a.term_id, a.attended_sessions, a.mileage_est) ORDER BY a.term_id)
                   FROM pbl3.v_student_term_activity a WHERE a.student_no = r.student_no),
       'progs', (SELECT json_agg(json_build_object('p', x.program_name, 'n', x.n) ORDER BY x.last DESC)
                   FROM (SELECT p.program_name, count(*) AS n, max(s.session_date) AS last
                           FROM pbl3.program_participant pp
                           JOIN pbl3.program_session s USING (session_id)
                           JOIN pbl3.program p USING (program_id)
                          WHERE pp.student_no = r.student_no AND pp.attendance_status = 'ATTENDED'
                          GROUP BY p.program_name) x)
     ) ORDER BY r.student_no) FROM ranked r)
);
\o
