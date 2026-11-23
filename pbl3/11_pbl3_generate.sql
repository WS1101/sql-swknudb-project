\encoding UTF8
\set ON_ERROR_STOP on
-- 11_pbl3_generate.sql : PBL3 가상 데이터 생성기
-- 담당: 서우진
--
-- 생성 방식
--   - 학생마다 보이지 않는 "적극성"(표준정규 분포)을 두고, 신청·출석·응답·만족도가 이 값과
--     회차 조건(수업 충돌, 시험기간, 캠퍼스, 시간대…)에서 확률적으로 나오게 한다.
--   - 효과 크기는 pbl3_truth.coef 한 곳에만 적고, 생성기는 그 값을 읽어서 쓴다.
--     → 모델이 추정한 효과를 이 표와 비교하면 "정답을 얼마나 복원했는가"를 채점할 수 있다.
--   - 난수는 md5 해시 기반이라 몇 번을 실행해도 같은 데이터가 나온다.
--   - 회차는 날짜 순서대로 생성한다. 직전 회차의 만족도가 다음 회차 신청에 영향을 주기 때문.
-- 기준일: 2026-11-23. 이후 회차는 SCHEDULED로 남겨 예측·추천 시연에 쓴다.

BEGIN;
SET LOCAL search_path = pbl3, public;

INSERT INTO pbl3.generation_meta (as_of_date, generator_ver) VALUES (DATE '2026-11-23', 'v2');

-- =====================================================================
-- 0. 정답 계수
-- =====================================================================
INSERT INTO pbl3_truth.coef VALUES (
    -3.55,  -- reg_intercept
     0.90,  -- reg_engagement
    -1.40,  -- reg_class_conflict
    -0.90,  -- reg_near_exam
    -0.40,  -- reg_vacation
    -0.12,  -- reg_session_fatigue
     0.80,  -- reg_prev_content
     2.40,  -- reg_returning
     0.90,  -- ret_content
     0.35,  -- ret_instructor
     0.00,  -- ret_operation
    -1.00,  -- reg_cross_campus
     0.30,  -- reg_online
    -0.35,  -- reg_friday
    -0.70,  -- reg_saturday
    -0.25,  -- reg_evening
     0.015, -- reg_mileage_per_pt
     0.50,  -- reg_program_appeal
     1.70,  -- att_intercept
     0.50,  -- att_engagement
    -1.00,  -- att_class_conflict
    -0.70,  -- att_near_exam
    -0.60,  -- att_online
    -0.40,  -- att_cross_campus
    -0.20,  -- att_evening
     0.06,  -- cancel_rate
     3.60,  -- sat_mean_content
     3.90,  -- sat_mean_instructor
     3.00,  -- sat_mean_operation
     3.60,  -- sat_mean_facility
     3.70,  -- sat_mean_schedule
     0.55,  -- sat_quality_content
     0.35,  -- sat_quality_instr
     0.10,  -- sat_quality_oper
     0.20,  -- sat_engagement
    -0.90,  -- sat_conflict_sched
     0.75,  -- sat_noise_sd
     0.05,  -- straightline_base
     0.12,  -- straightline_low_eng
    -0.90,  -- eng_transfer_dai
     1.60,  -- eng_fading_drop
     0.10   -- fading_ratio
);

INSERT INTO pbl3_truth.type_grade_affinity VALUES
    ('LECTURE',   1,  0.20), ('LECTURE',   2,  0.20), ('LECTURE',   3,  0.00), ('LECTURE',   4, -0.20),
    ('STUDY',     1,  0.20), ('STUDY',     2,  0.30), ('STUDY',     3,  0.00), ('STUDY',     4, -0.40),
    ('CAMP',      1,  0.10), ('CAMP',      2,  0.30), ('CAMP',      3,  0.20), ('CAMP',      4, -0.30),
    ('CONTEST',   1, -0.40), ('CONTEST',   2,  0.20), ('CONTEST',   3,  0.40), ('CONTEST',   4,  0.20),
    ('MENTORING', 1,  0.60), ('MENTORING', 2,  0.00), ('MENTORING', 3, -0.20), ('MENTORING', 4, -0.30),
    ('CAREER',    1, -0.80), ('CAREER',    2, -0.30), ('CAREER',    3,  0.40), ('CAREER',    4,  0.70);

-- =====================================================================
-- 1. 기준정보
-- =====================================================================
INSERT INTO pbl3.campus VALUES
    ('P3_CA', '천안캠퍼스'),
    ('P3_SG', '신관캠퍼스');

INSERT INTO pbl3.department VALUES
    ('P3_CSE', '컴퓨터공학과',     'P3_CA', 'ENG'),
    ('P3_SWE', '소프트웨어학과',   'P3_CA', 'ENG'),
    ('P3_ICE', '정보통신공학과',   'P3_CA', 'ENG'),
    ('P3_EEE', '전자공학과',       'P3_CA', 'ENG'),
    ('P3_IME', '산업경영공학과',   'P3_CA', 'ENG'),
    ('P3_AIE', '인공지능학과',     'P3_SG', 'DAI'),
    ('P3_DSC', '데이터사이언스학과', 'P3_SG', 'DAI'),
    ('P3_CYB', '사이버보안학과',   'P3_SG', 'DAI');

INSERT INTO pbl3.academic_term (term_year, term_code, start_date, end_date) VALUES
    (2025, '1', '2025-03-02', '2025-06-19'), (2025, 'S', '2025-06-20', '2025-08-31'),
    (2025, '2', '2025-09-01', '2025-12-18'), (2025, 'W', '2025-12-19', '2026-03-01'),
    (2026, '1', '2026-03-02', '2026-06-19'), (2026, 'S', '2026-06-20', '2026-08-31'),
    (2026, '2', '2026-09-01', '2026-12-18'), (2026, 'W', '2026-12-19', '2027-02-28');

-- 실제 학사일정이 아닌 가상 시험기간
INSERT INTO pbl3.academic_event (event_name, event_type, start_date, end_date) VALUES
    ('2025-1 중간고사', 'MIDTERM', '2025-04-21', '2025-04-25'),
    ('2025-1 기말고사', 'FINAL',   '2025-06-12', '2025-06-18'),
    ('2025-2 중간고사', 'MIDTERM', '2025-10-20', '2025-10-24'),
    ('2025-2 기말고사', 'FINAL',   '2025-12-11', '2025-12-17'),
    ('2026-1 중간고사', 'MIDTERM', '2026-04-20', '2026-04-24'),
    ('2026-1 기말고사', 'FINAL',   '2026-06-11', '2026-06-17'),
    ('2026-2 중간고사', 'MIDTERM', '2026-10-19', '2026-10-23'),
    ('2026-2 기말고사', 'FINAL',   '2026-12-10', '2026-12-16');

INSERT INTO pbl3.program_type VALUES
    ('LECTURE', '특강'), ('STUDY', '스터디'), ('CAMP', '캠프'),
    ('CONTEST', '경진대회'), ('MENTORING', '멘토링'), ('CAREER', '취업·진로');

INSERT INTO pbl3.survey_question_category VALUES
    ('CONTENT',    '교육 내용', '내용의 유익성·수준'),
    ('INSTRUCTOR', '강사',      '강사 전달력·질의응답'),
    ('OPERATION',  '운영',      '신청·안내·진행 운영'),
    ('FACILITY',   '환경',      '장소·장비·온라인 환경'),
    ('SCHEDULE',   '일정',      '진행 요일·시간의 적절성'),
    ('COMMENT',    '자유의견',  '주관식');

INSERT INTO pbl3.budget_item VALUES
    ('INSTRUCTOR_FEE', '강사료'), ('CATERING', '다과·식비'), ('VENUE', '장소 대관'),
    ('MATERIAL', '재료·교재비'), ('PRIZE', '시상금'), ('PLATFORM', '온라인 플랫폼');

-- =====================================================================
-- 2. 학생 (입학연도 2022~2026, 학과·연도별 인원은 정규분포)
-- =====================================================================
WITH dept AS (
    SELECT dept_code, row_number() OVER (ORDER BY dept_code) AS di, campus_code, track_type
      FROM pbl3.department
), cohort AS (
    SELECT d.*, y, 'NEW' AS admission_type,
           greatest(20, round(38 + 6 * pbl3_truth.fn_n('cohort:' || d.dept_code || ':' || y)))::INT AS n
      FROM dept d CROSS JOIN generate_series(2022, 2026) y
    UNION ALL
    SELECT d.*, y, 'TRANSFER',
           greatest(1, round(4 + 1.5 * pbl3_truth.fn_n('transfer:' || d.dept_code || ':' || y)))::INT
      FROM dept d CROSS JOIN generate_series(2024, 2026) y
)
INSERT INTO pbl3.student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date, sms_opt_in)
SELECT 'P3' || y || lpad(di::TEXT, 2, '0')
            || lpad((CASE WHEN admission_type = 'TRANSFER' THEN 500 ELSE 0 END + seq)::TEXT, 3, '0'),
       dept_code, NULL, 'ENROLLED', admission_type, make_date(y, 3, 2), TRUE
  FROM cohort CROSS JOIN LATERAL generate_series(1, n) seq;

-- 적극성: 표준정규 + 학과 차이(작게) + 신관캠 편입생 불이익(숨은 소외 집단)
INSERT INTO pbl3_truth.student_latent (student_no, engagement, is_fading, fade_start)
SELECT s.student_no,
       round((pbl3_truth.fn_n('eng:' || s.student_no)
             + 0.20 * pbl3_truth.fn_n('dept_eng:' || s.dept_code)
             + CASE WHEN s.admission_type = 'TRANSFER' AND d.track_type = 'DAI' THEN k.eng_transfer_dai ELSE 0 END
             )::NUMERIC, 3),
       f.is_fading,
       CASE WHEN f.is_fading
            THEN DATE '2025-04-01' + floor(pbl3_truth.fn_u('fade_at:' || s.student_no) * 540)::INT END
  FROM pbl3.student s
  JOIN pbl3.department d ON d.dept_code = s.dept_code
  CROSS JOIN pbl3_truth.coef k
  CROSS JOIN LATERAL (SELECT pbl3_truth.fn_u('fade:' || s.student_no) < k.fading_ratio
                             AND s.admission_date < DATE '2026-03-01' AS is_fading) f;

-- 학적: 졸업, 이탈 학생 일부 자퇴, 일부 휴학
UPDATE pbl3.student s
   SET enrollment_status  = x.status,
       status_change_type = x.change_type,
       status_change_date = x.change_date,
       grade              = pbl3.fn_grade_at(s.admission_date, s.admission_type, DATE '2026-11-23')
  FROM (
    SELECT s2.student_no,
           CASE WHEN g.grade_now IS NULL THEN 'GRADUATED'
                WHEN l.is_fading AND u_wd < 0.35 AND l.fade_start + 60 + floor(u_wd * 200)::INT <= DATE '2026-11-23' THEN 'WITHDRAWN'
                WHEN NOT l.is_fading AND u_lv < 0.05 THEN 'ON_LEAVE'
                ELSE 'ENROLLED' END AS status,
           CASE WHEN g.grade_now IS NULL THEN '졸업'
                WHEN l.is_fading AND u_wd < 0.35 AND l.fade_start + 60 + floor(u_wd * 200)::INT <= DATE '2026-11-23' THEN '자퇴'
                WHEN NOT l.is_fading AND u_lv < 0.05 THEN '휴학' END AS change_type,
           CASE WHEN g.grade_now IS NULL THEN make_date(pbl3.fn_academic_year(s2.admission_date)
                                                        + CASE WHEN s2.admission_type = 'TRANSFER' THEN 2 ELSE 4 END, 2, 20)
                WHEN l.is_fading AND u_wd < 0.35 AND l.fade_start + 60 + floor(u_wd * 200)::INT <= DATE '2026-11-23'
                     THEN l.fade_start + 60 + floor(u_wd * 200)::INT
                WHEN NOT l.is_fading AND u_lv < 0.05
                     THEN DATE '2025-09-01' + floor(pbl3_truth.fn_u('leave_at:' || s2.student_no) * 365)::INT END AS change_date
      FROM pbl3.student s2
      JOIN pbl3_truth.student_latent l ON l.student_no = s2.student_no
      CROSS JOIN LATERAL (SELECT pbl3.fn_grade_at(s2.admission_date, s2.admission_type, DATE '2026-11-23') AS grade_now,
                                 pbl3_truth.fn_u('withdraw:' || s2.student_no) AS u_wd,
                                 pbl3_truth.fn_u('leave:' || s2.student_no) AS u_lv) g
  ) x
 WHERE x.student_no = s.student_no;

-- 휴학 시작일이 입학 전이면 입학 이후로 보정
UPDATE pbl3.student
   SET status_change_date = admission_date + 120
 WHERE enrollment_status = 'ON_LEAVE' AND status_change_date <= admission_date;

-- SMS 수신 거부: 이탈 학생은 이탈 무렵 60% 확률, 그 외 4%
WITH optout AS (
    SELECT s.student_no,
           CASE WHEN l.is_fading
                THEN l.fade_start + round(12 * pbl3_truth.fn_n('sms_at:' || s.student_no))::INT
                ELSE DATE '2025-03-15' + floor(pbl3_truth.fn_u('sms_at:' || s.student_no) * 600)::INT END AS opt_date,
           CASE WHEN l.is_fading THEN pbl3_truth.fn_u('sms:' || s.student_no) < 0.60
                ELSE pbl3_truth.fn_u('sms:' || s.student_no) < 0.04 END AS opts_out
      FROM pbl3.student s
      JOIN pbl3_truth.student_latent l ON l.student_no = s.student_no
)
INSERT INTO pbl3.student_info_change_request
    (student_no, field_name, old_value, new_value, requested_at, status, processed_at)
SELECT o.student_no, 'sms_opt_in', 'true', 'false',
       (o.opt_date + TIME '10:00') AT TIME ZONE 'Asia/Seoul'
           + pbl3_truth.fn_u('sms_time:' || o.student_no) * INTERVAL '10 hours',
       'APPROVED',
       (o.opt_date + 1 + TIME '11:00') AT TIME ZONE 'Asia/Seoul'
  FROM optout o
  JOIN pbl3.student s ON s.student_no = o.student_no
 WHERE o.opts_out
   AND o.opt_date > s.admission_date
   AND o.opt_date < DATE '2026-11-22';

UPDATE pbl3.student s SET sms_opt_in = FALSE
  FROM pbl3.student_info_change_request r
 WHERE r.student_no = s.student_no AND r.field_name = 'sms_opt_in' AND r.new_value = 'false';

-- =====================================================================
-- 3. 전공 수업 시간표 (학과·학년·학기마다 다르게)
--    90분 블록 5개: 09:00 10:30 13:00 14:30 16:00. 저학년일수록 수업이 많다.
-- =====================================================================
INSERT INTO pbl3.course_timetable (dept_code, grade, term_id, weekday_iso, start_time, end_time, course_label)
SELECT d.dept_code, g, t.term_id, wd, b.start_time, b.start_time + INTERVAL '90 minutes',
       d.dept_name || ' ' || g || '학년 전공'
  FROM pbl3.department d
 CROSS JOIN generate_series(1, 4) g
 CROSS JOIN pbl3.academic_term t
 CROSS JOIN generate_series(1, 5) wd
 CROSS JOIN (VALUES (TIME '09:00'), (TIME '10:30'), (TIME '13:00'), (TIME '14:30'), (TIME '16:00')) b(start_time)
 WHERE t.term_code IN ('1', '2')
   AND pbl3_truth.fn_u('tt:' || d.dept_code || ':' || g || ':' || t.term_id || ':' || wd || ':' || b.start_time)
       < (CASE g WHEN 1 THEN 0.50 WHEN 2 THEN 0.55 WHEN 3 THEN 0.45 ELSE 0.30 END)
         + 0.20 * (pbl3_truth.fn_u('tt_dept:' || d.dept_code || ':' || g) - 0.5)
         + CASE WHEN wd = 5 THEN -0.15 ELSE 0 END;

-- =====================================================================
-- 4. 프로그램 카탈로그 (2년치 35개 시리즈)
--    quality / appeal 이 NULL이면 정규분포로 생성, 값이 있으면 시연용으로 의도한 값
-- =====================================================================
CREATE TEMP TABLE catalog (
    ord INT, program_name TEXT, type_code TEXT, series_key TEXT, first_date DATE, n_sessions INT,
    interval_days INT, start_time TIME, duration_min INT, campus_code TEXT, delivery_mode TEXT,
    capacity INT, mileage INT, organizer TEXT, quality NUMERIC, appeal NUMERIC, story TEXT
) ON COMMIT DROP;

INSERT INTO catalog VALUES
 -- 2025-1학기
 ( 1,'파이썬 기초 특강 2025',        'LECTURE',  'PYTHON_BASIC', '2025-03-18', 6, 7, '18:30',120,'P3_CA','OFFLINE', 120,10,'SW중심대학사업단', NULL, NULL, NULL),
 ( 2,'웹 개발 스터디 2025',          'STUDY',    'WEB_STUDY',    '2025-03-20', 8, 7, '16:00',120,'P3_CA','OFFLINE',  60,15,'SW중심대학사업단', NULL, NULL, NULL),
 ( 3,'AI 리터러시 특강 2025',        'LECTURE',  'AI_LITERACY',  '2025-04-02', 5, 7, '13:00',120,'P3_SG','OFFLINE', 120,10,'인공지능학부',     NULL, NULL, NULL),
 ( 4,'1학년 전공 멘토링 2025',       'MENTORING','FRESH_MENTOR', '2025-03-26', 7,14, '14:30',120,'P3_CA','OFFLINE',  60,10,'SW중심대학사업단', NULL, NULL, NULL),
 ( 5,'SW 취업 전략 특강 2025',       'CAREER',   'CAREER_SW',    '2025-05-07', 4, 7, '16:00',120,'P3_CA','OFFLINE',200,10,'취업지원센터',     NULL, NULL, NULL),
 ( 6,'데이터 분석 실습 2025',        'LECTURE',  'DATA_LAB',     '2025-05-13', 5, 7, '10:30',120,'P3_SG','OFFLINE', 120,10,'인공지능학부',     NULL, NULL, NULL),
 -- 2025 여름
 ( 7,'여름 AI 부트캠프 2025',        'CAMP',     'SUMMER_AI',    '2025-07-07', 5, 1, '10:00',360,'P3_SG','OFFLINE',  70,40,'인공지능학부',     NULL, NULL, NULL),
 ( 8,'여름 알고리즘 캠프 2025',      'CAMP',     'SUMMER_ALGO',  '2025-07-21', 5, 1, '10:00',360,'P3_CA','OFFLINE',  70,40,'SW중심대학사업단', NULL, NULL, NULL),
 ( 9,'SW 해커톤 2025',               'CONTEST',  'HACKATHON',    '2025-08-11', 2,11, '18:30', 60, NULL ,'ONLINE', 150,30,'SW중심대학사업단', NULL, NULL, NULL),
 -- 2025-2학기
 (10,'클라우드 입문 특강 2025',      'LECTURE',  'CLOUD_INTRO',  '2025-09-16', 6, 7, '18:30',120,'P3_CA','OFFLINE', 120,10,'SW중심대학사업단', NULL, NULL, NULL),
 (11,'코딩테스트 온라인 스터디 2025','STUDY',    'CT_STUDY',     '2025-09-17', 8, 7, '19:00',120, NULL ,'ONLINE',   60,15,'SW중심대학사업단', NULL, NULL, NULL),
 (12,'산업체 현장 멘토링 2025',      'MENTORING','INDUSTRY_MENTOR','2025-09-24',6,14,'16:00',120,'P3_CA','OFFLINE',  60,15,'산학협력단',       NULL, NULL, NULL),
 (13,'생성형 AI 활용 특강 2025',     'LECTURE',  'GENAI',        '2025-10-01', 5, 7, '14:30',120,'P3_SG','OFFLINE',120,10,'외부 교육업체',
      -1.30, 1.20, '주제 매력이 높아 신청은 많지만 내용 품질이 낮다. 강사료가 비싸 만족 1명당 비용이 크다'),
 (14,'SW 취업 박람회 연계 특강 2025','CAREER',   'CAREER_FAIR',  '2025-10-28', 3, 7, '13:00',150,'P3_CA','OFFLINE',200,10,'취업지원센터',     NULL, NULL, NULL),
 (15,'캡스톤 아이디어 경진대회 2025','CONTEST',  'CAPSTONE_IDEA','2025-11-05', 2,16, '18:30', 60, NULL ,'ONLINE', 150,30,'SW중심대학사업단', NULL, NULL, NULL),
 -- 2025 겨울
 (16,'겨울 데이터 캠프 2026',        'CAMP',     'WINTER_DATA',  '2026-01-12', 5, 1, '10:00',360,'P3_SG','OFFLINE',  70,40,'인공지능학부',     NULL, NULL, NULL),
 (17,'겨울 웹 풀스택 캠프 2026',     'CAMP',     'WINTER_WEB',   '2026-01-19', 5, 1, '10:00',360,'P3_CA','OFFLINE',  70,40,'SW중심대학사업단', NULL, NULL, NULL),
 -- 2026-1학기
 (18,'파이썬 기초 특강 2026',        'LECTURE',  'PYTHON_BASIC', '2026-03-17', 6, 7, '18:30',120,'P3_CA','OFFLINE', 120,10,'SW중심대학사업단', NULL, NULL, NULL),
 (19,'웹 개발 스터디 2026',          'STUDY',    'WEB_STUDY',    '2026-03-19', 8, 7, '16:00',120,'P3_CA','OFFLINE',  60,15,'SW중심대학사업단', NULL, NULL, NULL),
 (20,'AI 리터러시 특강 2026',        'LECTURE',  'AI_LITERACY',  '2026-04-01', 5, 7, '13:00',120,'P3_SG','OFFLINE', 120,10,'인공지능학부',     NULL, NULL, NULL),
 (21,'1학년 전공 멘토링 2026',       'MENTORING','FRESH_MENTOR', '2026-03-25', 7,14, '14:30',120,'P3_CA','OFFLINE',  60,10,'SW중심대학사업단', NULL, NULL, NULL),
 (22,'SW 취업 전략 특강 2026',       'CAREER',   'CAREER_SW',    '2026-05-06', 4, 7, '16:00',120,'P3_CA','OFFLINE',200,10,'취업지원센터',     NULL, NULL, NULL),
 (23,'정보보안 기초 특강 2026',      'LECTURE',  'SECURITY_BASIC','2026-04-07',5, 7, '10:30',120,'P3_SG','OFFLINE', 120,10,'인공지능학부',     NULL, NULL, NULL),
 -- 2026 여름
 (24,'여름 AI 부트캠프 2026',        'CAMP',     'SUMMER_AI',    '2026-07-06', 5, 1, '10:00',360,'P3_SG','OFFLINE',  70,40,'인공지능학부',     NULL, NULL, NULL),
 (25,'여름 알고리즘 캠프 2026',      'CAMP',     'SUMMER_ALGO',  '2026-07-20', 5, 1, '10:00',360,'P3_CA','OFFLINE',  70,40,'SW중심대학사업단', NULL, NULL, NULL),
 (26,'SW 해커톤 2026',               'CONTEST',  'HACKATHON',    '2026-08-10', 2,11, '18:30', 60, NULL ,'ONLINE', 150,30,'SW중심대학사업단', NULL, NULL, NULL),
 -- 2026-2학기
 (27,'코딩테스트 대비 알고리즘 특강 2026','LECTURE','ALGO_CT',   '2026-09-10', 8, 7, '18:30',120,'P3_CA','OFFLINE', 120,10,'SW중심대학사업단',
       1.00, 0.30, '내용 품질이 높지만 4회차부터 수요일 13:00로 옮겨 2~3학년 수업과 겹치며 참여가 급감. 시간만 문제'),
 (28,'클라우드 입문 특강 2026',      'LECTURE',  'CLOUD_INTRO',  '2026-09-15', 6, 7, '18:30',120,'P3_CA','OFFLINE', 120,10,'SW중심대학사업단', NULL, NULL, NULL),
 (29,'산업체 현장 멘토링 2026',      'MENTORING','INDUSTRY_MENTOR','2026-09-23',6,14,'16:00',120,'P3_CA','OFFLINE',  60,15,'산학협력단',       NULL, NULL, NULL),
 (30,'생성형 AI 활용 특강 2026',     'LECTURE',  'GENAI',        '2026-10-07', 8, 7, '14:30',120,'P3_SG','OFFLINE',120,10,'외부 교육업체',
      -0.80, 1.00, '2025년 저품질 강의를 같은 업체로 반복. 회차가 갈수록 입소문으로 신청 감소'),
 (31,'SW 취업 박람회 연계 특강 2026','CAREER',   'CAREER_FAIR',  '2026-10-27', 3, 7, '13:00',150,'P3_CA','OFFLINE',200,10,'취업지원센터',     NULL, NULL, NULL),
 (32,'캡스톤 아이디어 경진대회 2026','CONTEST',  'CAPSTONE_IDEA','2026-11-04', 2,16, '18:30', 60, NULL ,'ONLINE', 150,30,'SW중심대학사업단', NULL, NULL, NULL),
 (33,'MLOps 실무 특강 2026',         'LECTURE',  'MLOPS',        '2026-11-17', 4, 7, '13:00',120,'P3_CA','OFFLINE', 120,10,'SW중심대학사업단',
       0.50, 0.40, '1회차만 진행. 남은 회차(12/8은 기말 직전)는 예정 상태로 두어 예측·시간대 추천 시연에 사용'),
 (34,'오픈소스 기여 스터디 2026',    'STUDY',    'OSS_STUDY',    '2026-09-16', 8, 7, '16:00',120,'P3_SG','OFFLINE',  60,15,'인공지능학부',     NULL, NULL, NULL),
 (35,'데이터 분석 실습 2026',        'LECTURE',  'DATA_LAB',     '2026-09-22', 5, 7, '10:30',120,'P3_SG','OFFLINE', 120,10,'인공지능학부',     NULL, NULL, NULL);

INSERT INTO pbl3.program (program_type_code, program_name, program_date, organizer, capacity, series_key)
SELECT type_code, program_name, first_date, organizer, capacity, series_key FROM catalog ORDER BY ord;

INSERT INTO pbl3.mileage_criteria (program_id, participation_mileage, award_mileage)
SELECT p.program_id, c.mileage, CASE WHEN c.type_code = 'CONTEST' THEN c.mileage * 3 END
  FROM catalog c JOIN pbl3.program p ON p.program_name = c.program_name;

-- 같은 시리즈(해마다 반복)는 품질이 비슷하도록 시리즈 공통값 + 회차 고유값
INSERT INTO pbl3_truth.program_latent (program_id, quality, appeal, story)
SELECT p.program_id,
       COALESCE(c.quality, round((0.7 * pbl3_truth.fn_n('q_series:' || c.series_key)
                                + 0.5 * pbl3_truth.fn_n('q:' || c.program_name))::NUMERIC, 3)),
       COALESCE(c.appeal,  round((0.8 * pbl3_truth.fn_n('a:' || c.program_name))::NUMERIC, 3)),
       c.story
  FROM catalog c JOIN pbl3.program p ON p.program_name = c.program_name;

-- 회차: 기본 일정 + 약 20% 회차는 다른 시간으로 변경(실제 일정 변경처럼)
--   같은 프로그램 안에서도 시간이 달라지므로, 프로그램 자체 효과와 시간 효과를 분리해 볼 수 있다
WITH base AS (
    SELECT c.*, p.program_id, sn,
           c.first_date + (sn - 1) * c.interval_days AS d0,
           pbl3_truth.fn_u('move:' || c.program_name || ':' || sn) AS u_move,
           (ARRAY[TIME '10:30', TIME '13:00', TIME '14:30', TIME '16:00', TIME '18:30'])
               [1 + floor(pbl3_truth.fn_u('slot:' || c.program_name || ':' || sn) * 5)::INT] AS alt_time
      FROM catalog c
      JOIN pbl3.program p ON p.program_name = c.program_name
     CROSS JOIN LATERAL generate_series(1, c.n_sessions) sn
), timed AS (
    SELECT b.*,
           CASE
             WHEN b.series_key = 'ALGO_CT' AND b.sn >= 4 THEN b.d0 - 1                     -- 목 → 수
             ELSE b.d0 END AS session_date,
           CASE
             WHEN b.series_key = 'ALGO_CT' AND b.sn >= 4 THEN TIME '13:00'
             WHEN b.type_code = 'CONTEST' AND b.sn = 2   THEN TIME '10:00'                  -- 본선
             WHEN b.type_code IN ('CAMP', 'CONTEST')     THEN b.start_time
             WHEN b.series_key IN ('MLOPS', 'ALGO_CT')   THEN b.start_time
             WHEN b.u_move < 0.20                        THEN b.alt_time
             ELSE b.start_time END AS st,
           CASE WHEN b.type_code = 'CONTEST' AND b.sn = 2 THEN 480 ELSE b.duration_min END AS dur,
           CASE WHEN b.type_code = 'CONTEST' AND b.sn = 2 THEN 'P3_CA' ELSE b.campus_code END AS campus,
           CASE WHEN b.type_code = 'CONTEST' AND b.sn = 2 THEN 'OFFLINE' ELSE b.delivery_mode END AS mode
      FROM base b
)
INSERT INTO pbl3.program_session
    (program_id, session_no, session_date, start_time, end_time, campus_code, location_name, delivery_mode, session_status)
SELECT program_id, sn, session_date, st, (st + dur * INTERVAL '1 minute')::TIME,
       campus,
       CASE campus WHEN 'P3_CA' THEN '천안캠 공학관 ' || (300 + sn)
                   WHEN 'P3_SG' THEN '신관캠 AI관 '   || (200 + sn)
                   ELSE '온라인(Zoom)' END,
       mode,
       CASE WHEN session_date > DATE '2026-11-23' THEN 'SCHEDULED' ELSE 'COMPLETED' END
  FROM timed
 ORDER BY session_date, st, program_id;

-- 완료된 회차마다 만족도 조사와 문항 6개
INSERT INTO pbl3.survey (program_id, session_id, survey_name, start_date, end_date, status)
SELECT s.program_id, s.session_id, p.program_name || ' ' || s.session_no || '회차 만족도',
       s.session_date, s.session_date + 7, 'CLOSED'
  FROM pbl3.program_session s JOIN pbl3.program p ON p.program_id = s.program_id
 WHERE s.session_status = 'COMPLETED';

INSERT INTO pbl3.survey_question (survey_id, category_code, display_order, question_text, question_type, scale_max)
SELECT v.survey_id, q.cat, q.ord, q.txt, q.qtype, CASE WHEN q.qtype = 'SCALE' THEN 5 END
  FROM pbl3.survey v
 CROSS JOIN (VALUES
    (1, 'CONTENT',    '교육 내용이 유익하고 수준이 적절했다', 'SCALE'),
    (2, 'INSTRUCTOR', '강사의 설명과 질의응답이 만족스러웠다', 'SCALE'),
    (3, 'OPERATION',  '신청·안내·진행 등 운영이 원활했다',     'SCALE'),
    (4, 'FACILITY',   '장소·장비·온라인 환경이 적절했다',      'SCALE'),
    (5, 'SCHEDULE',   '진행 요일과 시간이 참여하기에 적절했다', 'SCALE'),
    (6, 'COMMENT',    '개선할 점이나 바라는 점을 적어 주세요', 'TEXT')) q(ord, cat, txt, qtype);

-- =====================================================================
-- 5. 회차별 신청·출석·만족도 (날짜 순서대로)
-- =====================================================================
-- 회차 × 재학생 후보 특성을 한 번에 계산 (루프 안에서 회차마다 다시 계산하지 않도록)
CREATE TEMP TABLE cand ON COMMIT DROP AS
SELECT s.session_id, st.student_no, g.grade_at,
       l.engagement - CASE WHEN l.is_fading AND s.session_date >= l.fade_start
                           THEN k.eng_fading_drop ELSE 0 END AS eng,
       EXISTS (SELECT 1 FROM pbl3.course_timetable ct
                WHERE ct.dept_code = st.dept_code AND ct.grade = g.grade_at
                  AND ct.term_id = tm.term_id
                  AND ct.weekday_iso = EXTRACT(ISODOW FROM s.session_date)
                  AND s.start_time < ct.end_time AND s.end_time > ct.start_time) AS conflict,
       (s.delivery_mode = 'OFFLINE' AND d.campus_code <> s.campus_code) AS cross_campus
  FROM pbl3.program_session s
  JOIN pbl3.academic_term tm ON s.session_date BETWEEN tm.start_date AND tm.end_date
 CROSS JOIN pbl3.student st
  JOIN pbl3.department d ON d.dept_code = st.dept_code
  JOIN pbl3_truth.student_latent l ON l.student_no = st.student_no
 CROSS JOIN pbl3_truth.coef k
 CROSS JOIN LATERAL (SELECT pbl3.fn_grade_at(st.admission_date, st.admission_type, s.session_date) AS grade_at) g
 WHERE s.session_status = 'COMPLETED'
   AND g.grade_at IS NOT NULL
   AND NOT (st.enrollment_status IN ('WITHDRAWN', 'ON_LEAVE') AND st.status_change_date <= s.session_date);
CREATE INDEX ON cand (session_id, student_no);
ANALYZE cand;

CREATE PROCEDURE pbl3_truth.sp_generate_participation()
LANGUAGE plpgsql AS $$
DECLARE
    r            RECORD;
    v_prev_id    INT;
    v_prev_score NUMERIC;
    v_exam       BOOLEAN;
    v_vacation   BOOLEAN;
BEGIN
    FOR r IN
        SELECT s.*, p.program_type_code, p.program_name, p.capacity, pl.appeal, pl.quality,
               COALESCE(mc.participation_mileage, 0) AS mileage,
               EXTRACT(ISODOW FROM s.session_date)::INT AS dow
          FROM pbl3.program_session s
          JOIN pbl3.program p ON p.program_id = s.program_id
          JOIN pbl3_truth.program_latent pl ON pl.program_id = s.program_id
          LEFT JOIN pbl3.mileage_criteria mc ON mc.program_id = s.program_id
         WHERE s.session_status = 'COMPLETED'
         ORDER BY s.session_date, s.start_time, s.session_id
    LOOP
        v_exam     := pbl3.fn_near_exam(r.session_date);
        v_vacation := NOT pbl3.fn_in_semester(r.session_date);

        SELECT ps.session_id INTO v_prev_id
          FROM pbl3.program_session ps
         WHERE ps.program_id = r.program_id AND ps.session_no = r.session_no - 1;

        -- 직전 회차의 응답 평균 내용 만족도 (입소문). 없으면 효과 0
        SELECT avg(d.score) INTO v_prev_score
          FROM pbl3.survey sv
          JOIN pbl3.survey_response rs ON rs.survey_id = sv.survey_id AND rs.is_completed
          JOIN pbl3.survey_response_detail d ON d.response_id = rs.response_id
          JOIN pbl3.survey_question q ON q.question_id = d.question_id AND q.category_code = 'CONTENT'
         WHERE sv.session_id = v_prev_id;

        -- 신청·출석 (후보 특성은 cand에 미리 계산되어 있다)
        --   정원이 차면 먼저 신청한 순서대로 마감 (선착순)
        INSERT INTO pbl3.program_participant (session_id, student_no, attendance_status, registered_at, attended_at)
        SELECT r.session_id, f.student_no, f.status, f.registered_at, f.attended_at
          FROM (
        SELECT c.student_no, c.status,
               ((r.session_date - 1 - floor(pbl3_truth.fn_u('regday:' || c.key) * 13)::INT) + TIME '09:00')
                   AT TIME ZONE 'Asia/Seoul' + pbl3_truth.fn_u('regtime:' || c.key) * INTERVAL '13 hours' AS registered_at,
               CASE WHEN c.status = 'ATTENDED'
                    THEN (r.session_date + r.start_time) AT TIME ZONE 'Asia/Seoul'
                         + (floor(pbl3_truth.fn_u('arrive:' || c.key) * 25) - 10) * INTERVAL '1 minute' END AS attended_at
          FROM (
            SELECT x.*,
                   CASE WHEN pbl3_truth.fn_u('cancel:' || x.key) < k.cancel_rate THEN 'CANCELLED'
                        WHEN pbl3_truth.fn_u('att:' || x.key) < pbl3_truth.fn_sigmoid(
                                 k.att_intercept + k.att_engagement * x.eng
                               + k.att_class_conflict * x.conflict::INT
                               + k.att_near_exam * v_exam::INT
                               + k.att_online * (r.delivery_mode = 'ONLINE')::INT
                               + k.att_cross_campus * x.cross_campus::INT
                               + k.att_evening * (r.start_time >= TIME '18:00')::INT)
                        THEN 'ATTENDED' ELSE 'NO_SHOW' END AS status
              FROM (
                SELECT cd.student_no, cd.grade_at, cd.eng, cd.conflict, cd.cross_campus,
                       cd.student_no || ':' || r.session_id AS key,
                       ps.true_content AS prev_content, ps.true_instructor AS prev_instructor,
                       ps.true_operation AS prev_operation
                  FROM cand cd
                  LEFT JOIN pbl3_truth.attendee_satisfaction ps
                         ON ps.session_id = v_prev_id AND ps.student_no = cd.student_no
                 WHERE cd.session_id = r.session_id
              ) x
             CROSS JOIN pbl3_truth.coef k
              LEFT JOIN pbl3_truth.type_grade_affinity a
                     ON a.program_type_code = r.program_type_code AND a.grade = x.grade_at
             WHERE pbl3_truth.fn_u('reg:' || x.key) < pbl3_truth.fn_sigmoid(
                         k.reg_intercept + k.reg_engagement * x.eng
                       + COALESCE(a.value, 0)
                       + k.reg_program_appeal * r.appeal
                       + k.reg_class_conflict * x.conflict::INT
                       + k.reg_near_exam * v_exam::INT
                       + k.reg_vacation * v_vacation::INT
                       + k.reg_session_fatigue * (r.session_no - 1)
                       + k.reg_prev_content * COALESCE(v_prev_score - 3.5, 0)
                       + CASE WHEN x.prev_content IS NOT NULL
                              THEN k.reg_returning
                                 + k.ret_content    * (x.prev_content - 3)
                                 + k.ret_instructor * (x.prev_instructor - 3)
                                 + k.ret_operation  * (x.prev_operation - 3)
                              ELSE 0 END
                       + k.reg_cross_campus * x.cross_campus::INT
                       + k.reg_online * (r.delivery_mode = 'ONLINE')::INT
                       + k.reg_friday * (r.dow = 5)::INT
                       + k.reg_saturday * (r.dow >= 6)::INT
                       + k.reg_evening * (r.start_time >= TIME '18:00')::INT
                       + k.reg_mileage_per_pt * r.mileage)
          ) c
          ) f
         ORDER BY f.registered_at, f.student_no
         LIMIT r.capacity;

        -- 출석자의 실제 만족도
        INSERT INTO pbl3_truth.attendee_satisfaction
        SELECT r.session_id, z.student_no,
               round((k.sat_mean_content    + k.sat_quality_content * r.quality + k.sat_engagement * z.eng
                      + k.sat_noise_sd * pbl3_truth.fn_n('s_ct:' || z.key))::NUMERIC, 3),
               round((k.sat_mean_instructor + k.sat_quality_instr * r.quality + k.sat_engagement * z.eng
                      + k.sat_noise_sd * pbl3_truth.fn_n('s_in:' || z.key))::NUMERIC, 3),
               round((k.sat_mean_operation  + k.sat_quality_oper * r.quality + k.sat_engagement * z.eng
                      + k.sat_noise_sd * pbl3_truth.fn_n('s_op:' || z.key))::NUMERIC, 3),
               round((k.sat_mean_facility   + k.sat_engagement * z.eng
                      + CASE WHEN r.delivery_mode = 'ONLINE' THEN -0.3 ELSE 0 END
                      + k.sat_noise_sd * pbl3_truth.fn_n('s_fa:' || z.key))::NUMERIC, 3),
               round((k.sat_mean_schedule   + k.sat_conflict_sched * z.conflict::INT + k.sat_engagement * z.eng
                      + k.sat_noise_sd * pbl3_truth.fn_n('s_sc:' || z.key))::NUMERIC, 3),
               pbl3_truth.fn_u('straight:' || z.key) < k.straightline_base
                   + CASE WHEN z.eng < -0.5 THEN k.straightline_low_eng ELSE 0 END
          FROM (
            SELECT pp.student_no, pp.student_no || ':' || r.session_id AS key, cd.eng, cd.conflict
              FROM pbl3.program_participant pp
              JOIN cand cd ON cd.session_id = r.session_id AND cd.student_no = pp.student_no
             WHERE pp.session_id = r.session_id AND pp.attendance_status = 'ATTENDED'
          ) z
         CROSS JOIN pbl3_truth.coef k;

        -- 만족도 응답: 적극적인 학생일수록 응답. 6%는 중도 포기
        INSERT INTO pbl3.survey_response
            (survey_id, student_no, grade_at_response, dept_code_at_response, responded_at, is_completed)
        SELECT sv.survey_id, t.student_no,
               pbl3.fn_grade_at(st.admission_date, st.admission_type, r.session_date), st.dept_code,
               (r.session_date + r.end_time) AT TIME ZONE 'Asia/Seoul'
                   + (0.3 + 96 * pbl3_truth.fn_u('resp_at:' || t.student_no || ':' || r.session_id) ^ 3) * INTERVAL '1 hour',
               pbl3_truth.fn_u('complete:' || t.student_no || ':' || r.session_id) >= 0.06
          FROM pbl3_truth.attendee_satisfaction t
          JOIN pbl3.student st ON st.student_no = t.student_no
          JOIN pbl3_truth.student_latent l ON l.student_no = t.student_no
          JOIN pbl3.survey sv ON sv.session_id = r.session_id
         WHERE t.session_id = r.session_id
           AND pbl3_truth.fn_u('respond:' || t.student_no || ':' || r.session_id)
               < pbl3_truth.fn_sigmoid(0.3 + 0.8 * l.engagement);

        -- 척도 문항: 성실 응답은 실제 만족도를 반올림, 일괄 응답자는 모든 문항 같은 점수
        --   중도 포기 응답은 앞쪽 1~4문항만
        INSERT INTO pbl3.survey_response_detail (response_id, question_id, score)
        SELECT rs.response_id, q.question_id,
               CASE WHEN t.is_straightliner
                    THEN CASE WHEN pbl3_truth.fn_u('sl_val:' || rs.response_id) < 0.6 THEN 5
                              WHEN pbl3_truth.fn_u('sl_val:' || rs.response_id) < 0.9 THEN 4 ELSE 3 END
                    ELSE least(5, greatest(1, round(CASE q.category_code
                              WHEN 'CONTENT'    THEN t.true_content
                              WHEN 'INSTRUCTOR' THEN t.true_instructor
                              WHEN 'OPERATION'  THEN t.true_operation
                              WHEN 'FACILITY'   THEN t.true_facility
                              ELSE t.true_schedule END))) END
          FROM pbl3.survey sv
          JOIN pbl3.survey_response rs ON rs.survey_id = sv.survey_id
          JOIN pbl3_truth.attendee_satisfaction t ON t.session_id = r.session_id AND t.student_no = rs.student_no
          JOIN pbl3.survey_question q ON q.survey_id = sv.survey_id AND q.question_type = 'SCALE'
         WHERE sv.session_id = r.session_id
           AND (rs.is_completed
                OR q.display_order <= 1 + floor(pbl3_truth.fn_u('partial:' || rs.response_id) * 4));

        -- 자유의견: 완료 응답의 30%. 실제 만족도가 가장 낮은 영역에 대한 의견
        INSERT INTO pbl3.survey_response_detail (response_id, question_id, text_answer)
        SELECT rs.response_id, q.question_id,
               (CASE w.worst
                  WHEN 'CONTENT'    THEN ARRAY['내용이 기대보다 기초적이었어요', '실습 비중이 더 높았으면 좋겠습니다', '주제는 좋은데 깊이가 부족했어요']
                  WHEN 'INSTRUCTOR' THEN ARRAY['설명 속도가 너무 빨랐어요', '질문할 시간이 부족했습니다', '강사님 목소리가 잘 안 들렸어요']
                  WHEN 'OPERATION'  THEN ARRAY['신청 안내 문자가 늦게 왔어요', '시작 시간이 지연됐습니다', '자료 공유가 늦었어요']
                  WHEN 'FACILITY'   THEN ARRAY['강의실이 좁았어요', '와이파이가 자주 끊겼습니다', '줌 화면 공유가 잘 안 보였어요']
                  ELSE                   ARRAY['수업 시간과 겹쳐서 중간에 나가야 했어요', '시간대를 저녁으로 옮겨주세요', '시험 기간이라 참여가 힘들었어요']
                END)[1 + floor(pbl3_truth.fn_u('txt:' || rs.response_id) * 3)::INT]
          FROM pbl3.survey sv
          JOIN pbl3.survey_response rs ON rs.survey_id = sv.survey_id AND rs.is_completed
          JOIN pbl3_truth.attendee_satisfaction t ON t.session_id = r.session_id AND t.student_no = rs.student_no
          JOIN pbl3.survey_question q ON q.survey_id = sv.survey_id AND q.question_type = 'TEXT'
         CROSS JOIN LATERAL (
            SELECT cat AS worst FROM (VALUES ('CONTENT', t.true_content), ('INSTRUCTOR', t.true_instructor),
                                             ('OPERATION', t.true_operation), ('FACILITY', t.true_facility),
                                             ('SCHEDULE', t.true_schedule)) v(cat, val)
             ORDER BY val LIMIT 1) w
         WHERE sv.session_id = r.session_id
           AND pbl3_truth.fn_u('has_txt:' || rs.response_id) < 0.30;
    END LOOP;
END;
$$;

CALL pbl3_truth.sp_generate_participation();

-- =====================================================================
-- 6. 프로그램 지출 (회차 단위, 금액은 로그정규 분포)
-- =====================================================================
WITH att AS (
    SELECT s.session_id, s.program_id, s.session_no, s.session_date, s.delivery_mode,
           p.program_type_code, p.program_name, p.organizer,
           count(*) FILTER (WHERE pp.attendance_status = 'ATTENDED') AS attended
      FROM pbl3.program_session s
      JOIN pbl3.program p ON p.program_id = s.program_id
      LEFT JOIN pbl3.program_participant pp ON pp.session_id = s.session_id
     WHERE s.session_status = 'COMPLETED'
     GROUP BY s.session_id, p.program_id
), lines AS (
    -- 강사료: 외부업체는 비싸다
    SELECT a.*, 'INSTRUCTOR_FEE' AS item, '강사료(' || a.session_no || '회차)' AS descr,
           round((CASE a.program_type_code WHEN 'CAMP' THEN 900000 WHEN 'CAREER' THEN 500000
                                          WHEN 'MENTORING' THEN 300000 WHEN 'STUDY' THEN 150000 ELSE 400000 END
                 * CASE WHEN a.organizer = '외부 교육업체' THEN 2.2 ELSE 1 END
                 * exp(0.20 * pbl3_truth.fn_n('fee:' || a.session_id)))::NUMERIC, -4) AS amount
      FROM att a WHERE a.program_type_code <> 'CONTEST' OR a.session_no = 1
    UNION ALL
    SELECT a.*, 'CATERING', '다과·식비(' || a.session_no || '회차)',
           round((a.attended * CASE WHEN a.program_type_code = 'CAMP' THEN 15000 ELSE 6000 END
                 * exp(0.15 * pbl3_truth.fn_n('cat:' || a.session_id)))::NUMERIC, -2)
      FROM att a WHERE a.delivery_mode = 'OFFLINE' AND a.attended > 0
    UNION ALL
    SELECT a.*, 'VENUE', '장소 대관', round((400000 * exp(0.2 * pbl3_truth.fn_n('venue:' || a.session_id)))::NUMERIC, -4)
      FROM att a WHERE a.program_type_code IN ('CAMP', 'CONTEST') AND a.delivery_mode = 'OFFLINE'
    UNION ALL
    SELECT a.*, 'MATERIAL', '교재·재료비', round((a.attended * 12000 * exp(0.2 * pbl3_truth.fn_n('mat:' || a.session_id)))::NUMERIC, -3)
      FROM att a WHERE a.program_type_code IN ('CAMP', 'STUDY') AND a.session_no = 1 AND a.attended > 0
    UNION ALL
    SELECT a.*, 'PRIZE', '시상금', 3000000::NUMERIC
      FROM att a WHERE a.program_type_code = 'CONTEST' AND a.session_no = 2
    UNION ALL
    SELECT a.*, 'PLATFORM', '온라인 플랫폼 이용료', 120000::NUMERIC
      FROM att a WHERE a.delivery_mode = 'ONLINE'
)
INSERT INTO pbl3.expenditure (program_id, session_id, budget_item_code, expenditure_date, amount, description, status, comment)
SELECT program_id, session_id, item, session_date + floor(pbl3_truth.fn_u('expd:' || session_id || item) * 14)::INT,
       amount::BIGINT, descr,
       CASE WHEN pbl3_truth.fn_u('exprej:' || session_id || item) < 0.04 THEN 'REJECTED' ELSE 'APPROVED' END,
       CASE WHEN pbl3_truth.fn_u('exprej:' || session_id || item) < 0.04 THEN '증빙 누락으로 반려 후 재신청' END
  FROM lines WHERE amount > 0;

-- 반려 건은 같은 금액으로 재신청되어 승인됨
INSERT INTO pbl3.expenditure (program_id, session_id, budget_item_code, expenditure_date, amount, description, status)
SELECT program_id, session_id, budget_item_code, expenditure_date + 5, amount, description || ' (재신청)', 'APPROVED'
  FROM pbl3.expenditure WHERE status = 'REJECTED';

DROP PROCEDURE pbl3_truth.sp_generate_participation();
COMMIT;

ANALYZE;
