\encoding UTF8
-- 01 → 02 → 03 순서로 실행. 가상 계정의 비밀번호는 복구 불가능한 임의 값의 bcrypt 해시이다.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
SELECT pg_advisory_xact_lock(20261015, 1);

DO $$
DECLARE
    seed_user RECORD;
    seed_role RECORD;
    seed_permission RECORD;
BEGIN
    FOR seed_user IN
        SELECT
            (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0') AS user_id,
            'seed.student.' || lpad(ordinal::TEXT, 2, '0') AS login_id,
            '가상학생' || lpad(ordinal::TEXT, 2, '0') AS user_name,
            'STUDENT'::VARCHAR AS user_type
        FROM generate_series(1, 32) AS student_number(ordinal)
        UNION ALL
        SELECT * FROM (VALUES
            ('90000001', 'seed.master', '가상관리자한별', 'ADMIN'),
            ('90000002', 'seed.admin.1', '가상관리자다온', 'ADMIN'),
            ('90000003', 'seed.admin.2', '가상관리자라온', 'ADMIN')
        ) AS admin_user(user_id, login_id, user_name, user_type)
    LOOP
        INSERT INTO app_user (
            user_id, login_id, password_hash, user_name, user_type, created_at
        ) VALUES (
            seed_user.user_id, seed_user.login_id,
            crypt(encode(gen_random_bytes(32), 'hex'), gen_salt('bf', 10)),
            seed_user.user_name, seed_user.user_type, TIMESTAMPTZ '2026-08-01 09:00:00+09'
        ) ON CONFLICT (user_id) DO NOTHING;

        IF NOT EXISTS (
            SELECT 1 FROM app_user AS existing_user
            WHERE existing_user.user_id = seed_user.user_id
              AND to_jsonb(existing_user) @> to_jsonb(seed_user)
              AND existing_user.is_active
              AND existing_user.password_hash ~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$'
        ) THEN
            RAISE EXCEPTION 'Seed 사용자 충돌: % (기존 행을 변경하지 않음)', seed_user.user_id;
        END IF;
    END LOOP;

    INSERT INTO admin (staff_no, dept_name) VALUES
        ('90000001', '가상사업단 총괄'),
        ('90000002', '가상사업단 학생지원'),
        ('90000003', '가상사업단 교육지원')
    ON CONFLICT (staff_no) DO NOTHING;

    IF EXISTS (
        SELECT 1 FROM (VALUES
            ('90000001', '가상사업단 총괄'),
            ('90000002', '가상사업단 학생지원'),
            ('90000003', '가상사업단 교육지원')
        ) AS expected(staff_no, dept_name)
        JOIN admin USING (staff_no)
        WHERE admin.dept_name IS DISTINCT FROM expected.dept_name
    ) THEN
        RAISE EXCEPTION 'Seed 관리자 소속 충돌';
    END IF;

    FOR seed_role IN SELECT * FROM (VALUES
        ('STUDENT', '본인 정보 조회·수정 요청 및 본인 업무 신청'),
        ('GENERAL_ADMIN', '업무 조회와 학생정보 변경 처리 위임; 그 외 관리·승인 제외'),
        ('MASTER_ADMIN', '전체 업무 관리·승인 및 역할 부여')
    ) AS expected(role_name, description)
    LOOP
        INSERT INTO role (role_name, description)
        VALUES (seed_role.role_name, seed_role.description)
        ON CONFLICT (role_name) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM role WHERE to_jsonb(role) @> to_jsonb(seed_role)
        ) THEN
            RAISE EXCEPTION 'Seed 역할 정책 충돌: %', seed_role.role_name;
        END IF;
    END LOOP;

    -- 미구현 업무의 권한도 정책 메타데이터이며, DB 접근 차단 기능을 의미하지 않는다.
    FOR seed_permission IN SELECT * FROM (VALUES
        ('STUDENT_READ_SELF', '본인 학생정보 조회'),
        ('STUDENT_CHANGE_REQUEST', '본인 학생정보 수정 요청'),
        ('TOPCIT_READ_SELF', '본인 TOPCIT 조회'),
        ('MILEAGE_READ_SELF', '본인 마일리지 조회'),
        ('MILEAGE_APPLY', '본인 마일리지 신청·증빙 첨부'),
        ('SURVEY_RESPOND', '본인 만족도 응답'),
        ('STUDENT_READ_ALL', '학생정보 업무 조회'),
        ('STUDENT_CHANGE_PROCESS', '학생정보 수정 요청 승인·반려'),
        ('TOPCIT_READ_ALL', 'TOPCIT 업무 조회'),
        ('TOPCIT_MANAGE', 'TOPCIT 회차·점수 관리'),
        ('MILEAGE_READ_ALL', '마일리지 업무 조회'),
        -- schema/08_procedures.sql의 권한 검사 코드와 동일하게 유지한다.
        ('MILEAGE_MANAGE', '마일리지 승인·반려·회수'),
        ('PROGRAM_MANAGE', '프로그램 관리'),
        ('BUDGET_READ', '예산·지출 조회'),
        ('BUDGET_MANAGE', '예산 관리'),
        ('EXPENDITURE_MANAGE', '지출 등록·승인·반려'),
        ('SURVEY_READ', '만족도 결과 조회'),
        ('SURVEY_MANAGE', '만족도 조사·문항 관리'),
        ('ROLE_MANAGE', '역할·권한 부여'),
        ('CHANGE_LOG_READ', '변경·승인 로그 조회')
    ) AS expected(permission_code, permission_name)
    LOOP
        INSERT INTO permission (permission_code, permission_name)
        VALUES (seed_permission.permission_code, seed_permission.permission_name)
        ON CONFLICT (permission_code) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM permission WHERE to_jsonb(permission) @> to_jsonb(seed_permission)
        ) THEN
            RAISE EXCEPTION 'Seed 기능 코드 충돌: %', seed_permission.permission_code;
        END IF;
    END LOOP;
END;
$$;

INSERT INTO role_permission (role_id, permission_id)
SELECT role.role_id, permission.permission_id
FROM role CROSS JOIN permission
WHERE permission.permission_code IN (
    'STUDENT_READ_SELF', 'STUDENT_CHANGE_REQUEST', 'TOPCIT_READ_SELF',
    'MILEAGE_READ_SELF', 'MILEAGE_APPLY', 'SURVEY_RESPOND',
    'STUDENT_READ_ALL', 'STUDENT_CHANGE_PROCESS', 'TOPCIT_READ_ALL',
    'TOPCIT_MANAGE', 'MILEAGE_READ_ALL', 'MILEAGE_MANAGE', 'PROGRAM_MANAGE',
    'BUDGET_READ', 'BUDGET_MANAGE', 'EXPENDITURE_MANAGE',
    'SURVEY_READ', 'SURVEY_MANAGE', 'ROLE_MANAGE', 'CHANGE_LOG_READ'
)
AND (
    role.role_name = 'MASTER_ADMIN'
    OR (role.role_name = 'STUDENT' AND permission.permission_code IN (
        'STUDENT_READ_SELF', 'STUDENT_CHANGE_REQUEST', 'TOPCIT_READ_SELF',
        'MILEAGE_READ_SELF', 'MILEAGE_APPLY', 'SURVEY_RESPOND'
    ))
    OR (role.role_name = 'GENERAL_ADMIN' AND permission.permission_code IN (
        'STUDENT_READ_ALL', 'STUDENT_CHANGE_PROCESS', 'TOPCIT_READ_ALL',
        'MILEAGE_READ_ALL', 'BUDGET_READ', 'SURVEY_READ', 'CHANGE_LOG_READ'
    ))
)
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO user_role (user_id, role_id, granted_by, granted_at)
SELECT app_user.user_id, role.role_id, '90000001', TIMESTAMPTZ '2026-08-01 09:10:00+09'
FROM app_user JOIN (
    SELECT (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0') AS user_id
    FROM generate_series(1, 32) AS student_number(ordinal)
    UNION ALL SELECT staff_no FROM (VALUES ('90000001'), ('90000002'), ('90000003')) AS administrator(staff_no)
) AS seed_user USING (user_id)
JOIN role ON role.role_name = CASE
    WHEN app_user.user_type = 'STUDENT' THEN 'STUDENT'
    WHEN app_user.user_id = '90000001' THEN 'MASTER_ADMIN'
    ELSE 'GENERAL_ADMIN'
END
ON CONFLICT (user_id, role_id) DO NOTHING;

DO $$
BEGIN
    IF (SELECT count(*) FROM role_permission JOIN role USING (role_id)
        WHERE role_name IN ('STUDENT', 'GENERAL_ADMIN', 'MASTER_ADMIN')) <> 33 THEN
        RAISE EXCEPTION 'Seed 역할에 기존 추가 권한이 있음; 권한 정책 협의 필요';
    END IF;
    IF (SELECT count(*) FROM user_role JOIN app_user USING (user_id)
        WHERE login_id IN ('seed.master', 'seed.admin.1', 'seed.admin.2')
           OR login_id IN (
               SELECT 'seed.student.' || lpad(ordinal::TEXT, 2, '0')
               FROM generate_series(1, 32) AS student_number(ordinal)
           )) <> 35 THEN
        RAISE EXCEPTION 'Seed 사용자에 기존 추가 역할이 있음; 권한 정책 협의 필요';
    END IF;
    IF EXISTS (
        SELECT 1 FROM user_role JOIN app_user USING (user_id)
        WHERE (login_id LIKE 'seed.student.%' OR login_id IN ('seed.master', 'seed.admin.1', 'seed.admin.2'))
          AND (granted_by IS DISTINCT FROM '90000001'
               OR granted_at IS DISTINCT FROM TIMESTAMPTZ '2026-08-01 09:10:00+09')
    ) THEN
        RAISE EXCEPTION 'Seed 역할 부여 이력 충돌';
    END IF;
END;
$$;

COMMIT;
