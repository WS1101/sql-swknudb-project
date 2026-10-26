-- =====================================================================
-- T04_range_violation.sql : 범위 밖 점수·0 이하 지출금액 거부
-- 담당: 김건희 (TOPCIT·마일리지), 임영효 (지출)
-- 실행: psql -d swknu_db -f tests/T04_range_violation.sql
--
-- 시나리오 (미션 7장)
--   입력        TOPCIT 총점 -1, 1001 / 지출금액 0, 음수 / 그 밖의 범위 밖 값
--   예상 결과   CHECK 위반(23514)으로 거부. 경계값(0, 1000, 1원)은 허용
--   구현 방법   - ck_topcit_score_total_score  CHECK (total_score BETWEEN 0 AND 1000)  (자동 강제)
--                 기준: TOPCIT 총점 1,000점 체계
--               - ck_expenditure_amount        CHECK (amount > 0)                       (자동 강제)
--               - 업무 함수 fn_create_expenditure 도 0 이하 금액을 먼저 거부 (P0001)
--               - 학년 1~4, 마일리지 신청값 > 0, 기준 마일리지 ≥ 0 (CHECK)
--   만족도 1~5점 범위는 T09에서 확인한다.
-- =====================================================================
\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 준비: 학생·관리자(지출 권한)·회차 3개·사업·예산항목·확정 예산·교수·프로그램
INSERT INTO college (college_code, college_name) VALUES ('T04C', '테스트대학');
INSERT INTO campus (campus_code, campus_name) VALUES ('T04P', '테스트캠퍼스');
INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
VALUES ('T04D', '테스트학과', 'T04C', 'T04P', 'ENG');
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
    ('99994001', 't04.student', crypt('x', gen_salt('bf')), '테스트학생', 'STUDENT'),
    ('99994901', 't04.admin',   crypt('x', gen_salt('bf')), '테스트관리자', 'ADMIN');
INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date)
VALUES ('99994001', 'T04D', 2, 'ENROLLED', 'NEW', '2025-03-01');
INSERT INTO admin (staff_no) VALUES ('99994901');

INSERT INTO permission (permission_code, permission_name)
VALUES ('EXPENDITURE_MANAGE', '지출 등록·승인·반려')
ON CONFLICT (permission_code) DO NOTHING;
INSERT INTO role (role_name, description) VALUES ('T04_ROLE', '테스트');
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM role r, permission p
 WHERE r.role_name = 'T04_ROLE' AND p.permission_code = 'EXPENDITURE_MANAGE';
INSERT INTO user_role (user_id, role_id)
SELECT '99994901', role_id FROM role WHERE role_name = 'T04_ROLE';

INSERT INTO topcit_exam_round (round_name, exam_date) VALUES
    ('T04_ROUND_1', '2026-04-01'), ('T04_ROUND_2', '2026-05-01'), ('T04_ROUND_3', '2026-06-01');

INSERT INTO budget_project (project_year, project_phase, project_name, start_date, end_date)
VALUES (2099, 94, 'T04 테스트 사업', '2099-01-01', '2099-12-31');
INSERT INTO budget_item (item_code, item_name) VALUES ('T04_ITEM', '테스트 항목');
INSERT INTO initial_budget (project_id, budget_item_id, initial_amount, expenditure_limit, status, created_by)
SELECT bp.project_id, bi.budget_item_id, 1000000, 1000000, 'CONFIRMED', '99994901'
  FROM budget_project bp, budget_item bi
 WHERE bp.project_name = 'T04 테스트 사업' AND bi.item_code = 'T04_ITEM';
INSERT INTO professor (professor_id, professor_name) VALUES ('T04PROF', '테스트교수');

INSERT INTO program_type (program_type_code, program_type_name) VALUES ('T04_TYPE', '테스트유형');
INSERT INTO program (program_type_code, program_name, program_date)
VALUES ('T04_TYPE', 'T04 테스트 프로그램', '2026-10-01');

DO $t$
DECLARE
    r1 INT; r2 INT; r3 INT;
    v_proj INT; v_item INT; v_prog INT;
BEGIN
    SELECT round_id INTO r1 FROM topcit_exam_round WHERE round_name = 'T04_ROUND_1';
    SELECT round_id INTO r2 FROM topcit_exam_round WHERE round_name = 'T04_ROUND_2';
    SELECT round_id INTO r3 FROM topcit_exam_round WHERE round_name = 'T04_ROUND_3';
    SELECT project_id INTO v_proj FROM budget_project WHERE project_name = 'T04 테스트 사업';
    SELECT budget_item_id INTO v_item FROM budget_item WHERE item_code = 'T04_ITEM';
    SELECT program_id INTO v_prog FROM program WHERE program_name = 'T04 테스트 프로그램';

    -- TOPCIT 총점 (0~1000)
    PERFORM pg_temp.t_expect_error('1. TOPCIT 총점 1001',
        format($q$INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
                  VALUES ('99994001', %s, 1001, '99994901')$q$, r1), '23514');
    PERFORM pg_temp.t_expect_error('2. TOPCIT 총점 -1',
        format($q$INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
                  VALUES ('99994001', %s, -1, '99994901')$q$, r1), '23514');
    PERFORM pg_temp.t_expect_ok('3. TOPCIT 총점 0 (하한 경계)',
        format($q$INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
                  VALUES ('99994001', %s, 0, '99994901')$q$, r1));
    PERFORM pg_temp.t_expect_ok('4. TOPCIT 총점 1000 (상한 경계)',
        format($q$INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
                  VALUES ('99994001', %s, 1000, '99994901')$q$, r2));
    PERFORM pg_temp.t_expect_error('5. 기존 점수를 1001로 수정',
        format($q$UPDATE topcit_score SET total_score = 1001
                   WHERE student_no = '99994001' AND round_id = %s$q$, r2), '23514');

    -- 지출금액 (> 0) : 직접 입력
    PERFORM pg_temp.t_expect_error('6. 지출금액 0 (직접 입력)',
        format($q$INSERT INTO expenditure (project_id, budget_item_id, expenditure_date, subject_type_code,
                                           professor_id, amount, description, created_by)
                  VALUES (%s, %s, '2099-03-01', 'MAJOR', 'T04PROF', 0, '0원 지출', '99994901')$q$,
               v_proj, v_item), '23514');
    PERFORM pg_temp.t_expect_error('7. 지출금액 -1000 (직접 입력)',
        format($q$INSERT INTO expenditure (project_id, budget_item_id, expenditure_date, subject_type_code,
                                           professor_id, amount, description, created_by)
                  VALUES (%s, %s, '2099-03-01', 'MAJOR', 'T04PROF', -1000, '음수 지출', '99994901')$q$,
               v_proj, v_item), '23514');
    PERFORM pg_temp.t_expect_ok('8. 지출금액 1원 (경계)',
        format($q$INSERT INTO expenditure (project_id, budget_item_id, expenditure_date, subject_type_code,
                                           professor_id, amount, description, created_by)
                  VALUES (%s, %s, '2099-03-01', 'MAJOR', 'T04PROF', 1, '1원 지출', '99994901')$q$,
               v_proj, v_item));

    -- 지출금액 : 업무 함수 경로
    PERFORM pg_temp.t_expect_error('9. 지출금액 0 (업무 함수)',
        format($q$SELECT fn_create_expenditure(%s, %s, DATE '2099-03-02', 'MAJOR', 'T04PROF',
                                               0, '0원 지출', '99994901')$q$, v_proj, v_item), 'P0001');

    -- 그 밖의 범위
    PERFORM pg_temp.t_expect_error('10. 학년 5',
        $q$UPDATE student SET grade = 5 WHERE student_no = '99994001'$q$, '23514');
    PERFORM pg_temp.t_expect_error('11. 학년 0',
        $q$UPDATE student SET grade = 0 WHERE student_no = '99994001'$q$, '23514');
    PERFORM pg_temp.t_expect_error('12. 마일리지 신청값 0',
        format($q$INSERT INTO mileage_application
                     (student_no, source_type, program_id, registration_path, registered_by,
                      participation_type, requested_mileage)
                  VALUES ('99994001', 'PROGRAM', %s, 'STUDENT_REQUEST', '99994001', 'PARTICIPATION', 0)$q$,
               v_prog), '23514');
    PERFORM pg_temp.t_expect_error('13. 프로그램 마일리지 기준 음수',
        format($q$INSERT INTO mileage_criteria (program_id, participation_mileage) VALUES (%s, -10)$q$,
               v_prog), '23514');
    PERFORM pg_temp.t_expect_error('14. TOPCIT 마일리지 구간 최소 점수 -1',
        $q$INSERT INTO topcit_mileage_criteria (min_score, max_score, mileage_awarded)
           VALUES (-1, 0, 10)$q$, '23514');

    -- 거부 후 데이터 상태
    PERFORM pg_temp.t_check('15. 거부 후 점수는 경계값 2건만 (0, 1000)',
        (SELECT string_agg(total_score::text, ',' ORDER BY total_score)
           FROM topcit_score WHERE student_no = '99994001') = '0,1000',
        (SELECT string_agg(total_score::text, ',' ORDER BY total_score)
           FROM topcit_score WHERE student_no = '99994001'));
    PERFORM pg_temp.t_check('16. 거부 후 지출은 1원 1건만',
        (SELECT count(*) = 1 AND min(amount) = 1 FROM expenditure WHERE project_id = v_proj),
        (SELECT 'count=' || count(*) FROM expenditure WHERE project_id = v_proj));
    PERFORM pg_temp.t_check('17. 거부 후 학년 2 유지',
        (SELECT grade = 2 FROM student WHERE student_no = '99994001'));
END;
$t$;

\ir _report.sql
ROLLBACK;
