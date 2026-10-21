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
--
-- 승인 함수 공통 순서
--   1) fn_assert_admin 으로 처리자 확인
--   2) 대상 행을 SELECT ... FOR UPDATE 로 잠그고 읽기
--   3) 현재 상태 확인 (이미 처리된 건 거부 → 이중 처리 방지)
--   4) 업무 규칙 확인
--   5) 상태 변경 + 관련 테이블 갱신
--   6) fn_write_change_log 로 기록
--   함수 안에서 에러가 나면 그 함수가 한 변경은 전부 취소된다 (롤백)
-- =====================================================================


-- =====================================================================
-- 1. 공통 함수 (서우진)
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_write_change_log : change_log 기록
--   모든 함수는 change_log에 직접 INSERT하지 않고 이 함수를 호출한다.
--   target_type은 실제 테이블명이어야 한다 (예: 'mileage_application').
--   반환값: 생성된 log_id
--
-- 로그 형식 규칙
--   CREATE        : before = NULL,            after = 생성된 행 전체
--   그 외 작업    : before = 바뀐 항목의 이전 값, after = 바뀐 항목의 새 값
--
-- p_processed_at : 생략하면 현재 시각. seed에서 과거 시점 데이터를 만들 때만 지정
--
-- 사용 예)
--   PERFORM fn_write_change_log(
--       'mileage_application', v_id::text, 'APPROVE',
--       jsonb_build_object('status', 'PENDING'),
--       jsonb_build_object('status', 'APPROVED', 'approved_by', p_admin),
--       p_admin, p_comment);
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_write_change_log(
    p_target_type   TEXT,
    p_target_id     TEXT,
    p_action_type   TEXT,
    p_before_value  JSONB,
    p_after_value   JSONB,
    p_processed_by  TEXT,
    p_reason        TEXT        DEFAULT NULL,
    p_processed_at  TIMESTAMPTZ DEFAULT NULL
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
                            before_value, after_value, processed_by,
                            processed_at, reason)
    VALUES (p_target_type, p_target_id, p_action_type,
            p_before_value, p_after_value, p_processed_by,
            COALESCE(p_processed_at, now()), p_reason)
    RETURNING log_id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- fn_assert_admin : 처리자가 활성 관리자인지 확인
--   관리자가 아니거나 비활성 계정이면 에러를 내고 멈춘다.
--   승인 함수의 맨 앞에서 호출한다.
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
-- ---------------------------------------------------------------------
-- fn_assert_permission : 사용자가 특정 권한을 가지고 있는지 확인
--   user_role → role_permission → permission 경로로 조회 (보고서 6.1)
--   권한이 없거나 비활성 계정이면 에러를 내고 멈춘다.
--   권한 코드는 docs/테스트데이터_기준표.md의 목록을 따른다.
--
-- 사용 예)
--   PERFORM fn_assert_admin(p_admin);
--   PERFORM fn_assert_permission(p_admin, 'EXPENDITURE_MANAGE');
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_assert_permission(
    p_user_id         TEXT,
    p_permission_code TEXT
)
RETURNS VOID AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM app_user u
          JOIN user_role ur       ON ur.user_id = u.user_id
          JOIN role_permission rp ON rp.role_id = ur.role_id
          JOIN permission p       ON p.permission_id = rp.permission_id
         WHERE u.user_id = p_user_id
           AND u.is_active
           AND p.permission_code = p_permission_code
    ) THEN
        RAISE EXCEPTION '해당 업무를 처리할 권한이 없습니다 (사용자 %, 권한 %)',
            p_user_id, p_permission_code
            USING ERRCODE = '42501';   -- insufficient_privilege
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 2. 학생정보 변경 승인 (서우진)
--   요청 → 승인 / 반려
--   변경 가능 항목: phone_number, email, sms_opt_in
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_create_student_info_change_request : 학생이 변경 요청 등록
--   old_value는 학생이 입력하지 않고 현재 값을 자동으로 채운다 (잘못된 기존값 방지)
--   현재 값과 같은 값으로는 요청할 수 없다
--   같은 항목에 대기 중인 요청이 있으면 uq_sicr_one_pending 이 거부한다
--   반환값: 생성된 request_id
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_create_student_info_change_request(
    p_student_no    TEXT,
    p_field_name    TEXT,
    p_new_value     TEXT,
    p_requested_at  TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_student   student%ROWTYPE;
    v_req       student_info_change_request%ROWTYPE;
    v_new_value TEXT := p_new_value;
    v_old_value TEXT;
BEGIN
    SELECT * INTO v_student FROM student WHERE student_no = p_student_no;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 학생입니다 (%)', p_student_no;
    END IF;

    IF p_field_name NOT IN ('phone_number', 'email', 'sms_opt_in') THEN
        RAISE EXCEPTION '변경 요청할 수 없는 항목입니다 (%)', p_field_name;
    END IF;

    -- SMS 수신여부는 'true' / 'false' 로 통일
    IF p_field_name = 'sms_opt_in' THEN
        v_new_value := lower(btrim(p_new_value));
        IF v_new_value NOT IN ('true', 'false') THEN
            RAISE EXCEPTION 'sms_opt_in 값은 true 또는 false 여야 합니다 (%)', p_new_value;
        END IF;
    END IF;

    v_old_value := to_jsonb(v_student) ->> p_field_name;

    IF v_old_value IS NOT DISTINCT FROM v_new_value THEN
        RAISE EXCEPTION '현재 값과 같은 값으로는 변경 요청할 수 없습니다';
    END IF;

    INSERT INTO student_info_change_request
        (student_no, field_name, old_value, new_value, requested_at)
    VALUES
        (p_student_no, p_field_name, v_old_value, v_new_value,
         COALESCE(p_requested_at, now()))
    RETURNING * INTO v_req;

    PERFORM fn_write_change_log(
        'student_info_change_request', v_req.request_id::text, 'CREATE',
        NULL, to_jsonb(v_req),
        p_student_no, '학생정보 변경 요청', v_req.requested_at);

    RETURN v_req.request_id;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- fn_approve_student_info_change : 관리자가 변경 요청 승인
--   요청 상태 PENDING → APPROVED, student의 해당 항목 갱신, 로그 2건 기록
--   요청 이후 학생 정보가 이미 바뀌었으면 승인하지 않는다 (오래된 요청 방지)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_approve_student_info_change(
    p_request_id    BIGINT,
    p_admin         TEXT,
    p_comment       TEXT        DEFAULT NULL,
    p_processed_at  TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_req      student_info_change_request%ROWTYPE;
    v_before   student%ROWTYPE;
    v_after    student%ROWTYPE;
    v_field    TEXT;
    v_at       TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    -- 1) 처리자 확인
    PERFORM fn_assert_admin(p_admin);

    -- 2) 요청 잠그고 읽기
    SELECT * INTO v_req
      FROM student_info_change_request
     WHERE request_id = p_request_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 요청입니다 (%)', p_request_id;
    END IF;

    -- 3) 상태 확인 (이중 승인 방지)
    IF v_req.status <> 'PENDING' THEN
        RAISE EXCEPTION '대기 중인 요청만 승인할 수 있습니다 (현재 상태: %)', v_req.status;
    END IF;

    -- 4) 업무 규칙
    IF v_at < v_req.requested_at THEN
        RAISE EXCEPTION '처리일시가 요청일시보다 빠를 수 없습니다';
    END IF;

    v_field := v_req.field_name;

    SELECT * INTO v_before FROM student
     WHERE student_no = v_req.student_no
       FOR UPDATE;

    IF (to_jsonb(v_before) ->> v_field) IS DISTINCT FROM v_req.old_value THEN
        RAISE EXCEPTION '요청 이후 학생 정보가 변경되었습니다. 요청을 반려하고 다시 요청해야 합니다';
    END IF;

    -- 5) 학생 정보 갱신 (항목별로 분기: 타입이 다른 컬럼이 섞여 있으므로)
    IF v_field = 'phone_number' THEN
        UPDATE student SET phone_number = v_req.new_value
         WHERE student_no = v_req.student_no
        RETURNING * INTO v_after;
    ELSIF v_field = 'email' THEN
        UPDATE student SET email = v_req.new_value
         WHERE student_no = v_req.student_no
        RETURNING * INTO v_after;
    ELSIF v_field = 'sms_opt_in' THEN
        UPDATE student SET sms_opt_in = v_req.new_value::boolean
         WHERE student_no = v_req.student_no
        RETURNING * INTO v_after;
    END IF;

    UPDATE student_info_change_request
       SET status       = 'APPROVED',
           processed_by = p_admin,
           processed_at = v_at,
           comment      = p_comment
     WHERE request_id = p_request_id;

    -- 6) 로그: 요청 상태 변경 + 학생 정보 변경
    PERFORM fn_write_change_log(
        'student_info_change_request', p_request_id::text, 'APPROVE',
        jsonb_build_object('status', 'PENDING'),
        jsonb_strip_nulls(jsonb_build_object(
            'status', 'APPROVED', 'processed_by', p_admin,
            'processed_at', v_at, 'comment', p_comment)),
        p_admin, p_comment, v_at);

    PERFORM fn_write_change_log(
        'student', v_req.student_no, 'UPDATE',
        jsonb_build_object(v_field, to_jsonb(v_before) -> v_field),
        jsonb_build_object(v_field, to_jsonb(v_after)  -> v_field),
        p_admin, '변경 요청 ' || p_request_id || ' 승인 반영', v_at);
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- fn_reject_student_info_change : 관리자가 변경 요청 반려
--   요청 상태 PENDING → REJECTED, 학생 정보는 그대로, 로그 1건 기록
--   반려 사유는 필수
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reject_student_info_change(
    p_request_id    BIGINT,
    p_admin         TEXT,
    p_comment       TEXT,
    p_processed_at  TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_req  student_info_change_request%ROWTYPE;
    v_at   TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    PERFORM fn_assert_admin(p_admin);

    SELECT * INTO v_req
      FROM student_info_change_request
     WHERE request_id = p_request_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 요청입니다 (%)', p_request_id;
    END IF;

    IF v_req.status <> 'PENDING' THEN
        RAISE EXCEPTION '대기 중인 요청만 반려할 수 있습니다 (현재 상태: %)', v_req.status;
    END IF;

    IF p_comment IS NULL OR btrim(p_comment) = '' THEN
        RAISE EXCEPTION '반려 사유를 입력해야 합니다';
    END IF;

    IF v_at < v_req.requested_at THEN
        RAISE EXCEPTION '처리일시가 요청일시보다 빠를 수 없습니다';
    END IF;

    UPDATE student_info_change_request
       SET status       = 'REJECTED',
           processed_by = p_admin,
           processed_at = v_at,
           comment      = p_comment
     WHERE request_id = p_request_id;

    PERFORM fn_write_change_log(
        'student_info_change_request', p_request_id::text, 'REJECT',
        jsonb_build_object('status', 'PENDING'),
        jsonb_build_object(
            'status', 'REJECTED', 'processed_by', p_admin,
            'processed_at', v_at, 'comment', p_comment),
        p_admin, p_comment, v_at);
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- 3. 마일리지 승인 (김건희)
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_approve_mileage_application : 관리자가 마일리지 신청 승인
--   신청 상태 PENDING → APPROVED, 학생 누적 마일리지 갱신, 로그 2건 기록
--   승인 시점의 프로그램·TOPCIT 지급 기준과 신청 마일리지를 다시 확인한다.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_approve_mileage_application(
    p_application_id BIGINT,
    p_admin          TEXT,
    p_comment        TEXT        DEFAULT NULL,
    p_processed_at   TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_application       mileage_application%ROWTYPE;
    v_student           student%ROWTYPE;
    v_student_after     student%ROWTYPE;
    v_expected_mileage  INT;
    v_source_student_no TEXT;
    v_at                TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    -- 1) 처리자 확인
    PERFORM fn_assert_admin(p_admin);
    PERFORM fn_assert_permission(p_admin, 'MILEAGE_MANAGE');
    -- 2) 신청 잠그고 읽기
    SELECT * INTO v_application
      FROM mileage_application
     WHERE application_id = p_application_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 마일리지 신청입니다 (%)', p_application_id;
    END IF;

    -- 3) 상태 확인 (이중 승인·승인/반려 동시 처리 방지)
    IF v_application.status <> 'PENDING' THEN
        RAISE EXCEPTION
            '대기 중인 마일리지 신청만 승인할 수 있습니다 (현재 상태: %)',
            v_application.status;
    END IF;

    IF v_at < v_application.applied_at THEN
        RAISE EXCEPTION '처리일시가 신청일시보다 빠를 수 없습니다';
    END IF;

    IF v_application.requested_mileage <= 0 THEN
        RAISE EXCEPTION '신청 마일리지는 0보다 커야 합니다';
    END IF;

    -- 4) 적립 근거와 승인 시점의 지급 기준 확인
    IF v_application.source_type = 'PROGRAM' THEN
        SELECT CASE v_application.participation_type
                   WHEN 'PARTICIPATION' THEN mc.participation_mileage
                   WHEN 'AWARD' THEN mc.award_mileage
               END
          INTO v_expected_mileage
          FROM program p
          JOIN mileage_criteria mc ON mc.program_id = p.program_id
         WHERE p.program_id = v_application.program_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                '연결된 프로그램 또는 마일리지 지급 기준이 없습니다 (%)',
                v_application.program_id;
        END IF;

        IF v_expected_mileage IS NULL THEN
            RAISE EXCEPTION
                '선택한 참여 구분의 마일리지 지급 기준이 없습니다 (%)',
                v_application.participation_type;
        END IF;
    ELSIF v_application.source_type = 'TOPCIT' THEN
        SELECT ts.student_no, tmc.mileage_awarded
          INTO v_source_student_no, v_expected_mileage
          FROM topcit_score ts
          JOIN topcit_mileage_criteria tmc
            ON int4range(tmc.min_score, tmc.max_score, '[)') @> ts.total_score
         WHERE ts.score_id = v_application.topcit_score_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                '연결된 TOPCIT 점수 또는 마일리지 지급 기준이 없습니다 (%)',
                v_application.topcit_score_id;
        END IF;

        IF v_source_student_no IS DISTINCT FROM v_application.student_no THEN
            RAISE EXCEPTION
                'TOPCIT 점수의 학생과 마일리지 신청 학생이 일치하지 않습니다';
        END IF;
    ELSE
        RAISE EXCEPTION '지원하지 않는 마일리지 적립 근거입니다 (%)',
            v_application.source_type;
    END IF;

    IF v_expected_mileage <= 0 THEN
        RAISE EXCEPTION '지급 기준 마일리지는 0보다 커야 합니다 (%)',
            v_expected_mileage;
    END IF;

    IF v_application.requested_mileage <> v_expected_mileage THEN
        RAISE NOTICE '신청 이후 지급 기준이 변경되었습니다 (신청 시점 %, 현재 %). 신청 시점 값으로 승인합니다',
            v_application.requested_mileage, v_expected_mileage;
    END IF;
    -- 5) 학생 행을 잠근 뒤 신청 승인과 누적 마일리지를 함께 갱신
    SELECT * INTO v_student
      FROM student
     WHERE student_no = v_application.student_no
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 학생입니다 (%)', v_application.student_no;
    END IF;

    UPDATE mileage_application
       SET status      = 'APPROVED',
           approved_by = p_admin,
           approved_at = v_at,
           comment     = p_comment
     WHERE application_id = p_application_id;

    UPDATE student
       SET cumulative_mileage = cumulative_mileage + v_application.requested_mileage
     WHERE student_no = v_application.student_no
    RETURNING * INTO v_student_after;

    -- 6) 로그: 신청 상태 변경 + 학생 누적 마일리지 변경
    PERFORM fn_write_change_log(
        'mileage_application', p_application_id::text, 'APPROVE',
        jsonb_build_object('status', 'PENDING'),
        jsonb_strip_nulls(jsonb_build_object(
            'status', 'APPROVED', 'approved_by', p_admin,
            'approved_at', v_at, 'comment', p_comment)),
        p_admin, p_comment, v_at);

    PERFORM fn_write_change_log(
        'student', v_application.student_no, 'UPDATE',
        jsonb_build_object('cumulative_mileage', v_student.cumulative_mileage),
        jsonb_build_object('cumulative_mileage', v_student_after.cumulative_mileage),
        p_admin, '마일리지 신청 ' || p_application_id || ' 승인 반영', v_at);
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- fn_reject_mileage_application : 관리자가 마일리지 신청 반려
--   신청 상태 PENDING → REJECTED, 누적 마일리지는 변경하지 않고 로그 1건 기록
--   반려 사유는 필수다.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reject_mileage_application(
    p_application_id BIGINT,
    p_admin          TEXT,
    p_comment        TEXT,
    p_processed_at   TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_application mileage_application%ROWTYPE;
    v_at          TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    PERFORM fn_assert_admin(p_admin);
    PERFORM fn_assert_permission(p_admin, 'MILEAGE_MANAGE');
    SELECT * INTO v_application
      FROM mileage_application
     WHERE application_id = p_application_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 마일리지 신청입니다 (%)', p_application_id;
    END IF;

    IF v_application.status <> 'PENDING' THEN
        RAISE EXCEPTION
            '대기 중인 마일리지 신청만 반려할 수 있습니다 (현재 상태: %)',
            v_application.status;
    END IF;

    IF p_comment IS NULL OR btrim(p_comment) = '' THEN
        RAISE EXCEPTION '반려 사유를 입력해야 합니다';
    END IF;

    IF v_at < v_application.applied_at THEN
        RAISE EXCEPTION '처리일시가 신청일시보다 빠를 수 없습니다';
    END IF;

    UPDATE mileage_application
       SET status      = 'REJECTED',
           approved_by = p_admin,
           approved_at = v_at,
           comment     = p_comment
     WHERE application_id = p_application_id;

    PERFORM fn_write_change_log(
        'mileage_application', p_application_id::text, 'REJECT',
        jsonb_build_object('status', 'PENDING'),
        jsonb_build_object(
            'status', 'REJECTED', 'approved_by', p_admin,
            'approved_at', v_at, 'comment', p_comment),
        p_admin, p_comment, v_at);
END;
$$ LANGUAGE plpgsql;



-- =====================================================================
-- fn_create_mileage_application : 지급 기준으로 신청 등록, 관리자 직접 등록은 즉시 승인
--   반환값: 생성된 application_id (기존 등록 함수와 같은 BIGINT 반환)
CREATE OR REPLACE FUNCTION fn_create_mileage_application(
    p_student_no         TEXT,
    p_source_type        TEXT,
    p_registered_by      TEXT,
    p_registration_path  TEXT        DEFAULT 'STUDENT_REQUEST',
    p_program_id         INT         DEFAULT NULL,
    p_topcit_score_id    BIGINT      DEFAULT NULL,
    p_participation_type TEXT        DEFAULT NULL,
    p_memo               TEXT        DEFAULT NULL,
    p_applied_at         TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_application       mileage_application%ROWTYPE;
    v_expected_mileage  INT;
    v_source_student_no TEXT;
    v_at                TIMESTAMPTZ := COALESCE(p_applied_at, now());
BEGIN
    IF NOT EXISTS (SELECT 1 FROM student WHERE student_no = p_student_no) THEN
        RAISE EXCEPTION '존재하지 않는 학생입니다 (%)', p_student_no;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app_user WHERE user_id = p_registered_by AND is_active
    ) THEN
        RAISE EXCEPTION '활성 사용자만 신청을 등록할 수 있습니다 (%)', p_registered_by
            USING ERRCODE = '42501';
    END IF;

    IF p_registration_path = 'ADMIN_DIRECT' THEN
        PERFORM fn_assert_admin(p_registered_by);
        PERFORM fn_assert_permission(p_registered_by, 'MILEAGE_MANAGE');
    ELSIF p_registration_path = 'STUDENT_REQUEST' THEN
        IF p_registered_by IS DISTINCT FROM p_student_no THEN
            RAISE EXCEPTION '학생은 본인 명의로만 신청할 수 있습니다'
                USING ERRCODE = '42501';
        END IF;
    ELSE
        RAISE EXCEPTION '지원하지 않는 신청 등록 경로입니다 (%)', p_registration_path;
    END IF;

    -- 지급 근거와 기준을 잠가 즉시 승인까지 같은 기준을 사용한다.
    IF p_source_type = 'PROGRAM' THEN
        IF p_program_id IS NULL OR p_topcit_score_id IS NOT NULL
           OR p_participation_type IS NULL
           OR p_participation_type NOT IN ('PARTICIPATION', 'AWARD') THEN
            RAISE EXCEPTION '프로그램 신청은 프로그램 ID와 참여·입상 구분이 필요합니다';
        END IF;

        SELECT CASE p_participation_type
                   WHEN 'PARTICIPATION' THEN mc.participation_mileage
                   WHEN 'AWARD' THEN mc.award_mileage
               END
          INTO v_expected_mileage
          FROM program pg
          JOIN mileage_criteria mc ON mc.program_id = pg.program_id
         WHERE pg.program_id = p_program_id
           FOR SHARE OF pg, mc;
        IF NOT FOUND THEN
            RAISE EXCEPTION '연결된 프로그램 또는 마일리지 지급 기준이 없습니다 (%)',
                p_program_id;
        END IF;

        IF EXISTS (
            SELECT 1 FROM mileage_application
             WHERE student_no = p_student_no AND program_id = p_program_id
               AND source_type = 'PROGRAM' AND status IN ('PENDING', 'APPROVED')
        ) THEN
            RAISE EXCEPTION '이미 대기 중이거나 승인된 프로그램 신청이 있습니다';
        END IF;
    ELSIF p_source_type = 'TOPCIT' THEN
        IF p_topcit_score_id IS NULL OR p_program_id IS NOT NULL
           OR p_participation_type IS NOT NULL THEN
            RAISE EXCEPTION 'TOPCIT 신청은 TOPCIT 점수 ID만 지급 근거로 사용합니다';
        END IF;

        SELECT ts.student_no, tmc.mileage_awarded
          INTO v_source_student_no, v_expected_mileage
          FROM topcit_score ts
          JOIN topcit_mileage_criteria tmc
            ON int4range(tmc.min_score, tmc.max_score, '[)') @> ts.total_score
         WHERE ts.score_id = p_topcit_score_id
           FOR SHARE OF ts, tmc;
        IF NOT FOUND THEN
            RAISE EXCEPTION '연결된 TOPCIT 점수 또는 마일리지 지급 기준이 없습니다 (%)',
                p_topcit_score_id;
        END IF;

        IF v_source_student_no IS DISTINCT FROM p_student_no THEN
            RAISE EXCEPTION 'TOPCIT 점수의 학생과 마일리지 신청 학생이 일치하지 않습니다';
        END IF;

        IF EXISTS (
            SELECT 1 FROM mileage_application
             WHERE topcit_score_id = p_topcit_score_id
               AND source_type = 'TOPCIT' AND status IN ('PENDING', 'APPROVED')
        ) THEN
            RAISE EXCEPTION '이미 대기 중이거나 승인된 TOPCIT 신청이 있습니다';
        END IF;
    ELSE
        RAISE EXCEPTION '지원하지 않는 마일리지 적립 근거입니다 (%)', p_source_type;
    END IF;

    IF v_expected_mileage IS NULL OR v_expected_mileage <= 0 THEN
        RAISE EXCEPTION '선택한 유형의 양수 마일리지 지급 기준이 없습니다';
    END IF;

    -- 즉시 승인은 INSERT의 FK 잠금 전에 학생을 잠가 동시 잠금 승격 교착을 막는다.
    IF p_registration_path = 'ADMIN_DIRECT' THEN
        PERFORM 1 FROM student WHERE student_no = p_student_no FOR UPDATE;
    END IF;

    -- 동시 중복 등록은 기존 활성 신청 부분 UNIQUE 인덱스가 최종 차단한다.
    INSERT INTO mileage_application
        (student_no, source_type, program_id, topcit_score_id,
         registration_path, registered_by, participation_type,
         requested_mileage, applied_at, status, memo)
    VALUES
        (p_student_no, p_source_type, p_program_id, p_topcit_score_id,
         p_registration_path, p_registered_by, p_participation_type,
         v_expected_mileage, v_at, 'PENDING', p_memo)
    RETURNING * INTO v_application;

    PERFORM fn_write_change_log(
        'mileage_application', v_application.application_id::text, 'CREATE',
        NULL, to_jsonb(v_application), p_registered_by, '마일리지 신청 등록', v_at);

    -- 예외를 삼키지 않아 승인 실패 시 등록 및 로그도 함께 롤백된다.
    IF p_registration_path = 'ADMIN_DIRECT' THEN
        PERFORM fn_approve_mileage_application(
            v_application.application_id, p_registered_by, p_memo, v_at);
    END IF;

    RETURN v_application.application_id;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- fn_revoke_mileage_application : 승인된 마일리지 회수
CREATE OR REPLACE FUNCTION fn_revoke_mileage_application(
    p_application_id BIGINT,
    p_admin          TEXT,
    p_comment        TEXT,
    p_processed_at   TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_application   mileage_application%ROWTYPE;
    v_student       student%ROWTYPE;
    v_student_after student%ROWTYPE;
    v_at            TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    PERFORM fn_assert_admin(p_admin);
    PERFORM fn_assert_permission(p_admin, 'MILEAGE_MANAGE');

    SELECT * INTO v_application
      FROM mileage_application
     WHERE application_id = p_application_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 마일리지 신청입니다 (%)', p_application_id;
    END IF;

    IF v_application.status <> 'APPROVED' THEN
        RAISE EXCEPTION '승인된 마일리지 신청만 회수할 수 있습니다 (현재 상태: %)',
            v_application.status;
    END IF;

    IF p_comment IS NULL OR p_comment !~ '[^[:space:]]' THEN
        RAISE EXCEPTION '회수 사유를 입력해야 합니다';
    END IF;

    IF v_at < v_application.approved_at THEN
        RAISE EXCEPTION '회수일시가 승인일시보다 빠를 수 없습니다';
    END IF;

    -- 기존 승인 함수와 같은 순서로 신청 → 학생 행을 잠근다.
    SELECT * INTO v_student
      FROM student
     WHERE student_no = v_application.student_no
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 학생입니다 (%)', v_application.student_no;
    END IF;

    IF v_student.cumulative_mileage < v_application.requested_mileage THEN
        RAISE EXCEPTION '누적 마일리지가 기존 지급액보다 작아 회수할 수 없습니다';
    END IF;

    -- requested_mileage가 실제 승인 지급액이므로 현재 지급 기준으로 재계산하지 않는다.
    UPDATE mileage_application
       SET status      = 'REVOKED',
           approved_by = p_admin,
           approved_at = v_at,
           comment     = p_comment
     WHERE application_id = p_application_id;

    UPDATE student
       SET cumulative_mileage = cumulative_mileage - v_application.requested_mileage
     WHERE student_no = v_application.student_no
    RETURNING * INTO v_student_after;

    -- 잠금 시 확보한 승인자·승인일시를 회수 이전 로그에 반드시 남긴다.
    PERFORM fn_write_change_log(
        'mileage_application', p_application_id::text, 'REVOKE',
        jsonb_build_object(
            'status', v_application.status, 'approved_by', v_application.approved_by,
            'approved_at', v_application.approved_at,
            'requested_mileage', v_application.requested_mileage,
            'comment', v_application.comment),
        jsonb_build_object(
            'status', 'REVOKED', 'approved_by', p_admin, 'approved_at', v_at,
            'requested_mileage', v_application.requested_mileage, 'comment', p_comment),
        p_admin, p_comment, v_at);

    PERFORM fn_write_change_log(
        'student', v_application.student_no, 'UPDATE',
        jsonb_build_object('cumulative_mileage', v_student.cumulative_mileage),
        jsonb_build_object('cumulative_mileage', v_student_after.cumulative_mileage),
        p_admin, '마일리지 신청 ' || p_application_id || ' 회수 반영', v_at);
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- fn_cancel_mileage_application : 본인 또는 처리 권한 관리자가 대기 신청 취소
CREATE OR REPLACE FUNCTION fn_cancel_mileage_application(
    p_application_id BIGINT,
    p_processed_by   TEXT,
    p_comment        TEXT        DEFAULT NULL,
    p_processed_at   TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_application mileage_application%ROWTYPE;
    v_at          TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    SELECT * INTO v_application
      FROM mileage_application
     WHERE application_id = p_application_id
       FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '존재하지 않는 마일리지 신청입니다 (%)', p_application_id;
    END IF;

    IF v_application.status <> 'PENDING' THEN
        RAISE EXCEPTION '대기 중인 마일리지 신청만 취소할 수 있습니다 (현재 상태: %)',
            v_application.status;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM app_user WHERE user_id = p_processed_by AND is_active
    ) THEN
        RAISE EXCEPTION '활성 사용자만 신청을 취소할 수 있습니다 (%)', p_processed_by
            USING ERRCODE = '42501';
    END IF;

    IF p_processed_by IS DISTINCT FROM v_application.student_no THEN
        PERFORM fn_assert_admin(p_processed_by);
        PERFORM fn_assert_permission(p_processed_by, 'MILEAGE_MANAGE');
    END IF;

    IF v_at < v_application.applied_at THEN
        RAISE EXCEPTION '취소일시가 신청일시보다 빠를 수 없습니다';
    END IF;

    UPDATE mileage_application
       SET status = 'CANCELLED', comment = p_comment
     WHERE application_id = p_application_id;

    -- 취소 전용 컬럼이 없으므로 처리자·일시는 공통 로그에 기록한다.
    PERFORM fn_write_change_log(
        'mileage_application', p_application_id::text, 'CANCEL',
        jsonb_build_object('status', v_application.status, 'comment', v_application.comment),
        jsonb_build_object('status', 'CANCELLED', 'comment', p_comment),
        p_processed_by, p_comment, v_at);
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- 4. 지출 승인 (임영효)
-- =====================================================================

-- =====================================================================
-- 지출 등록 함수
-- PENDING 상태로 등록하고 변경 로그 기록
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_create_expenditure(
    p_project_id INT,
    p_budget_item_id INT,
    p_expenditure_date DATE,
    p_subject_type_code TEXT,
    p_professor_id TEXT,
    p_amount BIGINT,
    p_description TEXT,
    p_admin TEXT,
    p_program_id INT DEFAULT NULL,
    p_created_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    v_exp expenditure%ROWTYPE;
    v_start_date DATE;
    v_end_date DATE;
BEGIN
    -- 1. 관리자 및 권한 확인
    PERFORM fn_assert_admin(p_admin);
    PERFORM fn_assert_permission(
        p_admin, 'EXPENDITURE_MANAGE'
    );

    -- 2. 입력값 검증
    IF p_expenditure_date IS NULL THEN
        RAISE EXCEPTION '지출일자를 입력해야 합니다';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION '지출금액은 0보다 커야 합니다';
    END IF;

    IF p_description IS NULL OR btrim(p_description) = '' THEN
        RAISE EXCEPTION '지출 내용을 입력해야 합니다';
    END IF;

    -- 3. 사업 및 예산항목 확인
    SELECT bp.start_date, bp.end_date
    INTO v_start_date, v_end_date
    FROM budget_project bp
    JOIN initial_budget ib
      ON ib.project_id = bp.project_id
    WHERE bp.project_id = p_project_id
      AND ib.budget_item_id = p_budget_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            '등록된 사업·예산항목 조합이 없습니다 (사업 %, 예산항목 %)',
            p_project_id, p_budget_item_id;
    END IF;

    -- 4. 지출일자 사업 기간 검증
    IF p_expenditure_date NOT BETWEEN v_start_date AND v_end_date THEN
        RAISE EXCEPTION
            '지출일자가 사업 기간을 벗어났습니다 (%)',
            p_expenditure_date;
    END IF;

    -- 5. 지출 등록
    INSERT INTO expenditure (
        project_id,
        budget_item_id,
        program_id,
        expenditure_date,
        subject_type_code,
        professor_id,
        amount,
        description,
        status,
        created_by,
        created_at
    )
    VALUES (
        p_project_id,
        p_budget_item_id,
        p_program_id,
        p_expenditure_date,
        p_subject_type_code,
        p_professor_id,
        p_amount,
        p_description,
        'PENDING',
        p_admin,
        COALESCE(p_created_at, now())
    )
    RETURNING * INTO v_exp;

    -- 6. 등록 로그
    PERFORM fn_write_change_log(
        'expenditure',
        v_exp.expenditure_id::text,
        'CREATE',
        NULL,
        to_jsonb(v_exp),
        p_admin,
        '지출 등록',
        v_exp.created_at
    );

    RETURN v_exp.expenditure_id;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- 최초예산 확정
-- UNCONFIRMED -> CONFIRMED
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_confirm_initial_budget(
    p_project_id INT,
    p_budget_item_id INT,
    p_admin TEXT,
    p_comment TEXT DEFAULT NULL,
    p_processed_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_budget initial_budget%ROWTYPE;
    v_at TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    -- 1. 권한 확인
    PERFORM fn_assert_admin(p_admin);
    PERFORM fn_assert_permission(
        p_admin, 'BUDGET_MANAGE'
    );

    -- 2. 예산 행 잠금
    SELECT * INTO v_budget
    FROM initial_budget
    WHERE project_id = p_project_id
      AND budget_item_id = p_budget_item_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            '존재하지 않는 최초예산입니다 (사업 %, 예산항목 %)',
            p_project_id, p_budget_item_id;
    END IF;

    -- 3. 상태 확인
    IF v_budget.status <> 'UNCONFIRMED' THEN
        RAISE EXCEPTION
            '미확정 예산만 확정할 수 있습니다 (현재 상태: %)',
            v_budget.status;
    END IF;

    IF v_at < v_budget.created_at THEN
        RAISE EXCEPTION
            '확정일시가 예산 등록일시보다 빠를 수 없습니다';
    END IF;

    -- 4. 예산 확정
    UPDATE initial_budget
    SET status = 'CONFIRMED'
    WHERE project_id = p_project_id
      AND budget_item_id = p_budget_item_id;

    -- 5. 변경 로그 기록
    PERFORM fn_write_change_log(
        'initial_budget',
        p_project_id::text || ':' || p_budget_item_id::text,
        'APPROVE',
        jsonb_build_object('status', 'UNCONFIRMED'),
        jsonb_build_object('status', 'CONFIRMED'),
        p_admin,
        COALESCE(p_comment, '최초예산 확정'),
        v_at
    );
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- 지출 승인
-- PENDING -> APPROVED
-- 이중 승인 방지, 사업 기간 확인, 한도 초과 차단
-- 90% 이상 사용 시 NOTICE 출력
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_approve_expenditure(
    p_expenditure_id BIGINT,
    p_admin TEXT,
    p_comment TEXT DEFAULT NULL,
    p_processed_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_exp expenditure%ROWTYPE;
    v_budget initial_budget%ROWTYPE;
    v_used NUMERIC;
    v_at TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    -- 1. 관리자 및 권한 확인
    PERFORM fn_assert_admin(p_admin);
    PERFORM fn_assert_permission(
        p_admin, 'EXPENDITURE_MANAGE'
    );

    -- 2. 지출 행 잠금
    SELECT * INTO v_exp
    FROM expenditure
    WHERE expenditure_id = p_expenditure_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            '존재하지 않는 지출입니다 (%)',
            p_expenditure_id;
    END IF;

    -- 3. 상태 확인
    IF v_exp.status <> 'PENDING' THEN
        RAISE EXCEPTION
            '대기 중인 지출만 승인할 수 있습니다 (현재 상태: %)',
            v_exp.status;
    END IF;

    IF v_at < v_exp.created_at THEN
        RAISE EXCEPTION
            '처리일시가 지출 등록일시보다 빠를 수 없습니다';
    END IF;

    -- 4. 예산 행 잠금
    SELECT * INTO v_budget
    FROM initial_budget
    WHERE project_id = v_exp.project_id
      AND budget_item_id = v_exp.budget_item_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            '연결된 최초예산이 없습니다 (사업 %, 예산항목 %)',
            v_exp.project_id, v_exp.budget_item_id;
    END IF;

    IF v_budget.status <> 'CONFIRMED' THEN
        RAISE EXCEPTION
            '확정된 예산항목만 지출 승인할 수 있습니다 (현재 상태: %)',
            v_budget.status;
    END IF;

    -- 5. 지출일자가 사업 기간 안인지 확인
    IF NOT EXISTS (
        SELECT 1
        FROM budget_project
        WHERE project_id = v_exp.project_id
          AND v_exp.expenditure_date BETWEEN start_date AND end_date
    ) THEN
        RAISE EXCEPTION
            '지출일자가 사업 기간을 벗어났습니다 (%)',
            v_exp.expenditure_date;
    END IF;

    -- 6. 기존 승인 지출 합계
    SELECT COALESCE(SUM(amount), 0)
    INTO v_used
    FROM expenditure
    WHERE project_id = v_exp.project_id
      AND budget_item_id = v_exp.budget_item_id
      AND status = 'APPROVED';

    -- 7. 지출한도 초과 방지
    IF v_used + v_exp.amount > v_budget.expenditure_limit THEN
        RAISE EXCEPTION
            '지출한도 초과 (기승인 %, 신청 %, 한도 %)',
            v_used,
            v_exp.amount,
            v_budget.expenditure_limit;
    END IF;

    -- 8. 지출 승인
    UPDATE expenditure
    SET status = 'APPROVED',
        approved_by = p_admin,
        approved_at = v_at,
        comment = p_comment
    WHERE expenditure_id = p_expenditure_id;

    -- 9. 지출한도 90% 이상 사용 시 경고
    IF (v_used + v_exp.amount) * 10
       >= v_budget.expenditure_limit::NUMERIC * 9 THEN

        RAISE NOTICE
            '지출한도의 90%% 이상을 사용했습니다 (누적 %, 한도 %)',
            v_used + v_exp.amount,
            v_budget.expenditure_limit;
    END IF;

    -- 10. 변경 로그 기록 (NULL 제거)
    PERFORM fn_write_change_log(
        'expenditure',
        p_expenditure_id::text,
        'APPROVE',
        jsonb_strip_nulls(
            jsonb_build_object(
                'status', v_exp.status,
                'approved_by', v_exp.approved_by,
                'approved_at', v_exp.approved_at,
                'comment', v_exp.comment
            )
        ),
        jsonb_strip_nulls(
            jsonb_build_object(
                'status', 'APPROVED',
                'approved_by', p_admin,
                'approved_at', v_at,
                'comment', p_comment
            )
        ),
        p_admin,
        p_comment,
        v_at
    );
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
-- 지출 반려
-- PENDING -> REJECTED
-- 반려 사유 필수, 승인 집계에는 포함되지 않음
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_reject_expenditure(
    p_expenditure_id BIGINT,
    p_admin TEXT,
    p_comment TEXT,
    p_processed_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_exp expenditure%ROWTYPE;
    v_at TIMESTAMPTZ := COALESCE(p_processed_at, now());
BEGIN
    -- 1. 관리자 및 권한 확인
    PERFORM fn_assert_admin(p_admin);
    PERFORM fn_assert_permission(
        p_admin, 'EXPENDITURE_MANAGE'
    );

    -- 2. 지출 행 잠금
    SELECT * INTO v_exp
    FROM expenditure
    WHERE expenditure_id = p_expenditure_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            '존재하지 않는 지출입니다 (%)',
            p_expenditure_id;
    END IF;

    -- 3. 상태 확인
    IF v_exp.status <> 'PENDING' THEN
        RAISE EXCEPTION
            '대기 중인 지출만 반려할 수 있습니다 (현재 상태: %)',
            v_exp.status;
    END IF;

    -- 4. 반려 사유 필수
    IF p_comment IS NULL OR btrim(p_comment) = '' THEN
        RAISE EXCEPTION
            '반려 사유를 입력해야 합니다';
    END IF;

    IF v_at < v_exp.created_at THEN
        RAISE EXCEPTION
            '처리일시가 지출 등록일시보다 빠를 수 없습니다';
    END IF;

    -- 5. 지출 반려
    UPDATE expenditure
    SET status = 'REJECTED',
        approved_by = p_admin,
        approved_at = v_at,
        comment = p_comment
    WHERE expenditure_id = p_expenditure_id;

    -- 6. 변경 로그 기록 (NULL 제거)
    PERFORM fn_write_change_log(
        'expenditure',
        p_expenditure_id::text,
        'REJECT',
        jsonb_strip_nulls(
            jsonb_build_object(
                'status', v_exp.status,
                'approved_by', v_exp.approved_by,
                'approved_at', v_exp.approved_at,
                'comment', v_exp.comment
            )
        ),
        jsonb_strip_nulls(
            jsonb_build_object(
                'status', 'REJECTED',
                'approved_by', p_admin,
                'approved_at', v_at,
                'comment', p_comment
            )
        ),
        p_admin,
        p_comment,
        v_at
    );
END;
$$ LANGUAGE plpgsql;
