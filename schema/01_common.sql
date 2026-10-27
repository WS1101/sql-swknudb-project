\encoding UTF8
-- =====================================================================
-- 01_common.sql : 사용자·권한·변경로그 (공통)
-- app_user → admin → role → permission → role_permission → user_role → change_log
-- =====================================================================

-- ---------------------------------------------------------------------
-- 사용자 (슈퍼타입)
--   USER는 PostgreSQL 예약어이므로 app_user로 명명
--   user_id = 학번(학생) / 교번(교직원) 그대로 사용, 접두사 없음 (설계서 7.1)
-- ---------------------------------------------------------------------
CREATE TABLE app_user (
    user_id         VARCHAR(20)  PRIMARY KEY,
    login_id        VARCHAR(50)  NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,          -- crypt(평문, gen_salt('bf')) 결과
    password_changed_at TIMESTAMPTZ,                 -- 비밀번호 변경 일시(최초 등록 시 NULL)  
    user_name       VARCHAR(50)  NOT NULL,          -- 학생·관리자 공통 성명
    user_type       VARCHAR(10)  NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ,
    
    -- CONSTRAINT 제약조건 이름 CHECK/UNIQUE/FOREIGN KEY ...
    CONSTRAINT uq_app_user_login_id  UNIQUE (login_id),
    CONSTRAINT ck_app_user_user_type CHECK (user_type IN ('STUDENT', 'ADMIN')),  -- user type을 두가지로 제약을 둠
    -- 서브타입(student/admin)이 (user_id, user_type) 복합 FK로 참조하기 위한 키
    CONSTRAINT uq_app_user_id_type   UNIQUE (user_id, user_type) -- 같은 유저가 두개의 타입을 같이 못함
);
-- COMMENT는 테이블이나 컬럼에 공식 메타데이터 주석을 남길 수 있는 것임
COMMENT ON TABLE app_user IS '사용자 슈퍼타입. 학생/관리자 공통 로그인 정보';

-- ---------------------------------------------------------------------
-- 관리자 (서브타입, app_user와 1:1)
--   user_type을 'ADMIN'으로 고정하고 (staff_no, user_type)로 FK를 걸어
--   STUDENT 유형의 사용자가 admin 행을 가질 수 없도록 DB 차원에서 강제
-- ---------------------------------------------------------------------
CREATE TABLE admin (
    staff_no        VARCHAR(20)  PRIMARY KEY,
    user_type       VARCHAR(10)  NOT NULL DEFAULT 'ADMIN',
    dept_name       VARCHAR(100),                    -- 소속부서

    CONSTRAINT ck_admin_user_type CHECK (user_type = 'ADMIN'),
    CONSTRAINT fk_admin_app_user  FOREIGN KEY (staff_no, user_type)
        REFERENCES app_user (user_id, user_type)
);

-- ---------------------------------------------------------------------
-- 역할 / 기능 / N:M 연결
-- ---------------------------------------------------------------------
CREATE TABLE role (
    role_id         INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_name       VARCHAR(50)  NOT NULL,
    description     VARCHAR(200),

    CONSTRAINT uq_role_role_name UNIQUE (role_name)
);

CREATE TABLE permission (
    permission_id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    permission_code VARCHAR(50)  NOT NULL,           -- 예: EXPENDITURE_READ
    permission_name VARCHAR(100) NOT NULL,           -- 예: 지출 조회

    CONSTRAINT uq_permission_code UNIQUE (permission_code)
);

CREATE TABLE role_permission (
    role_id         INT          NOT NULL,
    permission_id   INT          NOT NULL,

    CONSTRAINT pk_role_permission PRIMARY KEY (role_id, permission_id),
    CONSTRAINT fk_role_permission_role       FOREIGN KEY (role_id)       REFERENCES role (role_id),
    CONSTRAINT fk_role_permission_permission FOREIGN KEY (permission_id) REFERENCES permission (permission_id)
);

CREATE TABLE user_role (
    user_id         VARCHAR(20)  NOT NULL,
    role_id         INT          NOT NULL,
    granted_by      VARCHAR(20),                     -- 부여한 관리자
    granted_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT pk_user_role PRIMARY KEY (user_id, role_id),
    CONSTRAINT fk_user_role_user       FOREIGN KEY (user_id)    REFERENCES app_user (user_id),
    CONSTRAINT fk_user_role_role       FOREIGN KEY (role_id)    REFERENCES role (role_id),
    CONSTRAINT fk_user_role_granted_by FOREIGN KEY (granted_by) REFERENCES app_user (user_id)
);

-- ---------------------------------------------------------------------
-- 변경로그 (공통 감사로그)
--   target_id : FK 미설정(폴리모픽). 대상 PK가 학번(문자)·대리키(숫자)로
--               섞여 있으므로 VARCHAR로 통일
--   before/after_value : JSONB (설계서 4.1 의도적 1NF 예외)
-- ---------------------------------------------------------------------
CREATE TABLE change_log (
    log_id          BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    target_type     VARCHAR(50)  NOT NULL,           -- 대상 테이블명, 예: 'mileage_application'
    target_id       VARCHAR(50)  NOT NULL,
    action_type     VARCHAR(10)  NOT NULL,
    before_value    JSONB,                           -- CREATE면 NULL
    after_value     JSONB,                           -- DELETE면 NULL
    processed_by    VARCHAR(20)  NOT NULL,
    processed_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    reason          TEXT,

    CONSTRAINT ck_change_log_action_type CHECK (action_type IN
        ('CREATE', 'UPDATE', 'APPROVE', 'REJECT', 'CANCEL', 'DELETE', 'REVOKE')),
    CONSTRAINT fk_change_log_processed_by FOREIGN KEY (processed_by) REFERENCES app_user (user_id)
);

-- 대상별 이력 조회용 인덱스 ("이 신청 건의 변경 이력")
CREATE INDEX ix_change_log_target       ON change_log (target_type, target_id);
CREATE INDEX ix_change_log_processed_by ON change_log (processed_by);

-- change_log는 INSERT만 허용 (설계서 5.2: 수정·삭제 제한)
CREATE OR REPLACE FUNCTION fn_block_change_log_modify()
RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'change_log는 수정하거나 삭제할 수 없습니다';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_change_log_immutable
    BEFORE UPDATE OR DELETE ON change_log
    FOR EACH ROW EXECUTE FUNCTION fn_block_change_log_modify();
