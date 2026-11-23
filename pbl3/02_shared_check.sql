\encoding UTF8
\set ON_ERROR_STOP on
\pset pager off
\echo ===== PBL3 공유 데이터 건수 =====
SELECT '프로그램 회차' AS item,count(*) AS rows FROM pbl3.program_session
UNION ALL SELECT '회차 신청/출석',count(*) FROM pbl3.program_participant
UNION ALL SELECT '수업시간표',count(*) FROM pbl3.course_timetable
UNION ALL SELECT '가상 시험기간',count(*) FROM pbl3.academic_event;

\echo ===== 프로그램별 회차/출석/노쇼 =====
SELECT p.program_name, count(DISTINCT ps.session_id) AS sessions,
       count(*) FILTER(WHERE pp.attendance_status='ATTENDED') AS attended_records,
       count(*) FILTER(WHERE pp.attendance_status='NO_SHOW') AS no_shows,
       count(DISTINCT pp.student_no) FILTER(WHERE pp.attendance_status='ATTENDED') AS unique_attendees
FROM public.program p
JOIN pbl3.program_session ps ON ps.program_id=p.program_id
LEFT JOIN pbl3.program_participant pp ON pp.session_id=ps.session_id
GROUP BY p.program_id,p.program_name
ORDER BY p.program_name;

\echo ===== 출석률과 수업 충돌 비교 (상관관계 참고, 인과 증명 아님) =====
WITH registrations AS (
 SELECT pp.attendance_status, EXISTS (
      SELECT 1 FROM pbl3.course_timetable ct
      JOIN public.student s ON s.student_no=pp.student_no
      WHERE ct.dept_code=s.dept_code AND ct.grade=s.grade
        AND ct.weekday_iso=EXTRACT(ISODOW FROM ps.session_date)::INT
        AND ps.session_date BETWEEN ct.term_start AND ct.term_end
        AND ps.start_time<ct.end_time AND ps.end_time>ct.start_time
    ) AS class_conflict
 FROM pbl3.program_participant pp
 JOIN pbl3.program_session ps ON ps.session_id=pp.session_id
)
SELECT class_conflict,count(*) AS registrations,
       count(*) FILTER (WHERE attendance_status='ATTENDED') AS attended,
       round(100.0*count(*) FILTER(WHERE attendance_status='ATTENDED')/NULLIF(count(*),0),1) AS attendance_pct
FROM registrations GROUP BY class_conflict ORDER BY class_conflict;

\echo ===== 기존 설문 완료자 가운데 본행사 미출석 건수 (0이어야 함) =====
SELECT count(*) AS survey_without_attendance
FROM analytics.v_survey_response_final f
JOIN pbl3.program_session ps ON ps.program_id=f.program_id AND ps.session_no=5
LEFT JOIN pbl3.program_participant pp
  ON pp.session_id=ps.session_id AND pp.student_no=f.student_no
WHERE pp.attendance_status IS DISTINCT FROM 'ATTENDED';
