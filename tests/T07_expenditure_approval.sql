-- =====================================================================
-- T07_expenditure_approval.sql : 지출 등록·확정·승인·반려 검증
-- 담당: 임영효
-- 실행: psql -d swknu_db -f tests/T07_expenditure_approval.sql
--
-- 특징
--   - 테스트에 필요한 관리자·권한·사업·예산은 이 파일 안에서 직접 만든다
--     (seed 내용과 무관하게 실행 가능)
--   - 전체를 BEGIN ~ ROLLBACK으로 감싸서 실행 후 DB에 아무것도 남지 않는다
--   - 각 항목 결과를 PASS / FAIL로 출력하고 마지막에 실패 건수를 보여준다
--
-- 테스트 데이터
--   예산 1,000,000원, 지출한도 1,000,000원
--   e1 300,000 / e2 600,000 / e3 200,000 / e4 50,000
--
-- 한도 관련 항목(6, 7)은 T08_budget_limit.sql로 옮겨도 된다
-- =====================================================================

\encoding UTF8
BEGIN;

DO $$
DECLARE
    v_fail    INT := 0;
    v_role    INT;
    v_proj    INT;
    v_item    INT;
    e1        BIGINT;
    e2        BIGINT;
    e3        BIGINT;
    e4        BIGINT;
    v_status  TEXT;
    v_sum     NUMERIC;
    v_cnt     INT;
BEGIN
    -- -----------------------------------------------------------------
    -- 준비: 권한, 역할, 관리자 2명 (권한 있음 / 없음)
    -- -----------------------------------------------------------------
    INSERT INTO permission (permission_code, permission_name) VALUES
        ('BUDGET_MANAGE', '예산 관리'),
        ('EXPENDITURE_MANAGE', '지출 관리')
    ON CONFLICT (permission_code) DO NOTHING;

    INSERT INTO role (role_name, description)
    VALUES ('TEST_BUDGET_ROLE', '테스트용 예산 담당')
    RETURNING role_id INTO v_role;

    INSERT INTO role_permission (role_id, permission_id)
    SELECT v_role, permission_id FROM permission
     WHERE permission_code IN ('BUDGET_MANAGE', 'EXPENDITURE_MANAGE');

    INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
        ('99990001', 'test_budget_ok', crypt('test', gen_salt('bf')), '테스트권한있음', 'ADMIN'),
        ('99990002', 'test_budget_no', crypt('test', gen_salt('bf')), '테스트권한없음', 'ADMIN');
    INSERT INTO admin (staff_no) VALUES ('99990001'), ('99990002');
    INSERT INTO user_role (user_id, role_id) VALUES ('99990001', v_role);

    -- 사업, 예산항목, 최초예산(미확정), 교수
    INSERT INTO budget_project (project_year, project_phase, project_name, start_date, end_date)
    VALUES (2099, 99, '테스트 사업', '2099-01-01', '2099-12-31')
    RETURNING project_id INTO v_proj;

    INSERT INTO budget_item (item_code, item_name)
    VALUES ('TEST_ITEM', '테스트 항목')
    RETURNING budget_item_id INTO v_item;

    INSERT INTO initial_budget (project_id, budget_item_id, initial_amount,
                                expenditure_limit, created_by)
    VALUES (v_proj, v_item, 1000000, 1000000, '99990001');

    INSERT INTO professor (professor_id, professor_name) VALUES ('TESTPROF', '테스트교수');

    RAISE NOTICE '--- 준비 완료 ---';

    -- -----------------------------------------------------------------
    -- 1. 지출 등록 → PENDING
    -- -----------------------------------------------------------------
    e1 := fn_create_expenditure(v_proj, v_item, '2099-03-01', 'MAJOR', 'TESTPROF',
                                300000, '테스트 지출 1', '99990001');
    SELECT status INTO v_status FROM expenditure WHERE expenditure_id = e1;
    IF v_status = 'PENDING' THEN
        RAISE NOTICE 'PASS 1. 지출 등록 → PENDING';
    ELSE
        RAISE NOTICE 'FAIL 1. 지출 등록 상태: %', v_status; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 2. 미확정 예산의 지출 승인 → 거부
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_approve_expenditure(e1, '99990001');
        RAISE NOTICE 'FAIL 2. 미확정 예산인데 승인됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 2. 미확정 예산 승인 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 3. 최초예산 확정 → CONFIRMED
    -- -----------------------------------------------------------------
    PERFORM fn_confirm_initial_budget(v_proj, v_item, '99990001');
    SELECT status INTO v_status FROM initial_budget
     WHERE project_id = v_proj AND budget_item_id = v_item;
    IF v_status = 'CONFIRMED' THEN
        RAISE NOTICE 'PASS 3. 최초예산 확정';
    ELSE
        RAISE NOTICE 'FAIL 3. 최초예산 상태: %', v_status; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 4. 지출 승인 → APPROVED, 로그 CREATE + APPROVE
    -- -----------------------------------------------------------------
    PERFORM fn_approve_expenditure(e1, '99990001', '테스트 승인');
    SELECT status INTO v_status FROM expenditure WHERE expenditure_id = e1;
    SELECT count(*) INTO v_cnt FROM change_log
     WHERE target_type = 'expenditure' AND target_id = e1::text;
    IF v_status = 'APPROVED' AND v_cnt = 2 THEN
        RAISE NOTICE 'PASS 4. 지출 승인, 로그 2건';
    ELSE
        RAISE NOTICE 'FAIL 4. 상태 %, 로그 %건', v_status, v_cnt; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 5. 같은 지출 재승인 → 거부 (이중 승인 방지)
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_approve_expenditure(e1, '99990001');
        RAISE NOTICE 'FAIL 5. 재승인됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 5. 재승인 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 6. 누적 900,000 (90%) 승인 → 승인되고 경고 NOTICE 출력
    -- -----------------------------------------------------------------
    e2 := fn_create_expenditure(v_proj, v_item, '2099-04-01', 'MAJOR', 'TESTPROF',
                                600000, '테스트 지출 2', '99990001');
    PERFORM fn_approve_expenditure(e2, '99990001');   -- 여기서 90% 경고가 보여야 함
    SELECT status INTO v_status FROM expenditure WHERE expenditure_id = e2;
    IF v_status = 'APPROVED' THEN
        RAISE NOTICE 'PASS 6. 90%% 도달 승인 (바로 위에 경고 메시지가 있어야 함)';
    ELSE
        RAISE NOTICE 'FAIL 6. 상태: %', v_status; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 7. 한도 초과 승인 (900,000 + 200,000 > 1,000,000) → 거부, PENDING 유지
    -- -----------------------------------------------------------------
    e3 := fn_create_expenditure(v_proj, v_item, '2099-05-01', 'MAJOR', 'TESTPROF',
                                200000, '테스트 지출 3', '99990001');
    BEGIN
        PERFORM fn_approve_expenditure(e3, '99990001');
        RAISE NOTICE 'FAIL 7. 한도 초과인데 승인됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        SELECT status INTO v_status FROM expenditure WHERE expenditure_id = e3;
        IF v_status = 'PENDING' THEN
            RAISE NOTICE 'PASS 7. 한도 초과 거부, 상태 PENDING 유지: %', SQLERRM;
        ELSE
            RAISE NOTICE 'FAIL 7. 거부됐지만 상태가 %', v_status; v_fail := v_fail + 1;
        END IF;
    END;

    -- -----------------------------------------------------------------
    -- 8. 사유 없는 반려 → 거부 / 사유 있는 반려 → REJECTED
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_reject_expenditure(e3, '99990001', NULL);
        RAISE NOTICE 'FAIL 8-1. 사유 없이 반려됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 8-1. 사유 없는 반려 거부: %', SQLERRM;
    END;

    PERFORM fn_reject_expenditure(e3, '99990001', '한도 초과로 반려');
    SELECT status INTO v_status FROM expenditure WHERE expenditure_id = e3;
    IF v_status = 'REJECTED' THEN
        RAISE NOTICE 'PASS 8-2. 반려 → REJECTED';
    ELSE
        RAISE NOTICE 'FAIL 8-2. 상태: %', v_status; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    -- 9. 권한 없는 관리자의 승인 → 거부 (SQLSTATE 42501)
    -- -----------------------------------------------------------------
    e4 := fn_create_expenditure(v_proj, v_item, '2099-06-01', 'MAJOR', 'TESTPROF',
                                50000, '테스트 지출 4', '99990001');
    BEGIN
        PERFORM fn_approve_expenditure(e4, '99990002');
        RAISE NOTICE 'FAIL 9. 권한 없는데 승인됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = '42501' THEN
            RAISE NOTICE 'PASS 9. 권한 없음 거부: %', SQLERRM;
        ELSE
            RAISE NOTICE 'FAIL 9. 다른 이유로 거부: %', SQLERRM; v_fail := v_fail + 1;
        END IF;
    END;

    -- -----------------------------------------------------------------
    -- 10. 사업 기간 밖 지출일자 등록 → 거부
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_create_expenditure(v_proj, v_item, '2100-01-01', 'MAJOR', 'TESTPROF',
                                      10000, '기간 밖 지출', '99990001');
        RAISE NOTICE 'FAIL 10. 기간 밖인데 등록됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 10. 기간 밖 지출 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 11. 0원 지출 등록 → 거부
    -- -----------------------------------------------------------------
    BEGIN
        PERFORM fn_create_expenditure(v_proj, v_item, '2099-07-01', 'MAJOR', 'TESTPROF',
                                      0, '0원 지출', '99990001');
        RAISE NOTICE 'FAIL 11. 0원인데 등록됨'; v_fail := v_fail + 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'PASS 11. 0원 지출 거부: %', SQLERRM;
    END;

    -- -----------------------------------------------------------------
    -- 12. 승인 합계는 APPROVED만 (e1 + e2 = 900,000), 잔액 100,000
    --     REJECTED(e3), PENDING(e4)은 제외
    -- -----------------------------------------------------------------
    SELECT COALESCE(SUM(amount), 0) INTO v_sum FROM expenditure
     WHERE project_id = v_proj AND budget_item_id = v_item AND status = 'APPROVED';
    IF v_sum = 900000 THEN
        RAISE NOTICE 'PASS 12. 승인 합계 900,000 / 잔액 %', 1000000 - v_sum;
    ELSE
        RAISE NOTICE 'FAIL 12. 승인 합계: % (예상 900,000)', v_sum; v_fail := v_fail + 1;
    END IF;

    -- -----------------------------------------------------------------
    RAISE NOTICE '=== 결과: 실패 %건 ===', v_fail;
END;
$$;

ROLLBACK;
