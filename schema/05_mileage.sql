-- =====================================================================
-- 05_mileage.sql : 프로그램, 마일리지 기준, 신청, 증빙자료
-- 담당: 김건희
-- 참조: app_user, program_type, student, topcit_score
-- 생성 순서: program -> mileage_criteria -> mileage_application -> attachment
--
-- 설계 원칙
--   - 일반 프로그램 마일리지와 TOPCIT 마일리지를 하나의 신청 테이블에서 관리한다.
--   - 일반 프로그램 신청은 program_id, TOPCIT 신청은 topcit_score_id만 가진다.
--   - 별도 승인/적립 테이블은 최신 ERD에 없으므로 신청 상태와 requested_mileage를
--     승인 결과 및 실제 적립 근거로 사용한다.
--   - 누적 마일리지는 student.cumulative_mileage에 캐시하며, 승인/회수 처리와
--     change_log 기록은 동일 트랜잭션의 승인 처리 로직에서 수행한다.
-- =====================================================================

-- ---------------------------------------------------------------------
-- SW중심대학사업 프로그램 (마일리지 부여 여부는 mileage_criteria로 구분)
--   프로그램 구분은 기준정보 program_type을 참조한다.
-- ---------------------------------------------------------------------
CREATE TABLE program (
    program_id         INT          GENERATED ALWAYS AS IDENTITY,
    program_type_code  VARCHAR(20)  NOT NULL,
    program_name       VARCHAR(100) NOT NULL,
    program_date       DATE         NOT NULL,
    organizer          VARCHAR(50),
    capacity           INT,

    CONSTRAINT pk_program PRIMARY KEY (program_id),
    CONSTRAINT ck_program_capacity CHECK (capacity IS NULL OR capacity > 0),
    CONSTRAINT fk_program_program_type FOREIGN KEY (program_type_code)
    REFERENCES program_type (program_type_code)
);

CREATE INDEX ix_program_program_type_code ON program (program_type_code);
CREATE INDEX ix_program_program_date ON program (program_date);

COMMENT ON TABLE program IS 'SW중심대학사업 프로그램 (마일리지 부여 여부는 mileage_criteria로 구분)';
COMMENT ON COLUMN program.program_id IS '프로그램 ID';
COMMENT ON COLUMN program.program_type_code IS '프로그램 구분 코드';
COMMENT ON COLUMN program.program_name IS '세부 프로그램명';
COMMENT ON COLUMN program.program_date IS '프로그램 진행 일자';
COMMENT ON COLUMN program.organizer IS '주최·주관 기관';
COMMENT ON COLUMN program.capacity IS '모집 정원';

-- ---------------------------------------------------------------------
-- 프로그램별 마일리지 부여 기준 (program과 1:0..1)
--   참여/입상 중 한 종류만 지급하는 프로그램을 위해 각 점수는 NULL을 허용하되,
--   기준 행에는 적어도 하나의 점수가 있어야 한다.
-- ---------------------------------------------------------------------
CREATE TABLE mileage_criteria (
    program_id             INT NOT NULL,
    participation_mileage  INT,
    award_mileage          INT,

    CONSTRAINT pk_mileage_criteria PRIMARY KEY (program_id),
    CONSTRAINT ck_mileage_criteria_participation_mileage
        CHECK (participation_mileage IS NULL OR participation_mileage >= 0),
    CONSTRAINT ck_mileage_criteria_award_mileage
        CHECK (award_mileage IS NULL OR award_mileage >= 0),
    CONSTRAINT ck_mileage_criteria_value_required
        CHECK (participation_mileage IS NOT NULL OR award_mileage IS NOT NULL),
    CONSTRAINT fk_mileage_criteria_program FOREIGN KEY (program_id)
        REFERENCES program (program_id)
);

COMMENT ON TABLE mileage_criteria IS '프로그램별 참여·입상 마일리지 부여 기준';
COMMENT ON COLUMN mileage_criteria.program_id IS '프로그램 ID';
COMMENT ON COLUMN mileage_criteria.participation_mileage IS '참여 시 부여 마일리지';
COMMENT ON COLUMN mileage_criteria.award_mileage IS '입상 시 부여 마일리지';

-- ---------------------------------------------------------------------
-- 마일리지 적립 신청 및 처리 결과
--   source_type에 따라 일반 프로그램 또는 TOPCIT 점수 중 하나만 참조한다.
--   CANCELLED는 승인 전 신청 취소, REVOKED는 승인 후 적립 회수를 뜻한다.
--   승인·반려·회수 건은 처리자와 처리일시를 함께 보존한다.
-- ---------------------------------------------------------------------
CREATE TABLE mileage_application (
    application_id      BIGINT       GENERATED ALWAYS AS IDENTITY,
    student_no          VARCHAR(20)  NOT NULL,
    source_type         VARCHAR(10)  NOT NULL,
    program_id          INT,
    topcit_score_id     BIGINT,
    registration_path  VARCHAR(20)  NOT NULL,
    registered_by      VARCHAR(20)  NOT NULL,
    participation_type VARCHAR(15),
    requested_mileage  INT          NOT NULL,
    applied_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    status             VARCHAR(10)  NOT NULL DEFAULT 'PENDING',
    memo               VARCHAR(200),
    approved_by        VARCHAR(20),
    approved_at        TIMESTAMPTZ,
    comment            VARCHAR(200),

    CONSTRAINT pk_mileage_application PRIMARY KEY (application_id),
    CONSTRAINT ck_mileage_application_source_type
        CHECK (source_type IN ('PROGRAM', 'TOPCIT')),
    CONSTRAINT ck_mileage_application_registration_path
        CHECK (registration_path IN ('STUDENT_REQUEST', 'ADMIN_DIRECT')),
    CONSTRAINT ck_mileage_application_participation_type
        CHECK (participation_type IS NULL OR participation_type IN ('PARTICIPATION', 'AWARD')),
    CONSTRAINT ck_mileage_application_requested_mileage
        CHECK (requested_mileage > 0),
    CONSTRAINT ck_mileage_application_status
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED', 'REVOKED')),
    -- 일반 프로그램은 참여·입상 구분이 필요하고, TOPCIT는 점수 자체가 지급 근거이다.
    CONSTRAINT ck_mileage_application_source_reference CHECK (
        (source_type = 'PROGRAM'
            AND program_id IS NOT NULL
            AND topcit_score_id IS NULL
            AND participation_type IS NOT NULL)
        OR
        (source_type = 'TOPCIT'
            AND program_id IS NULL
            AND topcit_score_id IS NOT NULL
            AND participation_type IS NULL)
    ),
    -- 학생 직접 신청은 본인 명의로만 등록한다. 관리자는 대리 등록할 수 있다.
    CONSTRAINT ck_mileage_application_student_registration CHECK (
        registration_path <> 'STUDENT_REQUEST' OR registered_by = student_no
    ),
    CONSTRAINT ck_mileage_application_processing CHECK (
        (status IN ('PENDING', 'CANCELLED')
            AND approved_by IS NULL
            AND approved_at IS NULL)
        OR
        (status IN ('APPROVED', 'REJECTED', 'REVOKED')
            AND approved_by IS NOT NULL
            AND approved_at IS NOT NULL)
    ),

    CONSTRAINT fk_mileage_application_student FOREIGN KEY (student_no)
        REFERENCES student (student_no),
    CONSTRAINT fk_mileage_application_program FOREIGN KEY (program_id)
        REFERENCES program (program_id),
    CONSTRAINT fk_mileage_application_topcit_score FOREIGN KEY (topcit_score_id)
        REFERENCES topcit_score (score_id),
    CONSTRAINT fk_mileage_application_registered_by_app_user FOREIGN KEY (registered_by)
        REFERENCES app_user (user_id),
    CONSTRAINT fk_mileage_application_approved_by_app_user FOREIGN KEY (approved_by)
        REFERENCES app_user (user_id)
);

CREATE INDEX ix_mileage_application_student_no ON mileage_application (student_no);
CREATE INDEX ix_mileage_application_program_id ON mileage_application (program_id);
CREATE INDEX ix_mileage_application_topcit_score_id ON mileage_application (topcit_score_id);
CREATE INDEX ix_mileage_application_status ON mileage_application (status)
    WHERE status = 'PENDING';

-- 처리 중이거나 승인된 동일 프로그램 신청만 중복을 막는다.
-- 반려·취소·회수 후에는 새 신청을 만들 수 있어 처리 이력이 보존된다.
CREATE UNIQUE INDEX uq_mileage_application_active_program
    ON mileage_application (student_no, program_id)
    WHERE source_type = 'PROGRAM' AND status IN ('PENDING', 'APPROVED');

-- topcit_score는 학생+회차가 이미 UNIQUE이므로 점수 ID별 활성 신청을 하나로 제한하면
-- 동일 학생·동일 회차의 TOPCIT 마일리지 중복 지급도 방지된다.
CREATE UNIQUE INDEX uq_mileage_application_active_topcit
    ON mileage_application (topcit_score_id)
    WHERE source_type = 'TOPCIT' AND status IN ('PENDING', 'APPROVED');

COMMENT ON TABLE mileage_application IS '일반 프로그램 또는 TOPCIT 마일리지 적립 신청과 처리 결과';
COMMENT ON COLUMN mileage_application.application_id IS '마일리지 신청 ID';
COMMENT ON COLUMN mileage_application.student_no IS '신청 대상 학생 학번';
COMMENT ON COLUMN mileage_application.source_type IS '적립 근거 유형(PROGRAM/TOPCIT)';
COMMENT ON COLUMN mileage_application.program_id IS '일반 프로그램 ID';
COMMENT ON COLUMN mileage_application.topcit_score_id IS 'TOPCIT 점수 ID';
COMMENT ON COLUMN mileage_application.registration_path IS '등록 경로(STUDENT_REQUEST/ADMIN_DIRECT)';
COMMENT ON COLUMN mileage_application.registered_by IS '신청 등록자';
COMMENT ON COLUMN mileage_application.participation_type IS '프로그램 참여 구분(PARTICIPATION/AWARD)';
COMMENT ON COLUMN mileage_application.requested_mileage IS '신청 마일리지이자 승인 시 실제 적립 마일리지';
COMMENT ON COLUMN mileage_application.applied_at IS '신청일시';
COMMENT ON COLUMN mileage_application.status IS '신청 처리 상태';
COMMENT ON COLUMN mileage_application.memo IS '신청 메모';
COMMENT ON COLUMN mileage_application.approved_by IS '승인·반려·회수 처리자';
COMMENT ON COLUMN mileage_application.approved_at IS '승인·반려·회수 처리일시';
COMMENT ON COLUMN mileage_application.comment IS '처리 의견';

-- ---------------------------------------------------------------------
-- 마일리지 신청 증빙자료
--   파일 바이너리는 저장하지 않고 원본 파일명과 저장 위치만 관리한다.
--   application_id에 UNIQUE가 없으므로 한 신청에 여러 파일을 첨부할 수 있다.
-- ---------------------------------------------------------------------
CREATE TABLE attachment (
    attachment_id  BIGINT       GENERATED ALWAYS AS IDENTITY,
    application_id BIGINT       NOT NULL,
    file_name      VARCHAR(200) NOT NULL,
    file_path      VARCHAR(500) NOT NULL,
    uploaded_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT pk_attachment PRIMARY KEY (attachment_id),
    CONSTRAINT fk_attachment_mileage_application FOREIGN KEY (application_id)
        REFERENCES mileage_application (application_id)
);

CREATE INDEX ix_attachment_application_id ON attachment (application_id);

COMMENT ON TABLE attachment IS '마일리지 신청 증빙파일 메타데이터';
COMMENT ON COLUMN attachment.attachment_id IS '첨부파일 ID';
COMMENT ON COLUMN attachment.application_id IS '마일리지 신청 ID';
COMMENT ON COLUMN attachment.file_name IS '원본 파일명';
COMMENT ON COLUMN attachment.file_path IS '파일 저장 위치';
COMMENT ON COLUMN attachment.uploaded_at IS '파일 등록일시';
