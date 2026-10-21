-- =====================================================================
-- T06_mileage_approval.sql : 마일리지 등록·승인·반려·취소·회수 검증
-- 담당: 김건희
-- 실행: psql -d swknu_db -f tests/T06_mileage_approval.sql
--
-- 특징
--   - 학생·관리자·학과·프로그램을 이 파일 안에서 직접 만든다 (seed와 무관)
--   - 전체를 BEGIN ~ ROLLBACK으로 감싸서 실행 후 DB에 아무것도 남지 않는다
--   - 각 항목 결과를 PASS / FAIL로 출력하고 마지막에 실패 건수를 보여준다
--
-- 테스트 데이터
--   학생 s1, s2 (누적 0에서 시작)
--   관리자 A(마일리지 권한 있음), B(권한 없음)
--   프로그램 P_A(참여 30, 입상 100), P_B(참여 20, 입상 없음), P_C(참여 10)
-- =====================================================================

\encoding UTF8
BEGIN;

DO $$
DECLARE
    v_fail  INT := 0;
    s1      TEXT := '99999001';
    s2      TEXT := '99999002';
    adm     TEXT := '99990003';   -- 권한 있음
    noperm  TEXT := '99990004';   -- 권한 없음
    v_role  INT;
    p_a     INT;
    p_b     INT;
    p_c     INT;
    v_round INT;
    v_score BIGINT;
    a1      BIGINT;
    a2      BIGINT;
    a3      BIGINT;
    a4      BIGINT;
    a5      BIGINT;
    a6      BIGINT;
    v_cum   INT;
    v_cnt   INT;
    v_txt   TEXT;
    v_exp   INT;
BEGIN
    -- -----------------------------------------------------------------
    -- 준비
    -- -----------------------------------------------------------------
    INSERT INTO permission (permission_code, permission_name)
    VALUES ('MILEAGE_MANAGE', '마일리지 관리') ON CONFLICT (permission_code) DO NOTHING;

    INSERT INTO role (role_name, description) VALUES ('TEST_MILEAGE_ROLE', '테스트용')
    RETURNING role_id INTO v_role;
    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, permission_id FROM permission WHERE permission_code = 'MILEAGE_MANAGE';

    INSERT INTO college (college_code, college_name) VALUES ('TC', '테스트대학');
    INSERT INTO campus (campus_code, campus_name) VALUES ('TCP', '테스트캠퍼스');
    INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
    VALUES ('TD', '테스트학과', 'TC', 'TCP', 'ENG');

    INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
        (adm,    'test_m_adm',    crypt('test', gen_salt('bf')), '권한있음', 'ADMIN'),
        (noperm, 'test_m_noperm', crypt('test', gen_salt('bf')), '권한없음', 'ADMIN'),
        (s1,     'test_m_s1',     crypt('test', gen_salt('bf')), '학생1',   'STUDENT'),
        (s2,     'test_m_s2',     crypt('test', gen_salt('bf')), '학생2',   'STUDENT');
    INSERT INTO admin (staff_no) VALUES (adm), (noperm);
    INSERT INTO user_role (user_id, role_id) VALUES (adm, v_role);
    INSERT INTO student (student_no, dept_code, grade, enrollment_status,
                         admission_type, admission_date) VALUES
        (s1, 'TD', 2, 'ENROLLED', 'NEW', '2025-03-01'),
        (s2, 'TD', 3, 'ENROLLED', 'NEW', '2024-03-01');

    INSERT INTO program_type (program_type_code, program_type_name)
    VALUES ('TEST_TYPE', '테스트') ON CONFLICT DO NOTHING;
    INSERT INTO program (program_type_code, program_name, program_date)
    VALUES ('TEST_TYPE', '테스트 P_A', '2026-10-01') RETURNING program_id INTO p_a;
    INSERT INTO program (program_type_code, program_name, program_date)
    VALUES ('TEST_TYPE', '테스트 P_B', '2026-10-02') RETURNING program_id INTO p_b;
    INSERT INTO program (program_type_code, program_name, program_date)
    VALUES ('TEST_TYPE', '테스트 P_C', '2026-10-03') RETURNING program_id INTO p_c;
    INSERT INTO mileage_criteria (program_id, participation_mileage, award_mileage) VALUES
        (p_a, 30, 100), (p_b, 20, NULL), (p_c, 10, NULL);

    RAISE NOTICE '--- 준비 완료 ---';

    -- -----------------------------------------------------------------
    -- 1. 관리자 직권등록 → 즉시 APPROVED, 누적 +30, 로그 CREATE·APPROVE
    -- -----------------------------------------------------------------
    a1 := fn_create_mileage_application(s1, 'PROGRAM', adm, 'ADMIN_DIRECT',
                                        p_a, NULL, 'PARTICIPATION');
    SELECT status INTO v_txt FROM mileage_application WHERE application_id = a1;
    SELECT cumulative_mileage INTO v_cum FROM student WHERE student_no = s1;
    SELECT count(*) INTO v_cnt FROM change_log
     WHERE target_type = 'mileage_application' AND target_id = a1::text;
    IF v_txt = 'APPROVED' AND v_cum = 30 AND v_cnt = 2 THEN
        RAISE NOTICE 'PASS 1. 직권등록 즉시 승인, 누적 30, 로그 2건';
    ELSE
        RAISE NOTICE 'FAIL 1. 상태 %, 누적 %, 로그 %건', v_txt, v_cum, v_cnt; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 2. 학생 신청 → PENDING, 신청 마일리지는 기준표에서 자동 계산(20)
    -- -----------------------------------------------------------------
    a2 := fn_create_mileage_application(s1, 'PROGRAM', s1, 'STUDENT_REQUEST',
                                        p_b, NULL, 'PARTICIPATION');
    SELECT status || ':' || requested_mileage INTO v_txt
      FROM mileage_application WHERE application_id = a2;
    IF v_txt = 'PENDING:20' THEN
        RAISE NOTICE 'PASS 2. 학생 신청 PENDING, 신청 마일리지 20 자동 계산';
    ELSE
        RAISE NOTICE 'FAIL 2. %', v_txt; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 3. 같은 프로그램 중복 신청 → 거부
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_create_mileage_application(s1, 'PROGRAM', s1, 'STUDENT_REQUEST',
                                              p_b, NULL, 'PARTICIPATION');
        RAISE NOTICE 'FAIL 3. 중복 신청됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 3. 중복 신청 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 4. 다른 학생 명의로 신청 → 거부
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_create_mileage_application(s1, 'PROGRAM', s2, 'STUDENT_REQUEST',
                                              p_c, NULL, 'PARTICIPATION');
        RAISE NOTICE 'FAIL 4. 타인 명의 신청됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 4. 타인 명의 신청 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 5. 입상 옵션 없는 프로그램에 입상 신청 → 거부
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_create_mileage_application(s2, 'PROGRAM', s2, 'STUDENT_REQUEST',
                                              p_b, NULL, 'AWARD');
        RAISE NOTICE 'FAIL 5. 입상 옵션 없는데 신청됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 5. 입상 옵션 없음 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 6. 권한 없는 관리자의 승인 → 거부 (SQLSTATE 42501)
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_approve_mileage_application(a2, noperm);
        RAISE NOTICE 'FAIL 6. 권한 없는데 승인됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' THEN
            RAISE NOTICE 'PASS 6. 권한 없음 거부: %', SQLERRM;
        ELSE
            RAISE NOTICE 'FAIL 6. 다른 이유로 거부: %', SQLERRM; v_fail := v_fail + 1;
        END IF;
    END;

    -- -----------------------------------------------------------------
    -- 7. 승인 → APPROVED, 누적 30 + 20 = 50
    -- -----------------------------------------------------------------
    PERFORM fn_approve_mileage_application(a2, adm, '참여 확인');
    SELECT cumulative_mileage INTO v_cum FROM student WHERE student_no = s1;
    IF v_cum = 50 THEN
        RAISE NOTICE 'PASS 7. 승인 후 누적 50';
    ELSE
        RAISE NOTICE 'FAIL 7. 누적 % (예상 50)', v_cum; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 8. 같은 신청 재승인 → 거부, 누적 그대로 (이중 적립 방지)
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_approve_mileage_application(a2, adm);
        RAISE NOTICE 'FAIL 8. 재승인됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        SELECT cumulative_mileage INTO v_cum FROM student WHERE student_no = s1;
        IF v_cum = 50 THEN
            RAISE NOTICE 'PASS 8. 재승인 거부, 누적 50 유지: %', SQLERRM;
        ELSE
            RAISE NOTICE 'FAIL 8. 거부됐지만 누적 %', v_cum; v_fail := v_fail + 1;
        END IF;
    END;

    -- -----------------------------------------------------------------
    -- 9. 반려: 사유 없으면 거부 / 사유 있으면 REJECTED, 누적 변화 없음
    -- -----------------------------------------------------------------
    a3 := fn_create_mileage_application(s2, 'PROGRAM', s2, 'STUDENT_REQUEST',
                                        p_c, NULL, 'PARTICIPATION');
    BEGIN
        PERFORM fn_reject_mileage_application(a3, adm, NULL);
        RAISE NOTICE 'FAIL 9-1. 사유 없이 반려됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 9-1. 사유 없는 반려 거부: %', SQLERRM;
    END;

    PERFORM fn_reject_mileage_application(a3, adm, '증빙 부족');
    SELECT status INTO v_txt FROM mileage_application WHERE application_id = a3;
    SELECT cumulative_mileage INTO v_cum FROM student WHERE student_no = s2;
    IF v_txt = 'REJECTED' AND v_cum = 0 THEN
        RAISE NOTICE 'PASS 9-2. 반려 REJECTED, 누적 0 유지';
    ELSE
        RAISE NOTICE 'FAIL 9-2. 상태 %, 누적 %', v_txt, v_cum; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 10. 반려 후 같은 프로그램 재신청 → 허용 / 본인 취소 → CANCELLED
    -- -----------------------------------------------------------------
    a4 := fn_create_mileage_application(s2, 'PROGRAM', s2, 'STUDENT_REQUEST',
                                        p_c, NULL, 'PARTICIPATION');
    PERFORM fn_cancel_mileage_application(a4, s2, '본인 취소');
    SELECT status INTO v_txt FROM mileage_application WHERE application_id = a4;
    IF v_txt = 'CANCELLED' THEN
        RAISE NOTICE 'PASS 10. 반려 후 재신청 허용, 본인 취소 CANCELLED';
    ELSE
        RAISE NOTICE 'FAIL 10. 상태 %', v_txt; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 11. 승인된 신청 취소 시도 → 거부
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_cancel_mileage_application(a2, s1, '취소 시도');
        RAISE NOTICE 'FAIL 11. 승인 건이 취소됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 11. 승인 건 취소 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 12. 회수 → REVOKED, 누적 50 - 30 = 20, 로그에 원래 승인자 보존
    -- -----------------------------------------------------------------
    PERFORM fn_revoke_mileage_application(a1, adm, '참여 기록 오류');
    SELECT cumulative_mileage INTO v_cum FROM student WHERE student_no = s1;
    SELECT before_value ->> 'approved_by' INTO v_txt FROM change_log
     WHERE target_type = 'mileage_application' AND target_id = a1::text
       AND action_type = 'REVOKE';
    IF v_cum = 20 AND v_txt = adm THEN
        RAISE NOTICE 'PASS 12. 회수 후 누적 20, 로그에 원래 승인자 %', v_txt;
    ELSE
        RAISE NOTICE 'FAIL 12. 누적 %, 원래 승인자 %', v_cum, v_txt; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 13. 이미 회수된 신청 재회수 → 거부
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_revoke_mileage_application(a1, adm, '재회수');
        RAISE NOTICE 'FAIL 13. 재회수됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 13. 재회수 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 14. 신청 후 기준 변경 → 신청 시점 값(30)으로 승인 (NOTICE 출력)
    -- -----------------------------------------------------------------
    a5 := fn_create_mileage_application(s2, 'PROGRAM', s2, 'STUDENT_REQUEST',
                                        p_a, NULL, 'PARTICIPATION');
    UPDATE mileage_criteria SET participation_mileage = 50 WHERE program_id = p_a;
    PERFORM fn_approve_mileage_application(a5, adm);   -- 기준 변경 NOTICE가 보여야 함
    SELECT cumulative_mileage INTO v_cum FROM student WHERE student_no = s2;
    IF v_cum = 30 THEN
        RAISE NOTICE 'PASS 14. 기준 변경 후에도 신청 시점 30으로 승인';
    ELSE
        RAISE NOTICE 'FAIL 14. 누적 % (예상 30)', v_cum; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 15. TOPCIT 신청 → 점수 구간 기준으로 자동 계산, 승인 시 누적 반영
    --     다른 학생 점수로 신청 → 거부
    -- -----------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM topcit_mileage_criteria) THEN
        INSERT INTO topcit_mileage_criteria (min_score, max_score, mileage_awarded) VALUES
            (0, 150, 30), (150, 250, 50), (250, 300, 75),
            (300, 400, 100), (400, 500, 150), (500, NULL, 250);
    END IF;

    INSERT INTO topcit_exam_round (round_name, exam_date)
    VALUES ('TEST_ROUND_9999', '2026-09-01') RETURNING round_id INTO v_round;
    INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
    VALUES (s1, v_round, 260, adm) RETURNING score_id INTO v_score;

    SELECT mileage_awarded INTO v_exp FROM topcit_mileage_criteria
     WHERE int4range(min_score, max_score, '[)') @> 260;

    a6 := fn_create_mileage_application(s1, 'TOPCIT', s1, 'STUDENT_REQUEST',
                                        NULL, v_score, NULL);
    PERFORM fn_approve_mileage_application(a6, adm);
    SELECT cumulative_mileage INTO v_cum FROM student WHERE student_no = s1;
    IF v_cum = 20 + v_exp THEN
        RAISE NOTICE 'PASS 15-1. TOPCIT 260점 → %점 적립, 누적 %', v_exp, v_cum;
    ELSE
        RAISE NOTICE 'FAIL 15-1. 누적 % (예상 %)', v_cum, 20 + v_exp; v_fail := v_fail + 1;
    END IF;

    BEGIN
        PERFORM fn_create_mileage_application(s2, 'TOPCIT', s2, 'STUDENT_REQUEST',
                                              NULL, v_score, NULL);
        RAISE NOTICE 'FAIL 15-2. 다른 학생 점수로 신청됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 15-2. 다른 학생 점수 신청 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 16. 캐시 일치: 누적 마일리지 = APPROVED 신청 합계
    --     (반려·취소·회수 제외) — 미션 6장 저장형 집계값 검증
    -- -----------------------------------------------------------------
    SELECT count(*) INTO v_cnt
      FROM student s
     WHERE s.student_no IN (s1, s2)
       AND s.cumulative_mileage <> (
           SELECT COALESCE(SUM(requested_mileage), 0) FROM mileage_application m
            WHERE m.student_no = s.student_no AND m.status = 'APPROVED');
    IF v_cnt = 0 THEN
        RAISE NOTICE 'PASS 16. 누적 마일리지 캐시 = 승인 합계 (s1, s2)';
    ELSE
        RAISE NOTICE 'FAIL 16. 불일치 학생 %명', v_cnt; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    RAISE NOTICE '=== 결과: 실패 %건 ===', v_fail;
END;
$$;

ROLLBACK;
