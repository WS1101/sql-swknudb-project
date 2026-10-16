-- 06_budget.sql | 예산·지출 (임영효)
-- 의존성: 01_common(app_user), 02_master(budget_item, professor, expenditure_subject_type), 05_mileage(program)

CREATE TABLE budget_project (
    project_id      INT GENERATED ALWAYS AS IDENTITY,
    project_year    SMALLINT NOT NULL,
    project_phase   SMALLINT NOT NULL,
    project_name    VARCHAR(100) NOT NULL,
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    status          VARCHAR(10) NOT NULL DEFAULT 'PLANNED',
    CONSTRAINT pk_budget_project PRIMARY KEY (project_id),
    CONSTRAINT uq_budget_project_year_phase UNIQUE (project_year, project_phase),
    CONSTRAINT ck_budget_project_year CHECK (project_year BETWEEN 2000 AND 2100),
    CONSTRAINT ck_budget_project_phase CHECK (project_phase > 0),
    CONSTRAINT ck_budget_project_dates CHECK (end_date >= start_date),
    CONSTRAINT ck_budget_project_status CHECK (status IN ('PLANNED', 'ACTIVE', 'COMPLETED', 'CANCELLED'))
);

CREATE TABLE initial_budget (
    project_id        INT NOT NULL,
    budget_item_id    INT NOT NULL,
    initial_amount    BIGINT NOT NULL,
    expenditure_limit BIGINT NOT NULL,
    status            VARCHAR(15) NOT NULL DEFAULT 'UNCONFIRMED',
    created_by        VARCHAR(20) NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_initial_budget PRIMARY KEY (project_id, budget_item_id),
    CONSTRAINT ck_initial_budget_initial_amount CHECK (initial_amount >= 0),
    CONSTRAINT ck_initial_budget_expenditure_limit CHECK (expenditure_limit >= 0),
    CONSTRAINT ck_initial_budget_status CHECK (status IN ('UNCONFIRMED', 'CONFIRMED')),
    CONSTRAINT fk_initial_budget_project FOREIGN KEY (project_id) REFERENCES budget_project (project_id),
    CONSTRAINT fk_initial_budget_budget_item FOREIGN KEY (budget_item_id) REFERENCES budget_item (budget_item_id),
    CONSTRAINT fk_initial_budget_created_by FOREIGN KEY (created_by) REFERENCES app_user (user_id)
);

CREATE TABLE expenditure (
    expenditure_id    BIGINT GENERATED ALWAYS AS IDENTITY,
    project_id        INT NOT NULL,
    budget_item_id    INT NOT NULL,
    program_id        INT, -- 마일리지와 무관한 지출이면 NULL
    expenditure_date  DATE NOT NULL,
    subject_type_code VARCHAR(20) NOT NULL,
    professor_id      VARCHAR(20) NOT NULL,
    amount            BIGINT NOT NULL,
    description       VARCHAR(200) NOT NULL,
    status            VARCHAR(10) NOT NULL DEFAULT 'PENDING',
    created_by        VARCHAR(20) NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_by       VARCHAR(20),
    approved_at       TIMESTAMPTZ,
    comment           VARCHAR(200),
    CONSTRAINT pk_expenditure PRIMARY KEY (expenditure_id),
    CONSTRAINT ck_expenditure_amount CHECK (amount > 0),
    CONSTRAINT ck_expenditure_description CHECK (btrim(description) <> ''),
    CONSTRAINT ck_expenditure_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT ck_expenditure_processing CHECK (
        (status IN ('PENDING', 'CANCELLED') AND approved_by IS NULL AND approved_at IS NULL)
        OR (status IN ('APPROVED', 'REJECTED') AND approved_by IS NOT NULL AND approved_at IS NOT NULL)
    ),
    -- 사업에 배정되지 않은 항목의 지출 등록을 막는 복합 FK
    CONSTRAINT fk_expenditure_initial_budget FOREIGN KEY (project_id, budget_item_id)
        REFERENCES initial_budget (project_id, budget_item_id),
    CONSTRAINT fk_expenditure_program FOREIGN KEY (program_id) REFERENCES program (program_id),
    CONSTRAINT fk_expenditure_subject_type FOREIGN KEY (subject_type_code)
        REFERENCES expenditure_subject_type (subject_type_code),
    CONSTRAINT fk_expenditure_professor FOREIGN KEY (professor_id) REFERENCES professor (professor_id),
    CONSTRAINT fk_expenditure_created_by FOREIGN KEY (created_by) REFERENCES app_user (user_id),
    CONSTRAINT fk_expenditure_approved_by FOREIGN KEY (approved_by) REFERENCES app_user (user_id)
);

CREATE INDEX ix_expenditure_budget_status ON expenditure (project_id, budget_item_id, status);
CREATE INDEX ix_expenditure_professor_subject ON expenditure (professor_id, subject_type_code);
CREATE INDEX ix_expenditure_program ON expenditure (program_id);
CREATE INDEX ix_expenditure_date ON expenditure (expenditure_date);

COMMENT ON TABLE budget_project IS '연도·차수별 SW중심대학사업 예산사업';
COMMENT ON TABLE initial_budget IS '사업별 예산항목 최초예산과 지출한도. 누적액·잔액은 조회 시 계산';
COMMENT ON TABLE expenditure IS '지출 신청과 승인·반려 상태. 승인금액만 집계';
COMMENT ON COLUMN initial_budget.expenditure_limit IS '승인 가능 누적 지출 한도. 승인 함수에서 검사';
COMMENT ON COLUMN expenditure.program_id IS '프로그램 연관 지출일 때만 입력, 일반 지출은 NULL';
