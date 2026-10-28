-- T01_duplicate_key.sql | 학번·교번·로그인 ID 중복 등록 검사.
-- 담당: 서우진
-- 중복은 PK·UNIQUE 오류(23505)로 거부하고 기존 행은 유지해야 한다.

\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 준비: 학과 1, 학생 1, 관리자 1
INSERT INTO college (college_code, college_name) VALUES ('T01C', '테스트대학');
INSERT INTO campus (campus_code, campus_name) VALUES ('T01P', '테스트캠퍼스');
INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
VALUES ('T01D', '테스트학과', 'T01C', 'T01P', 'ENG');

INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
    ('99991001', 't01.student', crypt('x', gen_salt('bf')), '테스트학생', 'STUDENT'),
    ('99991901', 't01.admin',   crypt('x', gen_salt('bf')), '테스트관리자', 'ADMIN');
INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date)
VALUES ('99991001', 'T01D', 2, 'ENROLLED', 'NEW', '2025-03-01');
INSERT INTO admin (staff_no, dept_name) VALUES ('99991901', '테스트부서');

DO $t$
BEGIN
    -- 1. 같은 학번으로 사용자 재등록 (로그인 ID는 다름)
    PERFORM pg_temp.t_expect_error('1. 중복 학번으로 사용자 등록',
        $q$INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type)
           VALUES ('99991001', 't01.other', 'x', '다른사람', 'STUDENT')$q$, '23505');

    -- 2. 같은 로그인 ID로 다른 사용자 등록
    PERFORM pg_temp.t_expect_error('2. 중복 로그인 ID로 사용자 등록',
        $q$INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type)
           VALUES ('99991002', 't01.student', 'x', '다른사람', 'STUDENT')$q$, '23505');

    -- 3. 같은 학번으로 학생 정보 재등록
    PERFORM pg_temp.t_expect_error('3. 중복 학번으로 학생 등록',
        $q$INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date)
           VALUES ('99991001', 'T01D', 3, 'ENROLLED', 'NEW', '2024-03-01')$q$, '23505');

    -- 4. 같은 교번으로 관리자 재등록
    PERFORM pg_temp.t_expect_error('4. 중복 교번으로 관리자 등록',
        $q$INSERT INTO admin (staff_no, dept_name) VALUES ('99991901', '다른부서')$q$, '23505');

    -- 5. 기존 사용자 행 유지
    PERFORM pg_temp.t_check('5. 기존 사용자 행 유지 (이름·로그인 ID·유형)',
        (SELECT user_name = '테스트학생' AND login_id = 't01.student' AND user_type = 'STUDENT'
           FROM app_user WHERE user_id = '99991001'),
        (SELECT format('user_name=%s, login_id=%s', user_name, login_id)
           FROM app_user WHERE user_id = '99991001'));

    -- 6. 기존 학생 행 유지 (3번에서 학년 3으로 덮어쓰지 않음)
    PERFORM pg_temp.t_check('6. 기존 학생 행 유지 (학년 2, 입학일 2025-03-01)',
        (SELECT grade = 2 AND admission_date = DATE '2025-03-01'
           FROM student WHERE student_no = '99991001'),
        (SELECT format('grade=%s, admission_date=%s', grade, admission_date)
           FROM student WHERE student_no = '99991001'));

    -- 7. 로그인 ID별 행 수가 1개 그대로
    PERFORM pg_temp.t_check('7. 로그인 ID t01.student 행 수 = 1',
        (SELECT count(*) = 1 FROM app_user WHERE login_id = 't01.student'),
        (SELECT 'count=' || count(*) FROM app_user WHERE login_id = 't01.student'));

    -- 8. 정상 등록은 가능 (다른 학번·다른 로그인 ID)
    PERFORM pg_temp.t_expect_ok('8. 새 학번·새 로그인 ID 등록은 허용',
        $q$INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type)
           VALUES ('99991003', 't01.new', 'x', '새학생', 'STUDENT')$q$);

    -- 9. 전체 DB에 중복 로그인 ID가 없음 (seed 포함)
    PERFORM pg_temp.t_check('9. 전체 사용자 중 중복 로그인 ID 0건',
        NOT EXISTS (SELECT login_id FROM app_user GROUP BY login_id HAVING count(*) > 1));
END;
$t$;

\ir _report.sql
ROLLBACK;
