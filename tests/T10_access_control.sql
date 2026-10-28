-- T10_access_control.sql | 학생 본인·관리자·비활성 계정의 조회 범위 검사.
-- 담당: 서우진
-- 조회 쿼리에서 권한 조건을 확인한다. 테이블 직접 조회에 대한 DB 계정 권한 제한은 별개이다.

\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 준비
--   학생 A, B (STUDENT 역할: STUDENT_READ_SELF)
--   학생 C   (STUDENT 역할, 비활성 계정)
--   학생 D   (역할 없음)
--   관리자 M (STUDENT_READ_ALL 있음)
--   관리자 N (역할 없음)
INSERT INTO college (college_code, college_name) VALUES ('T10C', '테스트대학');
INSERT INTO campus (campus_code, campus_name) VALUES ('T10P', '테스트캠퍼스');
INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
VALUES ('T10D', '테스트학과', 'T10C', 'T10P', 'ENG');
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type, is_active) VALUES
    ('99910001', 't10.a', crypt('x', gen_salt('bf')), '학생A', 'STUDENT', true),
    ('99910002', 't10.b', crypt('x', gen_salt('bf')), '학생B', 'STUDENT', true),
    ('99910003', 't10.c', crypt('x', gen_salt('bf')), '학생C', 'STUDENT', false),
    ('99910004', 't10.d', crypt('x', gen_salt('bf')), '학생D', 'STUDENT', true),
    ('99910901', 't10.m', crypt('x', gen_salt('bf')), '관리자M', 'ADMIN', true),
    ('99910902', 't10.n', crypt('x', gen_salt('bf')), '관리자N', 'ADMIN', true);
INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date,
                     phone_number, email)
SELECT v.no, 'T10D', 2, 'ENROLLED', 'NEW', '2025-03-01', '000-0000-' || right(v.no, 4), 't10@example.invalid'
  FROM (VALUES ('99910001'), ('99910002'), ('99910003'), ('99910004')) AS v(no);
INSERT INTO admin (staff_no) VALUES ('99910901'), ('99910902');

INSERT INTO permission (permission_code, permission_name) VALUES
    ('STUDENT_READ_SELF', '본인 학생정보 조회'), ('STUDENT_READ_ALL', '학생정보 업무 조회')
ON CONFLICT (permission_code) DO NOTHING;
INSERT INTO role (role_name, description) VALUES
    ('T10_STUDENT', '테스트 학생'), ('T10_READER', '테스트 조회 관리자');
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM role r JOIN permission p
    ON (r.role_name = 'T10_STUDENT' AND p.permission_code = 'STUDENT_READ_SELF')
    OR (r.role_name = 'T10_READER'  AND p.permission_code = 'STUDENT_READ_ALL');
INSERT INTO user_role (user_id, role_id)
SELECT u.no, r.role_id
  FROM (VALUES ('99910001', 'T10_STUDENT'), ('99910002', 'T10_STUDENT'),
               ('99910003', 'T10_STUDENT'), ('99910901', 'T10_READER')) AS u(no, role_name)
  JOIN role r ON r.role_name = u.role_name;

-- Q01 [2]의 조회 범위 조건과 같은 함수: 요청자가 대상 학생 행을 몇 개 볼 수 있는지
CREATE FUNCTION pg_temp.q01_visible(p_requester text, p_student_no text)
RETURNS int AS $f$
    WITH requester_permission AS (
        SELECT p.permission_code
          FROM app_user u
          JOIN user_role ur       ON ur.user_id = u.user_id
          JOIN role_permission rp ON rp.role_id = ur.role_id
          JOIN permission p       ON p.permission_id = rp.permission_id
         WHERE u.user_id = p_requester
           AND u.is_active
    )
    SELECT count(*)::int
      FROM student s
     WHERE s.student_no = p_student_no
       AND (   (s.student_no = p_requester
                AND EXISTS (SELECT 1 FROM requester_permission WHERE permission_code = 'STUDENT_READ_SELF'))
            OR EXISTS (SELECT 1 FROM requester_permission WHERE permission_code = 'STUDENT_READ_ALL'));
$f$ LANGUAGE sql STABLE;

DO $t$
DECLARE
    n INT;
BEGIN
    n := pg_temp.q01_visible('99910001', '99910001');
    PERFORM pg_temp.t_check('1. 학생 A → 본인(A) 조회: 1행', n = 1, n || '행');

    n := pg_temp.q01_visible('99910001', '99910002');
    PERFORM pg_temp.t_check('2. 학생 A → 다른 학생(B) 조회: 0행', n = 0, n || '행');

    n := pg_temp.q01_visible('99910002', '99910001');
    PERFORM pg_temp.t_check('3. 학생 B → 다른 학생(A) 조회: 0행', n = 0, n || '행');

    n := pg_temp.q01_visible('99910901', '99910002');
    PERFORM pg_temp.t_check('4. 조회 권한 관리자 M → 학생 B: 1행', n = 1, n || '행');

    n := pg_temp.q01_visible('99910902', '99910002');
    PERFORM pg_temp.t_check('5. 권한 없는 관리자 N → 학생 B: 0행 (관리자라는 것만으로는 불가)', n = 0, n || '행');

    n := pg_temp.q01_visible('99910003', '99910003');
    PERFORM pg_temp.t_check('6. 비활성 학생 C → 본인 조회: 0행', n = 0, n || '행');

    n := pg_temp.q01_visible('99910004', '99910004');
    PERFORM pg_temp.t_check('7. 역할 없는 학생 D → 본인 조회: 0행 (계정 존재만으로는 불가)', n = 0, n || '행');

    n := pg_temp.q01_visible('00000000', '99910001');
    PERFORM pg_temp.t_check('8. 없는 사용자 → 학생 A: 0행', n = 0, n || '행');

    -- 9. 관리자 M의 권한을 회수하면 즉시 0행
    DELETE FROM user_role WHERE user_id = '99910901';
    n := pg_temp.q01_visible('99910901', '99910002');
    PERFORM pg_temp.t_check('9. 관리자 M 역할 회수 후 → 학생 B: 0행', n = 0, n || '행');

    -- 10. 관리자 M 계정 비활성화 상태에서 역할을 다시 줘도 0행
    INSERT INTO user_role (user_id, role_id)
    SELECT '99910901', role_id FROM role WHERE role_name = 'T10_READER';
    UPDATE app_user SET is_active = false WHERE user_id = '99910901';
    n := pg_temp.q01_visible('99910901', '99910002');
    PERFORM pg_temp.t_check('10. 비활성 관리자 M (역할 있음) → 학생 B: 0행', n = 0, n || '행');

    -- 11. seed 데이터 기준: 학생 20230001이 20230002 조회 → 0행, 일반관리자 90000002 → 1행
    IF EXISTS (SELECT 1 FROM student WHERE student_no IN ('20230001', '20230002'))
       AND EXISTS (SELECT 1 FROM app_user WHERE user_id = '90000002') THEN
        PERFORM pg_temp.t_check('11. [seed] 20230001 → 20230002: 0행',
            pg_temp.q01_visible('20230001', '20230002') = 0);
        PERFORM pg_temp.t_check('12. [seed] 20230001 → 본인: 1행',
            pg_temp.q01_visible('20230001', '20230001') = 1);
        PERFORM pg_temp.t_check('13. [seed] 일반관리자 90000002 → 20230002: 1행',
            pg_temp.q01_visible('90000002', '20230002') = 1);
    ELSE
        PERFORM pg_temp.t_check('11~13. [seed] seed 데이터 없음 - 건너뜀', true, 'seed 미적용');
    END IF;

    -- 14·15. 마일리지 대기 목록(Q07 조건): 학생은 0행, 조회 권한 관리자만
    PERFORM pg_temp.t_check('14. 학생 A는 마일리지 처리 권한 없음 (Q07 0행)',
        NOT EXISTS (SELECT 1 FROM user_role ur
                      JOIN role_permission rp ON rp.role_id = ur.role_id
                      JOIN permission p ON p.permission_id = rp.permission_id
                     WHERE ur.user_id = '99910001'
                       AND p.permission_code IN ('MILEAGE_MANAGE', 'MILEAGE_READ_ALL')));

    -- 15. 미구현 범위 확인: 조건 없이 직접 SELECT하면 조회된다 (DB 차원 차단 없음)
    SELECT count(*) INTO n FROM student WHERE student_no = '99910002';
    PERFORM pg_temp.t_check('15. [미구현 확인] 조회 범위 조건 없이 직접 SELECT → 1행 조회됨',
        n = 1, 'DB 계정 권한·RLS 차단은 구현 범위 밖 (README 미구현 범위). 애플리케이션 또는 RLS 필요');
END;
$t$;

\ir _report.sql
ROLLBACK;
