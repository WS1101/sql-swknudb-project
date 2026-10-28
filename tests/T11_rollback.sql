-- T11_rollback.sql | 승인 처리 도중 오류가 생겼을 때 상태와 변경 로그가 함께 롤백되는지 검사.
-- 담당: 서우진
-- 테스트용 트리거로 로그 기록 오류를 발생시키고 부분 반영이 없는지 확인한다.

\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 실패 주입용 트리거 (ROLLBACK으로 함께 제거됨)
CREATE FUNCTION tmp_t11_fail_log() RETURNS trigger AS $f$
BEGIN
    IF NEW.action_type <> 'CREATE'
       AND NEW.target_type = current_setting('t11.fail_target', true) THEN
        RAISE EXCEPTION 'T11 강제 실패: % 로그 기록 장애', NEW.target_type;
    END IF;
    RETURN NEW;
END;
$f$ LANGUAGE plpgsql;
CREATE TRIGGER tmp_t11_fail_log BEFORE INSERT ON change_log
    FOR EACH ROW EXECUTE FUNCTION tmp_t11_fail_log();

-- 준비: 학생 1, 모든 처리 권한을 가진 관리자 1, 프로그램 2, 예산 1
INSERT INTO college (college_code, college_name) VALUES ('T11C', '테스트대학');
INSERT INTO campus (campus_code, campus_name) VALUES ('T11P', '테스트캠퍼스');
INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
VALUES ('T11D', '테스트학과', 'T11C', 'T11P', 'ENG');
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
    ('99911001', 't11.student', crypt('x', gen_salt('bf')), '테스트학생', 'STUDENT'),
    ('99911901', 't11.admin',   crypt('x', gen_salt('bf')), '테스트관리자', 'ADMIN');
INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date,
                     phone_number, email)
VALUES ('99911001', 'T11D', 2, 'ENROLLED', 'NEW', '2025-03-01', '000-0000-1101', 't11@example.invalid');
INSERT INTO admin (staff_no) VALUES ('99911901');

INSERT INTO permission (permission_code, permission_name) VALUES
    ('STUDENT_CHANGE_PROCESS', '학생정보 수정 요청 승인·반려'),
    ('MILEAGE_MANAGE', '마일리지 승인·반려·회수'),
    ('BUDGET_MANAGE', '예산 관리'),
    ('EXPENDITURE_MANAGE', '지출 등록·승인·반려')
ON CONFLICT (permission_code) DO NOTHING;
INSERT INTO role (role_name, description) VALUES ('T11_ROLE', '테스트');
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM role r, permission p
 WHERE r.role_name = 'T11_ROLE'
   AND p.permission_code IN ('STUDENT_CHANGE_PROCESS', 'MILEAGE_MANAGE', 'BUDGET_MANAGE', 'EXPENDITURE_MANAGE');
INSERT INTO user_role (user_id, role_id)
SELECT '99911901', role_id FROM role WHERE role_name = 'T11_ROLE';

INSERT INTO program_type (program_type_code, program_type_name) VALUES ('T11_TYPE', '테스트유형');
INSERT INTO program (program_type_code, program_name, program_date) VALUES
    ('T11_TYPE', 'T11 프로그램 1', '2026-10-01'),
    ('T11_TYPE', 'T11 프로그램 2', '2026-10-02');
INSERT INTO mileage_criteria (program_id, participation_mileage)
SELECT program_id, 30 FROM program WHERE program_name IN ('T11 프로그램 1', 'T11 프로그램 2');

INSERT INTO budget_project (project_year, project_phase, project_name, start_date, end_date)
VALUES (2099, 91, 'T11 테스트 사업', '2099-01-01', '2099-12-31');
INSERT INTO budget_item (item_code, item_name) VALUES ('T11_ITEM', '테스트 항목');
INSERT INTO initial_budget (project_id, budget_item_id, initial_amount, expenditure_limit, created_by)
SELECT bp.project_id, bi.budget_item_id, 1000000, 1000000, '99911901'
  FROM budget_project bp, budget_item bi
 WHERE bp.project_name = 'T11 테스트 사업' AND bi.item_code = 'T11_ITEM';
INSERT INTO professor (professor_id, professor_name) VALUES ('T11PROF', '테스트교수');

DO $t$
DECLARE
    p1 INT; p2 INT;
    v_proj INT; v_item INT;
    app BIGINT; req BIGINT; exp_id BIGINT;
    v_txt TEXT;
    n INT;
BEGIN
    SELECT program_id INTO p1 FROM program WHERE program_name = 'T11 프로그램 1';
    SELECT program_id INTO p2 FROM program WHERE program_name = 'T11 프로그램 2';
    SELECT project_id INTO v_proj FROM budget_project WHERE project_name = 'T11 테스트 사업';
    SELECT budget_item_id INTO v_item FROM budget_item WHERE item_code = 'T11_ITEM';

    -- (a-1) 마일리지 승인 중 실패
    --   함수 순서: 신청 APPROVED → 학생 누적 +30 → 신청 APPROVE 로그 → 학생 UPDATE 로그(여기서 실패)
    app := fn_create_mileage_application('99911001', 'PROGRAM', '99911001', 'STUDENT_REQUEST',
                                         p1, NULL, 'PARTICIPATION');
    PERFORM set_config('t11.fail_target', 'student', true);
    PERFORM pg_temp.t_expect_error('1. 마일리지 승인 중 마지막 로그 단계 실패',
        format('SELECT fn_approve_mileage_application(%s, %L)', app, '99911901'), 'P0001');

    SELECT format('상태=%s 승인자=%s', status, COALESCE(approved_by, '없음')) INTO v_txt
      FROM mileage_application WHERE application_id = app;
    PERFORM pg_temp.t_check('2. 신청 상태 PENDING 유지 (이미 바꿨던 APPROVED 취소)',
        v_txt = '상태=PENDING 승인자=없음', v_txt);
    PERFORM pg_temp.t_check('3. 학생 누적 마일리지 0 유지 (이미 더했던 +30 취소)',
        (SELECT cumulative_mileage = 0 FROM student WHERE student_no = '99911001'),
        (SELECT 'cumulative=' || cumulative_mileage FROM student WHERE student_no = '99911001'));
    SELECT count(*) INTO n FROM change_log
     WHERE target_type = 'mileage_application' AND target_id = app::text AND action_type = 'APPROVE';
    PERFORM pg_temp.t_check('4. 먼저 기록됐던 신청 APPROVE 로그도 취소 (0건)', n = 0, n || '건');

    -- (a-2) 관리자 직권등록 중 승인 실패 — 바깥 함수(등록)까지 함께 취소
    PERFORM pg_temp.t_expect_error('5. 직권등록(등록+즉시 승인) 중 승인 단계 실패',
        format($q$SELECT fn_create_mileage_application('99911001', 'PROGRAM', %L, 'ADMIN_DIRECT',
                                                       %s, NULL, 'PARTICIPATION')$q$, '99911901', p2), 'P0001');
    SELECT count(*) INTO n FROM mileage_application WHERE student_no = '99911001' AND program_id = p2;
    PERFORM pg_temp.t_check('6. 직권등록 신청 행 자체가 없음 (등록도 취소)', n = 0, n || '건');
    SELECT count(*) INTO n FROM change_log l
     WHERE l.target_type = 'mileage_application'
       AND NOT EXISTS (SELECT 1 FROM mileage_application ma WHERE ma.application_id::text = l.target_id);
    PERFORM pg_temp.t_check('7. 존재하지 않는 신청을 가리키는 로그 0건 (CREATE 로그도 취소)', n = 0, n || '건');

    -- (a-3) 학생정보 승인 중 실패
    --   함수 순서: 학생 이메일 변경 → 요청 APPROVED → 요청 APPROVE 로그 → 학생 UPDATE 로그(실패)
    PERFORM set_config('t11.fail_target', '', true);
    req := fn_create_student_info_change_request('99911001', 'email', 't11.new@example.invalid');
    PERFORM set_config('t11.fail_target', 'student', true);
    PERFORM pg_temp.t_expect_error('8. 학생정보 승인 중 마지막 로그 단계 실패',
        format('SELECT fn_approve_student_info_change(%s, %L)', req, '99911901'), 'P0001');
    SELECT format('요청=%s 이메일=%s', r.status, s.email) INTO v_txt
      FROM student_info_change_request r JOIN student s ON s.student_no = r.student_no
     WHERE r.request_id = req;
    PERFORM pg_temp.t_check('9. 요청 PENDING, 학생 이메일 원래 값 유지',
        v_txt = '요청=PENDING 이메일=t11@example.invalid', v_txt);

    -- (b) 중간 단계 제약조건 위반: 잘못된 이메일 형식으로 승인
    PERFORM set_config('t11.fail_target', '', true);
    PERFORM fn_reject_student_info_change(req, '99911901', '다음 테스트를 위해 정리');
    req := fn_create_student_info_change_request('99911001', 'email', 'invalid-email');
    PERFORM pg_temp.t_expect_error('10. 학생정보 승인 중 이메일 CHECK 위반',
        format('SELECT fn_approve_student_info_change(%s, %L)', req, '99911901'), '23514');
    SELECT format('요청=%s 이메일=%s 승인로그=%s', r.status, s.email,
                  (SELECT count(*) FROM change_log
                    WHERE target_type = 'student_info_change_request'
                      AND target_id = req::text AND action_type = 'APPROVE'))
      INTO v_txt
      FROM student_info_change_request r JOIN student s ON s.student_no = r.student_no
     WHERE r.request_id = req;
    PERFORM pg_temp.t_check('11. 요청 PENDING, 이메일 유지, 승인 로그 0건',
        v_txt = '요청=PENDING 이메일=t11@example.invalid 승인로그=0', v_txt);

    -- (a-4) 지출 승인 중 실패
    --   함수 순서: 지출 APPROVED → 지출 APPROVE 로그(실패)
    PERFORM fn_confirm_initial_budget(v_proj, v_item, '99911901');
    exp_id := fn_create_expenditure(v_proj, v_item, '2099-03-01', 'MAJOR', 'T11PROF',
                                    300000, 'T11 지출', '99911901');
    PERFORM set_config('t11.fail_target', 'expenditure', true);
    PERFORM pg_temp.t_expect_error('12. 지출 승인 중 로그 단계 실패',
        format('SELECT fn_approve_expenditure(%s, %L)', exp_id, '99911901'), 'P0001');
    SELECT format('상태=%s 승인합계=%s', e.status,
                  (SELECT COALESCE(sum(amount), 0) FROM expenditure
                    WHERE project_id = v_proj AND status = 'APPROVED'))
      INTO v_txt
      FROM expenditure e WHERE e.expenditure_id = exp_id;
    PERFORM pg_temp.t_check('13. 지출 PENDING 유지, 승인 합계 0 (잔액 그대로)',
        v_txt = '상태=PENDING 승인합계=0', v_txt);

    -- 장애 해제 후 같은 처리를 다시 하면 정상 반영 → 데이터와 로그가 함께 남음
    PERFORM set_config('t11.fail_target', '', true);
    PERFORM fn_approve_mileage_application(app, '99911901');
    PERFORM fn_approve_expenditure(exp_id, '99911901');

    SELECT format('누적=%s 신청승인로그=%s 학생로그=%s',
                  (SELECT cumulative_mileage FROM student WHERE student_no = '99911001'),
                  (SELECT count(*) FROM change_log WHERE target_type = 'mileage_application'
                      AND target_id = app::text AND action_type = 'APPROVE'),
                  (SELECT count(*) FROM change_log WHERE target_type = 'student'
                      AND target_id = '99911001' AND reason LIKE '마일리지 신청 %'))
      INTO v_txt;
    PERFORM pg_temp.t_check('14. 재처리: 누적 30, 신청 승인 로그 1, 학생 로그 1',
        v_txt = '누적=30 신청승인로그=1 학생로그=1', v_txt);

    PERFORM pg_temp.t_check('15. 재처리: 지출 APPROVED, 승인 로그 1',
        (SELECT status = 'APPROVED' FROM expenditure WHERE expenditure_id = exp_id)
        AND (SELECT count(*) = 1 FROM change_log WHERE target_type = 'expenditure'
               AND target_id = exp_id::text AND action_type = 'APPROVE'));

    -- 16. 최종 일관성: 누적 마일리지 캐시 = 승인 합계
    PERFORM pg_temp.t_check('16. 누적 마일리지 캐시 = 승인 신청 합계',
        (SELECT s.cumulative_mileage = COALESCE(sum(ma.requested_mileage), 0)
           FROM student s
           LEFT JOIN mileage_application ma ON ma.student_no = s.student_no AND ma.status = 'APPROVED'
          WHERE s.student_no = '99911001'
          GROUP BY s.cumulative_mileage));
END;
$t$;

\ir _report.sql
ROLLBACK;
