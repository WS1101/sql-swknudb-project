-- =====================================================================
-- 08_procedures.sql : 승인 처리 함수
-- 모든 테이블이 생성된 뒤 실행된다 (01_schema.sql의 마지막 순서)
--
-- 구역
--   1. 공통 함수 (서우진)
--   2. 학생정보 변경 승인 (서우진)
--   3. 마일리지 승인 (김건희)
--   4. 지출 승인 (임영효)
--
-- 각자 자기 구역 안에서만 작성한다 (Git 충돌 방지)
-- =====================================================================


-- =====================================================================
-- 1. 공통 함수 (서우진)
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_write_change_log : change_log 기록
--   모든 승인 함수는 change_log에 직접 INSERT하지 않고 이 함수를 호출한다.
--   target_type은 실제 테이블명이어야 한다 (예: 'mileage_application').
--   반환값: 생성된 log_id
--
-- 사용 예)
--   PERFORM fn_write_change_log(
--       'mileage_application', v_id::text, 'APPROVE',
--       jsonb_build_object('status', 'PENDING'),
--       jsonb_build_object('status', 'APPROVED'),
--       p_admin, p_comment);
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_write_change_log(
    p_target_type   TEXT,
    p_target_id     TEXT,
    p_action_type   TEXT,
    p_before_value  JSONB,
    p_after_value   JSONB,
    p_processed_by  TEXT,
    p_reason        TEXT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_log_id BIGINT;
BEGIN
    -- 오타 방지: target_type이 실제 존재하는 테이블인지 확인
    IF to_regclass('public.' || p_target_type) IS NULL THEN
        RAISE EXCEPTION 'change_log: 존재하지 않는 테이블명입니다 (%)', p_target_type;
    END IF;

    INSERT INTO change_log (target_type, target_id, action_type,
                            before_value, after_value, processed_by, reason)
    VALUES (p_target_type, p_target_id, p_action_type,
            p_before_value, p_after_value, p_processed_by, p_reason)
    RETURNING log_id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- fn_assert_admin : 처리자가 활성 관리자인지 확인
--   관리자가 아니거나 비활성 계정이면 에러를 내고 멈춘다.
--   승인 함수의 맨 앞에서 호출한다.
--
-- 사용 예)
--   PERFORM fn_assert_admin(p_admin);
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_assert_admin(p_user_id TEXT)
RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM admin a
          JOIN app_user u ON u.user_id = a.staff_no
         WHERE a.staff_no = p_user_id
           AND u.is_active
    ) THEN
        RAISE EXCEPTION '활성 관리자만 처리할 수 있습니다 (%)', p_user_id
            USING ERRCODE = '42501';   -- insufficient_privilege
    END IF;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- 2. 학생정보 변경 승인 (서우진)
-- =====================================================================


-- =====================================================================
-- 3. 마일리지 승인 (김건희)
-- =====================================================================


-- =====================================================================
-- 4. 지출 승인 (임영효)
-- =====================================================================
