-- =====================================================================
-- 02_master.sql : 기준정보(코드 마스터)
-- 담당: 서우진
-- 원칙: DELETE 금지, is_active = FALSE 로 논리삭제 (설계서 5.1)
-- 생성 순서: college → campus → department → professor
--            → budget_item → expenditure_subject_type
--            → academic_term → program_type → survey_question_category
-- =====================================================================

-- ---------------------------------------------------------------------
-- 대학 / 캠퍼스 / 학과
-- ---------------------------------------------------------------------
CREATE TABLE college (
    college_code    VARCHAR(10)  PRIMARY KEY,
    college_name    VARCHAR(100) NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE campus (
    campus_code     VARCHAR(10)  PRIMARY KEY,
    campus_name     VARCHAR(100) NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE department (
    dept_code       VARCHAR(10)  PRIMARY KEY,
    dept_name       VARCHAR(100) NOT NULL,
    college_code    VARCHAR(10)  NOT NULL,
    campus_code     VARCHAR(10)  NOT NULL,
    track_type      CHAR(3)      NOT NULL,           -- 등록계열 (v2: char(2) → char(3))
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT ck_department_track_type CHECK (track_type IN ('ENG', 'NAT')),
    CONSTRAINT fk_department_college FOREIGN KEY (college_code) REFERENCES college (college_code),
    CONSTRAINT fk_department_campus  FOREIGN KEY (campus_code)  REFERENCES campus (campus_code)
);

-- ---------------------------------------------------------------------
-- 교수 : 로그인 없는 독립 참조 엔티티
--   v2: PK를 교번 형식 VARCHAR로 (향후 app_user 서브타입 전환 대비)
--   v2: 예산이 참조하므로 기준정보로 이동
-- ---------------------------------------------------------------------
CREATE TABLE professor (
    professor_id    VARCHAR(20)  PRIMARY KEY,
    professor_name  VARCHAR(50)  NOT NULL,
    affiliation     VARCHAR(100),                    -- 소속
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 예산항목 : 7개 고정 (실제 항목은 seed에서 입력)
-- ---------------------------------------------------------------------
CREATE TABLE budget_item (
    budget_item_id  INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_code       VARCHAR(20)  NOT NULL,
    item_name       VARCHAR(100) NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_budget_item_code UNIQUE (item_code)
);

-- ---------------------------------------------------------------------
-- 지출주체구분 : 산학협력/전공/융합 3종 고정 → 스키마와 함께 입력
-- ---------------------------------------------------------------------
CREATE TABLE expenditure_subject_type (
    subject_type_code VARCHAR(20)  PRIMARY KEY,
    subject_type_name VARCHAR(50)  NOT NULL
);

INSERT INTO expenditure_subject_type (subject_type_code, subject_type_name) VALUES
    ('INDUSTRY_ACADEMIC', '산학협력'),
    ('MAJOR',             '전공'),
    ('CONVERGENCE',       '융합');

-- ---------------------------------------------------------------------
-- 학기 (v2 신규)
--   다른 테이블은 term_id를 저장하지 않고, 날짜가 이 기간 안에 드는지로 학기를 판별
--   term_year는 학년도. 겨울학기(W)는 다음 해 2월까지 이어질 수 있음
--   1년을 1 → S → 2 → W 로 빈틈없이 정의해야 모든 날짜가 매칭됨
--   ex_academic_term_no_overlap : 두 학기 기간이 겹치면 INSERT 거부
-- ---------------------------------------------------------------------
CREATE TABLE academic_term (
    term_id         INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    term_year       SMALLINT     NOT NULL,
    term_code       VARCHAR(2)   NOT NULL,
    start_date      DATE         NOT NULL,
    end_date        DATE         NOT NULL,

    CONSTRAINT uq_academic_term_year_code UNIQUE (term_year, term_code),
    CONSTRAINT ck_academic_term_code      CHECK (term_code IN ('1', 'S', '2', 'W')),
    CONSTRAINT ck_academic_term_period    CHECK (end_date >= start_date),
    CONSTRAINT ex_academic_term_no_overlap
        EXCLUDE USING gist ((daterange(start_date, end_date, '[]')) WITH &&)
);

COMMENT ON TABLE academic_term IS '학기 기간 정의. 학기는 날짜 범위 매칭으로 계산 (1차 확정 사항 유지)';

-- ---------------------------------------------------------------------
-- 프로그램유형 (v2 신규) : 1차 program_category 자유 입력을 코드화
-- ---------------------------------------------------------------------
CREATE TABLE program_type (
    program_type_code VARCHAR(20)  PRIMARY KEY,
    program_type_name VARCHAR(50)  NOT NULL,
    is_active         BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 문항분류 (v2 신규) : 조사가 달라도 같은 축으로 문항을 비교
-- ---------------------------------------------------------------------
CREATE TABLE survey_question_category (
    category_code   VARCHAR(20)  PRIMARY KEY,
    category_name   VARCHAR(50)  NOT NULL,
    description     VARCHAR(200),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);
