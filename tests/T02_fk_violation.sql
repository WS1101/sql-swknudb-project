-- =====================================================================
-- T02_fk_violation.sql : 존재하지 않는 대상 참조 거부, 삭제 정책
-- 담당: 서우진
-- 실행: psql -d swknu_db -f tests/T02_fk_violation.sql
--
-- 시나리오 (미션 7장 + 과제 2 "외래키와 삭제·수정 정책")
--   입력        없는 학생·학과·프로그램·TOPCIT 점수를 참조해서 등록 / 참조되는 행 삭제
--   예상 결과   등록 거부(FK 위반, 23503) / 삭제 거부(23503) / 로그 수정·삭제 거부
--   구현 방법   - FK 제약 (자동 강제). ON DELETE는 기본값 NO ACTION → 이력이 있으면 삭제 불가
--               - 학생·관리자 배타성: (id, user_type) 복합 FK (자동 강제)
--               - change_log 수정·삭제: 트리거 (자동 강제)
--               - 업무 함수 경로: 함수 안의 존재 확인 (P0001)
--
-- 이력 보존과의 관계
--   CASCADE를 쓰지 않으므로 TOPCIT·마일리지 이력이 있는 학생이나 학생이 소속된 학과는
--   삭제되지 않는다. 코드 마스터는 DELETE 대신 is_active = false로 비활성화한다.
-- =====================================================================
\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 준비
INSERT INTO college (college_code, college_name) VALUES ('T02C', '테스트대학');
INSERT INTO campus (campus_code, campus_name) VALUES ('T02P', '테스트캠퍼스');
INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
VALUES ('T02D', '테스트학과', 'T02C', 'T02P', 'ENG');

INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
    ('99992001', 't02.student',  crypt('x', gen_salt('bf')), '테스트학생', 'STUDENT'),
    ('99992002', 't02.student2', crypt('x', gen_salt('bf')), '학과없는학생', 'STUDENT'),
    ('99992901', 't02.admin',    crypt('x', gen_salt('bf')), '테스트관리자', 'ADMIN');
INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date)
VALUES ('99992001', 'T02D', 2, 'ENROLLED', 'NEW', '2025-03-01');
INSERT INTO admin (staff_no) VALUES ('99992901');

INSERT INTO program_type (program_type_code, program_type_name) VALUES ('T02_TYPE', '테스트유형');
INSERT INTO program (program_type_code, program_name, program_date)
VALUES ('T02_TYPE', 'T02 테스트 프로그램', '2026-10-01');
INSERT INTO mileage_criteria (program_id, participation_mileage)
SELECT program_id, 10 FROM program WHERE program_name = 'T02 테스트 프로그램';

INSERT INTO topcit_exam_round (round_name, exam_date) VALUES ('T02_ROUND', '2026-10-01');
INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
SELECT '99992001', round_id, 300, '99992901' FROM topcit_exam_round WHERE round_name = 'T02_ROUND';

DO $t$
DECLARE
    v_prog  INT;
    v_round INT;
    v_log   BIGINT;
BEGIN
    SELECT program_id INTO v_prog FROM program WHERE program_name = 'T02 테스트 프로그램';
    SELECT round_id INTO v_round FROM topcit_exam_round WHERE round_name = 'T02_ROUND';

    -- 1. 없는 학과로 학생 등록
    PERFORM pg_temp.t_expect_error('1. 없는 학과 코드로 학생 등록',
        $q$INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date)
           VALUES ('99992002', 'NO_DEPT', 1, 'ENROLLED', 'NEW', '2026-03-01')$q$, '23503');

    -- 2. 없는 학생으로 마일리지 신청 (함수를 거치지 않는 직접 입력)
    PERFORM pg_temp.t_expect_error('2. 없는 학생으로 마일리지 신청 직접 입력',
        format($q$INSERT INTO mileage_application
                   (student_no, source_type, program_id, registration_path, registered_by,
                    participation_type, requested_mileage)
                  VALUES ('00000000', 'PROGRAM', %s, 'ADMIN_DIRECT', '99992901', 'PARTICIPATION', 10)$q$,
               v_prog), '23503');

    -- 3. 없는 프로그램으로 마일리지 신청
    PERFORM pg_temp.t_expect_error('3. 없는 프로그램으로 마일리지 신청',
        $q$INSERT INTO mileage_application
              (student_no, source_type, program_id, registration_path, registered_by,
               participation_type, requested_mileage)
           VALUES ('99992001', 'PROGRAM', -1, 'ADMIN_DIRECT', '99992901', 'PARTICIPATION', 10)$q$, '23503');

    -- 4. 없는 TOPCIT 점수로 마일리지 신청
    PERFORM pg_temp.t_expect_error('4. 없는 TOPCIT 점수로 마일리지 신청',
        $q$INSERT INTO mileage_application
              (student_no, source_type, topcit_score_id, registration_path, registered_by, requested_mileage)
           VALUES ('99992001', 'TOPCIT', -1, 'ADMIN_DIRECT', '99992901', 10)$q$, '23503');

    -- 5. 없는 학생의 TOPCIT 점수 (스냅샷 값을 직접 넣어 FK 검사까지 도달)
    PERFORM pg_temp.t_expect_error('5. 없는 학생의 TOPCIT 점수 등록',
        format($q$INSERT INTO topcit_score (student_no, round_id, total_score,
                                            grade_at_exam, dept_code_at_exam, created_by)
                  VALUES ('00000000', %s, 300, 1, 'T02D', '99992901')$q$, v_round), '23503');

    -- 6. 없는 프로그램으로 만족도 조사 생성
    PERFORM pg_temp.t_expect_error('6. 없는 프로그램으로 만족도 조사 생성',
        $q$INSERT INTO survey (program_id, survey_name, start_date, end_date)
           VALUES (-1, '없는 프로그램 조사', '2026-10-01', '2026-10-10')$q$, '23503');

    -- 7. 관리자 계정을 학생으로 등록 (서브타입 배타성)
    PERFORM pg_temp.t_expect_error('7. 관리자 계정으로 학생 행 생성 (배타성)',
        $q$INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date)
           VALUES ('99992901', 'T02D', 1, 'ENROLLED', 'NEW', '2026-03-01')$q$, '23503');

    -- 8. 학생 계정을 관리자로 등록 (서브타입 배타성)
    PERFORM pg_temp.t_expect_error('8. 학생 계정으로 관리자 행 생성 (배타성)',
        $q$INSERT INTO admin (staff_no) VALUES ('99992001')$q$, '23503');

    -- 9. 학생이 소속된 학과 삭제 (삭제 정책: NO ACTION)
    PERFORM pg_temp.t_expect_error('9. 학생이 소속된 학과 삭제',
        $q$DELETE FROM department WHERE dept_code = 'T02D'$q$, '23503');

    -- 10. TOPCIT 이력이 있는 학생 삭제
    PERFORM pg_temp.t_expect_error('10. TOPCIT 이력이 있는 학생 삭제',
        $q$DELETE FROM student WHERE student_no = '99992001'$q$, '23503');

    -- 11. 코드 마스터는 삭제 대신 비활성화
    PERFORM pg_temp.t_expect_ok('11. 학과 비활성화 (is_active = false) 는 허용',
        $q$UPDATE department SET is_active = false WHERE dept_code = 'T02D'$q$);
    PERFORM pg_temp.t_check('12. 비활성화 후에도 학생의 학과 참조 유지',
        EXISTS (SELECT 1 FROM student s JOIN department d ON d.dept_code = s.dept_code
                 WHERE s.student_no = '99992001' AND NOT d.is_active));

    -- 13·14. 변경 로그는 수정·삭제 불가
    v_log := fn_write_change_log('app_user', '99992001', 'CREATE', NULL, NULL, '99992901', 'T02 테스트');
    PERFORM pg_temp.t_expect_error('13. 변경 로그 수정',
        format($q$UPDATE change_log SET reason = '조작' WHERE log_id = %s$q$, v_log), 'P0001');
    PERFORM pg_temp.t_expect_error('14. 변경 로그 삭제',
        format($q$DELETE FROM change_log WHERE log_id = %s$q$, v_log), 'P0001');

    -- 15. 업무 함수 경로: 없는 학생으로 마일리지 신청
    PERFORM pg_temp.t_expect_error('15. 업무 함수로 없는 학생 마일리지 신청',
        format($q$SELECT fn_create_mileage_application('00000000', 'PROGRAM', '99992901',
                    'ADMIN_DIRECT', %s, NULL, 'PARTICIPATION')$q$, v_prog), 'P0001');

    -- 16. 거부 후에도 기존 데이터 유지
    PERFORM pg_temp.t_check('16. 거부 후 기존 데이터 유지 (학과·학생·점수 각 1건, 신청 0건)',
        (SELECT count(*) FROM department WHERE dept_code = 'T02D') = 1
        AND (SELECT count(*) FROM student WHERE student_no = '99992001') = 1
        AND (SELECT count(*) FROM topcit_score WHERE student_no = '99992001') = 1
        AND (SELECT count(*) FROM mileage_application WHERE program_id = v_prog) = 0);
END;
$t$;

\ir _report.sql
ROLLBACK;
