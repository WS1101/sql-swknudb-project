\encoding UTF8
\set ON_ERROR_STOP on
-- 2026년 가상 분석 데이터. 고정 규칙으로 생성되어 재실행해도 결과가 같다.
-- 미션2 public 테이블 및 기존 시드는 변경하지 않는다.
BEGIN;
SET LOCAL search_path = public, pg_temp;

DO $$ BEGIN
    IF (SELECT count(*) FROM public.program WHERE program_name LIKE 'SEED %') < 10
       OR (SELECT count(*) FROM public.student) < 32 THEN
        RAISE EXCEPTION '미션2 reset.sql 및 기본 시드를 먼저 실행해야 합니다.';
    END IF;
END $$;

-- 실제 학교 학사일정이 아닌 시연용 시험기간
INSERT INTO pbl3.academic_event(event_name,event_type,start_date,end_date)
VALUES
  ('PBL3 1학기 중간고사(가상)','MIDTERM',DATE '2026-04-13',DATE '2026-04-24'),
  ('PBL3 1학기 기말고사(가상)','FINAL',  DATE '2026-06-08',DATE '2026-06-19'),
  ('PBL3 2학기 중간고사(가상)','MIDTERM',DATE '2026-10-12',DATE '2026-10-23'),
  ('PBL3 2학기 기말고사(가상)','FINAL',  DATE '2026-12-07',DATE '2026-12-18')
ON CONFLICT(event_name,start_date) DO NOTHING;

-- 학과·학년별 대표 시간표: 각 학기, 월~금, 오전/오후 2개 시간대
WITH terms AS (
    SELECT DATE '2026-03-02' AS term_start,DATE '2026-06-19' AS term_end,1 AS term_no
    UNION ALL SELECT DATE '2026-09-01',DATE '2026-12-18',2
), slots AS (
    SELECT d.dept_code,g.grade,wd.weekday_iso,sl.slot_no,t.term_start,t.term_end,t.term_no,
        CASE WHEN sl.slot_no=1 THEN
            CASE ((g.grade+wd.weekday_iso+t.term_no)%3)
                WHEN 0 THEN TIME '09:00' WHEN 1 THEN TIME '10:00' ELSE TIME '11:00' END
        ELSE CASE ((g.grade+wd.weekday_iso+t.term_no)%3)
                WHEN 0 THEN TIME '13:00' WHEN 1 THEN TIME '14:00' ELSE TIME '15:00' END
        END AS start_time
    FROM public.department d
    CROSS JOIN generate_series(1,4) g(grade)
    CROSS JOIN generate_series(1,5) wd(weekday_iso)
    CROSS JOIN generate_series(1,2) sl(slot_no)
    CROSS JOIN terms t
    WHERE d.dept_code LIKE 'SEED_%'
)
INSERT INTO pbl3.course_timetable
(dept_code,grade,weekday_iso,start_time,end_time,term_start,term_end,course_label)
SELECT dept_code,grade,weekday_iso,start_time,
       (start_time+INTERVAL '90 minutes')::TIME,term_start,term_end,
       'PBL3 가상 수업 '||term_no||'학기-'||slot_no
FROM slots
ON CONFLICT(dept_code,grade,weekday_iso,start_time,term_start) DO NOTHING;

-- 기존 프로그램 10개의 준비/본 행사 5회차. 날짜·시간은 시연용 가상 값
WITH programs AS (
    SELECT p.*, row_number() OVER (ORDER BY p.program_date,p.program_id) AS program_order
    FROM public.program p WHERE p.program_name LIKE 'SEED %'
), seq AS (
    SELECT p.*,g.session_no,
           p.program_date - (ARRAY[28,22,16,10,0])[g.session_no] AS session_date,
           CASE ((p.program_order+g.session_no)%4)
              WHEN 0 THEN TIME '09:00'
              WHEN 1 THEN TIME '11:00'
              WHEN 2 THEN TIME '14:00'
              ELSE TIME '16:00' END AS start_time
    FROM programs p CROSS JOIN generate_series(1,5) g(session_no)
)
INSERT INTO pbl3.program_session
(program_id,session_no,session_date,start_time,end_time,campus_code,location_name,series_code,delivery_mode)
SELECT program_id,session_no,session_date,start_time,(start_time+INTERVAL '2 hours')::TIME,
       CASE WHEN program_order%4=0 THEN 'SEED_B' ELSE 'SEED_A' END,
       CASE WHEN program_order%4=0 THEN '신관캠 강의실(가상)' ELSE '천안캠 강의실(가상)' END,
       'PBL3_SERIES_'||lpad(program_order::TEXT,2,'0'),
       CASE WHEN (program_order+session_no)%9=0 THEN 'ONLINE' ELSE 'OFFLINE' END
FROM seq
ON CONFLICT(program_id,session_no) DO NOTHING;

-- 신청과 출석 생성: 수업 충돌·시험기간·회차·학생별 편차를 함께 반영한다.
-- 독립적인 실제 관측자료가 아니라 분석 시연용으로 설계된 규칙 기반 가상 데이터이다.
-- 기존 완료 설문이나 승인 마일리지가 있으면 해당 프로그램 본행사 출석으로 연결한다.
WITH candidates AS (
    SELECT ps.session_id, ps.program_id, ps.session_no, ps.session_date,
           ps.start_time,ps.end_time,s.student_no,s.dept_code,s.grade,
           EXISTS(
                SELECT 1 FROM pbl3.course_timetable ct
                WHERE ct.dept_code=s.dept_code AND ct.grade=s.grade
                  AND ct.weekday_iso=EXTRACT(ISODOW FROM ps.session_date)::INT
                  AND ps.session_date BETWEEN ct.term_start AND ct.term_end
                  AND ps.start_time<ct.end_time AND ps.end_time>ct.start_time
           ) AS class_conflict,
           EXISTS(
                SELECT 1 FROM pbl3.academic_event ae
                WHERE ps.session_date BETWEEN ae.start_date-3 AND ae.end_date+3
                  AND ae.event_type IN ('MIDTERM','FINAL')
           ) AS near_exam,
           (ps.session_no=5 AND (
                EXISTS(SELECT 1 FROM analytics.v_survey_response_final f
                       WHERE f.program_id=ps.program_id AND f.student_no=s.student_no)
                OR EXISTS(SELECT 1 FROM public.mileage_application ma
                          WHERE ma.program_id=ps.program_id AND ma.student_no=s.student_no
                            AND ma.source_type='PROGRAM' AND ma.status='APPROVED')
           )) AS has_seed_evidence,
           (get_byte(decode(md5(s.student_no||':R:'||ps.program_id||':'||ps.session_no),'hex'),0)
               *100/256) AS registration_draw,
           (get_byte(decode(md5(s.student_no||':A:'||ps.program_id||':'||ps.session_no),'hex'),0)
               *100/256) AS attendance_draw
    FROM pbl3.program_session ps CROSS JOIN public.student s
    WHERE ps.data_source='PBL3_SYNTHETIC'
), scored AS (
    SELECT c.*,
           (72 - CASE WHEN class_conflict THEN 22 ELSE 0 END
               - CASE WHEN near_exam THEN 15 ELSE 0 END
               - (session_no-1)*4) AS registration_threshold,
           (86 - CASE WHEN class_conflict THEN 23 ELSE 0 END
               - CASE WHEN near_exam THEN 18 ELSE 0 END
               - (session_no-1)*3) AS attendance_threshold
    FROM candidates c
), registered AS (
    SELECT *,CASE
         WHEN has_seed_evidence THEN 'ATTENDED'
         WHEN attendance_draw < 5 THEN 'CANCELLED'
         WHEN attendance_draw < attendance_threshold THEN 'ATTENDED'
         ELSE 'NO_SHOW' END AS attendance_status
    FROM scored
    WHERE has_seed_evidence OR registration_draw < registration_threshold
)
INSERT INTO pbl3.program_participant
(session_id,student_no,attendance_status,registered_at,attended_at)
SELECT r.session_id,r.student_no,r.attendance_status,
       ((r.session_date-8)+TIME '09:00') AT TIME ZONE 'Asia/Seoul'
           + (r.registration_draw*INTERVAL '3 minutes'),
       CASE WHEN r.attendance_status='ATTENDED' THEN
            (r.session_date+r.start_time) AT TIME ZONE 'Asia/Seoul'
               + (r.attendance_draw%12)*INTERVAL '1 minute'
       ELSE NULL END
FROM registered r
ON CONFLICT(session_id,student_no) DO NOTHING;

-- 시연용 기본 데이터 수와 설문·출석 연결상태 확인
DO $$ BEGIN
    IF (SELECT count(*) FROM pbl3.program_session WHERE data_source='PBL3_SYNTHETIC') < 50 THEN
        RAISE EXCEPTION 'PBL3 program_session 시드가 부족합니다.';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM analytics.v_survey_response_final f
        JOIN pbl3.program_session ps ON ps.program_id=f.program_id AND ps.session_no=5
        LEFT JOIN pbl3.program_participant pp
          ON pp.session_id=ps.session_id AND pp.student_no=f.student_no
        WHERE pp.attendance_status IS DISTINCT FROM 'ATTENDED'
    ) THEN
        RAISE EXCEPTION '기존 완료 설문과 본행사 출석 시드가 연결되지 않았습니다.';
    END IF;
END $$;
COMMIT;
