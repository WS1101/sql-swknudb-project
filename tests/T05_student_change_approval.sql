-- T05_student_change_approval.sql | 학생정보 변경 요청·승인·반려 검사.
-- 담당: 서우진
-- 승인된 요청만 학생 정보와 로그에 반영한다. 중복·재처리·권한 없는 승인은 거부한다.

\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 준비: 학생 1, 처리 권한 있는 관리자 A, 권한 없는 관리자 B
INSERT INTO college (college_code, college_name) VALUES ('T05C', '테스트대학');
INSERT INTO campus (campus_code, campus_name) VALUES ('T05P', '테스트캠퍼스');
INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
VALUES ('T05D', '테스트학과', 'T05C', 'T05P', 'ENG');
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
    ('99995001', 't05.student', crypt('x', gen_salt('bf')), '테스트학생', 'STUDENT'),
    ('99995901', 't05.admin.a', crypt('x', gen_salt('bf')), '처리권한있음', 'ADMIN'),
    ('99995902', 't05.admin.b', crypt('x', gen_salt('bf')), '처리권한없음', 'ADMIN');
INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date,
                     phone_number, sms_opt_in, email)
VALUES ('99995001', 'T05D', 2, 'ENROLLED', 'NEW', '2025-03-01',
        '000-0000-5001', true, 't05@example.invalid');
INSERT INTO admin (staff_no) VALUES ('99995901'), ('99995902');

INSERT INTO permission (permission_code, permission_name)
VALUES ('STUDENT_CHANGE_PROCESS', '학생정보 수정 요청 승인·반려')
ON CONFLICT (permission_code) DO NOTHING;
INSERT INTO role (role_name, description) VALUES ('T05_ROLE', '테스트');
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM role r, permission p
 WHERE r.role_name = 'T05_ROLE' AND p.permission_code = 'STUDENT_CHANGE_PROCESS';
INSERT INTO user_role (user_id, role_id)
SELECT '99995901', role_id FROM role WHERE role_name = 'T05_ROLE';

DO $t$
DECLARE
    req_phone BIGINT;
    req_email BIGINT;
    req_sms   BIGINT;
    v_txt     TEXT;
    v_json    JSONB;
BEGIN
    -- 1. 요청 생성 → 대기, 기존 값 자동 입력, 학생 정보 그대로
    req_phone := fn_create_student_info_change_request('99995001', 'phone_number', '000-0000-5999');
    SELECT status || ' / old=' || old_value INTO v_txt
      FROM student_info_change_request WHERE request_id = req_phone;
    PERFORM pg_temp.t_check('1. 요청 생성 → PENDING, 기존 값 자동 입력',
        v_txt = 'PENDING / old=000-0000-5001', v_txt);
    PERFORM pg_temp.t_check('2. 대기 중에는 학생 전화번호 변경 없음',
        (SELECT phone_number = '000-0000-5001' FROM student WHERE student_no = '99995001'));

    -- 3. 대기 중 같은 항목 재요청 (부분 UNIQUE)
    PERFORM pg_temp.t_expect_error('3. 대기 중 같은 항목 재요청',
        $q$SELECT fn_create_student_info_change_request('99995001', 'phone_number', '000-0000-5888')$q$,
        '23505');

    -- 4. 현재 값과 같은 값으로 요청
    PERFORM pg_temp.t_expect_error('4. 현재 값과 같은 값으로 요청',
        $q$SELECT fn_create_student_info_change_request('99995001', 'email', 't05@example.invalid')$q$,
        'P0001');

    -- 5·6. 변경 요청할 수 없는 항목 (학년은 관리자 변경 항목)
    PERFORM pg_temp.t_expect_error('5. 허용되지 않는 항목(학년) 요청 - 함수',
        $q$SELECT fn_create_student_info_change_request('99995001', 'grade', '3')$q$, 'P0001');
    PERFORM pg_temp.t_expect_error('6. 허용되지 않는 항목(학년) 요청 - 직접 입력',
        $q$INSERT INTO student_info_change_request (student_no, field_name, old_value, new_value)
           VALUES ('99995001', 'grade', '2', '3')$q$, '23514');

    -- 7. 처리 정보 일관성: 승인 상태인데 처리자 없음
    PERFORM pg_temp.t_expect_error('7. 처리자 없이 APPROVED 상태로 직접 입력',
        $q$INSERT INTO student_info_change_request (student_no, field_name, old_value, new_value, status)
           VALUES ('99995001', 'email', 't05@example.invalid', 'x@example.invalid', 'APPROVED')$q$,
        '23514');

    -- 8. 권한 없는 관리자의 승인
    PERFORM pg_temp.t_expect_error('8. 처리 권한 없는 관리자의 승인',
        format($q$SELECT fn_approve_student_info_change(%s, '99995902')$q$, req_phone), '42501');

    -- 9. 학생 본인의 승인 시도
    PERFORM pg_temp.t_expect_error('9. 학생 본인의 승인 시도',
        format($q$SELECT fn_approve_student_info_change(%s, '99995001')$q$, req_phone), '42501');

    -- 10~12. 반려 → 학생 정보 유지
    req_email := fn_create_student_info_change_request('99995001', 'email', 't05.new@example.invalid');
    PERFORM pg_temp.t_expect_error('10. 사유 없이 반려',
        format($q$SELECT fn_reject_student_info_change(%s, '99995901', NULL)$q$, req_email), 'P0001');
    PERFORM fn_reject_student_info_change(req_email, '99995901', '확인 자료 부족');
    SELECT status || ' / ' || processed_by || ' / ' || comment INTO v_txt
      FROM student_info_change_request WHERE request_id = req_email;
    PERFORM pg_temp.t_check('11. 반려 → REJECTED, 처리자·사유 기록',
        v_txt = 'REJECTED / 99995901 / 확인 자료 부족', v_txt);
    PERFORM pg_temp.t_check('12. 반려 후 학생 이메일 그대로',
        (SELECT email = 't05@example.invalid' FROM student WHERE student_no = '99995001'));

    -- 13~16. 승인 → 학생 정보 변경 + 로그
    PERFORM fn_approve_student_info_change(req_phone, '99995901', '확인 완료');
    SELECT status || ' / ' || processed_by INTO v_txt
      FROM student_info_change_request WHERE request_id = req_phone;
    PERFORM pg_temp.t_check('13. 승인 → APPROVED, 처리자 기록', v_txt = 'APPROVED / 99995901', v_txt);
    PERFORM pg_temp.t_check('14. 승인 후 학생 전화번호 변경',
        (SELECT phone_number = '000-0000-5999' FROM student WHERE student_no = '99995001'),
        (SELECT phone_number FROM student WHERE student_no = '99995001'));

    SELECT before_value INTO v_json FROM change_log
     WHERE target_type = 'student_info_change_request' AND target_id = req_phone::text
       AND action_type = 'APPROVE';
    PERFORM pg_temp.t_check('15. 요청 APPROVE 로그 (before = 대기 상태만)',
        v_json = '{"status": "PENDING"}'::jsonb, v_json::text);

    SELECT jsonb_build_object('before', before_value, 'after', after_value) INTO v_json
      FROM change_log
     WHERE target_type = 'student' AND target_id = '99995001'
       AND reason = '변경 요청 ' || req_phone || ' 승인 반영';
    PERFORM pg_temp.t_check('16. 학생 UPDATE 로그 (바뀐 항목만)',
        v_json = '{"before": {"phone_number": "000-0000-5001"}, "after": {"phone_number": "000-0000-5999"}}'::jsonb,
        v_json::text);

    -- 17·18. 이미 처리된 요청 재처리
    PERFORM pg_temp.t_expect_error('17. 승인된 요청 재승인',
        format($q$SELECT fn_approve_student_info_change(%s, '99995901')$q$, req_phone), 'P0001');
    PERFORM pg_temp.t_expect_error('18. 반려된 요청 승인',
        format($q$SELECT fn_approve_student_info_change(%s, '99995901')$q$, req_email), 'P0001');

    -- 19·20. 오래된 요청: 요청 후 다른 경로로 값이 바뀌었으면 승인 거부
    req_sms := fn_create_student_info_change_request('99995001', 'sms_opt_in', 'false');
    UPDATE student SET sms_opt_in = false WHERE student_no = '99995001';
    PERFORM pg_temp.t_expect_error('19. 요청 이후 값이 바뀐 오래된 요청 승인',
        format($q$SELECT fn_approve_student_info_change(%s, '99995901')$q$, req_sms), 'P0001');
    PERFORM pg_temp.t_check('20. 거부된 오래된 요청은 PENDING 유지',
        (SELECT status = 'PENDING' FROM student_info_change_request WHERE request_id = req_sms));

    -- 21. 반려 후 같은 항목 재요청은 허용
    PERFORM pg_temp.t_expect_ok('21. 반려 후 같은 항목 재요청',
        $q$SELECT fn_create_student_info_change_request('99995001', 'email', 't05.retry@example.invalid')$q$);

    -- 22. 이 학생의 요청 로그 건수: CREATE 4(전화·이메일·SMS·이메일 재요청), APPROVE 1, REJECT 1
    SELECT string_agg(action_type || ':' || cnt, ', ' ORDER BY action_type) INTO v_txt
      FROM (SELECT l.action_type, count(*) AS cnt
              FROM change_log l
              JOIN student_info_change_request r ON r.request_id::text = l.target_id
             WHERE l.target_type = 'student_info_change_request' AND r.student_no = '99995001'
             GROUP BY l.action_type) x;
    PERFORM pg_temp.t_check('22. 요청 로그 CREATE 4 / APPROVE 1 / REJECT 1',
        v_txt = 'APPROVE:1, CREATE:4, REJECT:1', v_txt);
END;
$t$;

\ir _report.sql
ROLLBACK;
