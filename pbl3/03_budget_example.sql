\encoding UTF8
\set ON_ERROR_STOP on
\pset pager off
-- 임영효 파트: 프로그램과 연결된 승인 지출 / 출석 인원 / 만족 응답자당 비용.
-- 프로그램에 연결되지 않은 공통 지출은 제외한다. 출석·만족 데이터는 가상 시드이다.
WITH budget AS (
    SELECT program_id,SUM(amount) AS approved_spending
    FROM public.expenditure
    WHERE status='APPROVED' AND program_id IS NOT NULL
    GROUP BY program_id
), attendees AS (
    SELECT ps.program_id,pp.student_no
    FROM pbl3.program_session ps
    JOIN pbl3.program_participant pp ON pp.session_id=ps.session_id
    WHERE pp.attendance_status='ATTENDED'
    GROUP BY ps.program_id,pp.student_no
), attendance_counts AS (
    SELECT program_id,count(*) AS unique_attendees FROM attendees GROUP BY program_id
), satisfaction AS (
    SELECT f.program_id,f.student_no,AVG(d.score)::NUMERIC AS avg_student_score
    FROM analytics.v_survey_response_final f
    JOIN public.survey_response_detail d ON d.response_id=f.response_id
    JOIN public.survey_question q ON q.question_id=d.question_id AND q.question_type='SCALE'
    GROUP BY f.program_id,f.student_no
), satisfied_counts AS (
    SELECT a.program_id, count(*) AS satisfied_attendees
    FROM attendees a JOIN satisfaction s
      ON s.program_id=a.program_id AND s.student_no=a.student_no
    WHERE s.avg_student_score >= 4
    GROUP BY a.program_id
)
SELECT p.program_id,p.program_name,
       b.approved_spending AS program_linked_approved_spending,
       COALESCE(a.unique_attendees,0) AS distinct_attendees,
       COALESCE(sc.satisfied_attendees,0) AS satisfied_surveyed_attendees,
       round(b.approved_spending::NUMERIC/NULLIF(a.unique_attendees,0),0) AS spending_per_attendee,
       round(b.approved_spending::NUMERIC/NULLIF(sc.satisfied_attendees,0),0) AS spending_per_satisfied_respondent
FROM public.program p
LEFT JOIN budget b ON b.program_id=p.program_id
LEFT JOIN attendance_counts a ON a.program_id=p.program_id
LEFT JOIN satisfied_counts sc ON sc.program_id=p.program_id
WHERE p.program_name LIKE 'SEED %'
ORDER BY p.program_date,p.program_id;
