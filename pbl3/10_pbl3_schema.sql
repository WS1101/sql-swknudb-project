\encoding UTF8
\set ON_ERROR_STOP on
-- 10_pbl3_schema.sql : PBL3 분석용 가상 세계(pbl3) + 정답지(pbl3_truth)
-- 담당: 서우진
--
-- 설계 원칙
--   1. public(미션2)에 의존하지 않는 독립 스키마. reset.sql이 public을 지워도 영향 없음.
--   2. 테이블·컬럼 이름은 public과 같게 맞춘다 → 다음 과제에서 public으로 merge할 때
--      그대로 옮길 수 있다. public에 없는 컬럼은 "확장" 주석으로 표시.
--   3. 생성기에 심어둔 정답(잠재 변수·효과 계수)은 pbl3_truth에만 둔다.
--      분석·모델은 pbl3만 읽고, pbl3_truth는 "모델이 정답을 얼마나 복원했는지" 채점할 때만 쓴다.
--   4. 재실행 시 두 스키마를 통째로 지우고 다시 만든다 (IF NOT EXISTS로 FK가 빠진 채 남는 문제 방지).

DROP SCHEMA IF EXISTS pbl3_truth CASCADE;
DROP SCHEMA IF EXISTS pbl3 CASCADE;
CREATE SCHEMA pbl3;
CREATE SCHEMA pbl3_truth;

COMMENT ON SCHEMA pbl3       IS 'PBL3 분석용 가상 데이터. public과 같은 구조, 추후 public으로 merge';
COMMENT ON SCHEMA pbl3_truth IS 'PBL3 생성기 정답지(잠재 변수·효과 계수). 모델 학습에 사용 금지, 채점용';

SET search_path = pbl3, public;

-- =====================================================================
-- 기준정보
-- =====================================================================
CREATE TABLE pbl3.campus (
    campus_code  VARCHAR(10)  PRIMARY KEY,
    campus_name  VARCHAR(100) NOT NULL
);

CREATE TABLE pbl3.department (
    dept_code    VARCHAR(10)  PRIMARY KEY,
    dept_name    VARCHAR(100) NOT NULL,
    campus_code  VARCHAR(10)  NOT NULL,
    track_type   CHAR(3)      NOT NULL,
    CONSTRAINT ck_p3_department_track CHECK (track_type IN ('ENG', 'DAI')),
    CONSTRAINT fk_p3_department_campus FOREIGN KEY (campus_code) REFERENCES pbl3.campus (campus_code)
);
CREATE INDEX ix_p3_department_campus ON pbl3.department (campus_code);

-- 학기: public.academic_term과 동일. 1 → S → 2 → W 로 빈틈없이 정의
CREATE TABLE pbl3.academic_term (
    term_id     INT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    term_year   SMALLINT   NOT NULL,
    term_code   VARCHAR(2) NOT NULL,
    start_date  DATE       NOT NULL,
    end_date    DATE       NOT NULL,
    CONSTRAINT uq_p3_term_year_code UNIQUE (term_year, term_code),
    CONSTRAINT ck_p3_term_code CHECK (term_code IN ('1', 'S', '2', 'W')),
    CONSTRAINT ck_p3_term_period CHECK (end_date >= start_date),
    CONSTRAINT ex_p3_term_no_overlap EXCLUDE USING gist (daterange(start_date, end_date, '[]') WITH &&)
);

-- 시험기간 (확장)
CREATE TABLE pbl3.academic_event (
    event_id    INT         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_name  VARCHAR(80) NOT NULL,
    event_type  VARCHAR(20) NOT NULL,
    start_date  DATE        NOT NULL,
    end_date    DATE        NOT NULL,
    CONSTRAINT uq_p3_event UNIQUE (event_name),
    CONSTRAINT ck_p3_event_type CHECK (event_type IN ('MIDTERM', 'FINAL', 'OTHER')),
    CONSTRAINT ck_p3_event_period CHECK (end_date >= start_date)
);

CREATE TABLE pbl3.program_type (
    program_type_code VARCHAR(20) PRIMARY KEY,
    program_type_name VARCHAR(50) NOT NULL
);

CREATE TABLE pbl3.survey_question_category (
    category_code VARCHAR(20)  PRIMARY KEY,
    category_name VARCHAR(50)  NOT NULL,
    description   VARCHAR(200)
);

CREATE TABLE pbl3.budget_item (
    item_code VARCHAR(20)  PRIMARY KEY,
    item_name VARCHAR(100) NOT NULL
);

-- =====================================================================
-- 학생
-- =====================================================================
-- public.student와 같은 컬럼 (연락처·이메일·누적마일리지 제외).
-- grade는 기준일(generation_meta.as_of_date) 기준 학년. 과거 시점 학년은 fn_grade_at으로 계산.
CREATE TABLE pbl3.student (
    student_no          VARCHAR(20) PRIMARY KEY,
    dept_code           VARCHAR(10) NOT NULL,
    grade               SMALLINT,                    -- 졸업생은 NULL
    enrollment_status   VARCHAR(10) NOT NULL,
    status_change_type  VARCHAR(20),
    status_change_date  DATE,
    admission_type      VARCHAR(10) NOT NULL,
    admission_date      DATE        NOT NULL,
    sms_opt_in          BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_p3_student_grade CHECK (grade IS NULL OR grade BETWEEN 1 AND 4),
    CONSTRAINT ck_p3_student_status CHECK (enrollment_status IN ('ENROLLED', 'ON_LEAVE', 'GRADUATED', 'WITHDRAWN')),
    CONSTRAINT ck_p3_student_admission CHECK (admission_type IN ('NEW', 'TRANSFER')),
    CONSTRAINT ck_p3_student_change_pair CHECK ((status_change_type IS NULL) = (status_change_date IS NULL)),
    CONSTRAINT fk_p3_student_department FOREIGN KEY (dept_code) REFERENCES pbl3.department (dept_code)
);
CREATE INDEX ix_p3_student_dept ON pbl3.student (dept_code);

-- SMS 수신 변경 이력 (public.student_info_change_request와 같은 구조, 승인된 건만 생성)
CREATE TABLE pbl3.student_info_change_request (
    request_id    BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_no    VARCHAR(20)  NOT NULL,
    field_name    VARCHAR(30)  NOT NULL,
    old_value     VARCHAR(200),
    new_value     VARCHAR(200) NOT NULL,
    requested_at  TIMESTAMPTZ  NOT NULL,
    status        VARCHAR(10)  NOT NULL,
    processed_at  TIMESTAMPTZ,
    CONSTRAINT ck_p3_sicr_field CHECK (field_name IN ('phone_number', 'email', 'sms_opt_in')),
    CONSTRAINT ck_p3_sicr_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    CONSTRAINT fk_p3_sicr_student FOREIGN KEY (student_no) REFERENCES pbl3.student (student_no)
);
CREATE INDEX ix_p3_sicr_student ON pbl3.student_info_change_request (student_no);

-- 학과·학년·학기별 전공 수업 시간표 (확장). 개인 시간표가 아닌 교육과정 공개 정보 수준
CREATE TABLE pbl3.course_timetable (
    course_id    INT         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dept_code    VARCHAR(10) NOT NULL,
    grade        SMALLINT    NOT NULL,
    term_id      INT         NOT NULL,
    weekday_iso  SMALLINT    NOT NULL,
    start_time   TIME        NOT NULL,
    end_time     TIME        NOT NULL,
    course_label VARCHAR(80) NOT NULL,
    CONSTRAINT uq_p3_course_slot UNIQUE (dept_code, grade, term_id, weekday_iso, start_time),
    CONSTRAINT ck_p3_course_grade CHECK (grade BETWEEN 1 AND 4),
    CONSTRAINT ck_p3_course_weekday CHECK (weekday_iso BETWEEN 1 AND 7),
    CONSTRAINT ck_p3_course_time CHECK (end_time > start_time),
    CONSTRAINT fk_p3_course_dept FOREIGN KEY (dept_code) REFERENCES pbl3.department (dept_code),
    CONSTRAINT fk_p3_course_term FOREIGN KEY (term_id) REFERENCES pbl3.academic_term (term_id)
);
CREATE INDEX ix_p3_course_term ON pbl3.course_timetable (term_id);

-- =====================================================================
-- 프로그램·회차·참여
-- =====================================================================
-- program = 하나의 시리즈. 회차는 program_session
CREATE TABLE pbl3.program (
    program_id        INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    program_type_code VARCHAR(20)  NOT NULL,
    program_name      VARCHAR(100) NOT NULL,
    program_date      DATE         NOT NULL,          -- public과 같은 의미: 대표 일자(1회차)
    organizer         VARCHAR(50),
    capacity          INT,
    series_key        VARCHAR(40)  NOT NULL,          -- 확장: 해마다 반복되는 같은 프로그램 묶음
    CONSTRAINT uq_p3_program_name UNIQUE (program_name),
    CONSTRAINT ck_p3_program_capacity CHECK (capacity IS NULL OR capacity > 0),
    CONSTRAINT fk_p3_program_type FOREIGN KEY (program_type_code) REFERENCES pbl3.program_type (program_type_code)
);
CREATE INDEX ix_p3_program_type ON pbl3.program (program_type_code);

CREATE TABLE pbl3.mileage_criteria (
    program_id            INT NOT NULL PRIMARY KEY,
    participation_mileage INT,
    award_mileage         INT,
    CONSTRAINT ck_p3_mc_value CHECK (participation_mileage IS NOT NULL OR award_mileage IS NOT NULL),
    CONSTRAINT fk_p3_mc_program FOREIGN KEY (program_id) REFERENCES pbl3.program (program_id)
);

CREATE TABLE pbl3.program_session (
    session_id     INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    program_id     INT          NOT NULL,
    session_no     SMALLINT     NOT NULL,
    session_date   DATE         NOT NULL,
    start_time     TIME         NOT NULL,
    end_time       TIME         NOT NULL,
    campus_code    VARCHAR(10),                       -- 온라인이면 NULL
    location_name  VARCHAR(80)  NOT NULL,
    delivery_mode  VARCHAR(10)  NOT NULL,
    session_status VARCHAR(10)  NOT NULL,             -- 기준일 이후 회차는 SCHEDULED (예측 대상)
    CONSTRAINT uq_p3_session UNIQUE (program_id, session_no),
    CONSTRAINT ck_p3_session_no CHECK (session_no >= 1),
    CONSTRAINT ck_p3_session_time CHECK (end_time > start_time),
    CONSTRAINT ck_p3_session_mode CHECK (delivery_mode IN ('OFFLINE', 'ONLINE')),
    CONSTRAINT ck_p3_session_campus CHECK ((delivery_mode = 'ONLINE') = (campus_code IS NULL)),
    CONSTRAINT ck_p3_session_status CHECK (session_status IN ('COMPLETED', 'SCHEDULED')),
    CONSTRAINT fk_p3_session_program FOREIGN KEY (program_id) REFERENCES pbl3.program (program_id),
    CONSTRAINT fk_p3_session_campus FOREIGN KEY (campus_code) REFERENCES pbl3.campus (campus_code)
);
CREATE INDEX ix_p3_session_date ON pbl3.program_session (session_date);

CREATE TABLE pbl3.program_participant (
    session_id        INT         NOT NULL,
    student_no        VARCHAR(20) NOT NULL,
    attendance_status VARCHAR(12) NOT NULL,
    registered_at     TIMESTAMPTZ NOT NULL,
    attended_at       TIMESTAMPTZ,
    CONSTRAINT pk_p3_participant PRIMARY KEY (session_id, student_no),
    CONSTRAINT ck_p3_participant_status CHECK (attendance_status IN ('REGISTERED', 'ATTENDED', 'NO_SHOW', 'CANCELLED')),
    CONSTRAINT ck_p3_participant_attended CHECK ((attendance_status = 'ATTENDED') = (attended_at IS NOT NULL)),
    CONSTRAINT fk_p3_participant_session FOREIGN KEY (session_id) REFERENCES pbl3.program_session (session_id),
    CONSTRAINT fk_p3_participant_student FOREIGN KEY (student_no) REFERENCES pbl3.student (student_no)
);
CREATE INDEX ix_p3_participant_student ON pbl3.program_participant (student_no, attendance_status);

-- =====================================================================
-- 만족도 (public 구조와 동일, 조사가 회차 단위라는 점만 확장)
-- =====================================================================
CREATE TABLE pbl3.survey (
    survey_id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    program_id  INT          NOT NULL,
    session_id  INT          NOT NULL,                -- 확장: 회차별 조사
    survey_name VARCHAR(100) NOT NULL,
    start_date  DATE         NOT NULL,
    end_date    DATE         NOT NULL,
    status      VARCHAR(10)  NOT NULL,
    CONSTRAINT uq_p3_survey_session UNIQUE (session_id),
    CONSTRAINT ck_p3_survey_period CHECK (end_date >= start_date),
    CONSTRAINT ck_p3_survey_status CHECK (status IN ('DRAFT', 'OPEN', 'CLOSED')),
    CONSTRAINT fk_p3_survey_program FOREIGN KEY (program_id) REFERENCES pbl3.program (program_id),
    CONSTRAINT fk_p3_survey_session FOREIGN KEY (session_id) REFERENCES pbl3.program_session (session_id)
);
CREATE INDEX ix_p3_survey_program ON pbl3.survey (program_id);

CREATE TABLE pbl3.survey_question (
    question_id   INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    survey_id     INT          NOT NULL,
    category_code VARCHAR(20)  NOT NULL,
    display_order SMALLINT     NOT NULL,
    question_text VARCHAR(200) NOT NULL,
    question_type VARCHAR(15)  NOT NULL,
    scale_max     SMALLINT,
    CONSTRAINT uq_p3_question_order UNIQUE (survey_id, display_order),
    CONSTRAINT ck_p3_question_type CHECK (question_type IN ('SCALE', 'TEXT')),
    CONSTRAINT ck_p3_question_scale CHECK ((question_type = 'SCALE' AND scale_max = 5)
                                        OR (question_type = 'TEXT' AND scale_max IS NULL)),
    CONSTRAINT fk_p3_question_survey FOREIGN KEY (survey_id) REFERENCES pbl3.survey (survey_id),
    CONSTRAINT fk_p3_question_category FOREIGN KEY (category_code) REFERENCES pbl3.survey_question_category (category_code)
);
CREATE INDEX ix_p3_question_category ON pbl3.survey_question (category_code);

CREATE TABLE pbl3.survey_response (
    response_id           BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    survey_id             INT         NOT NULL,
    student_no            VARCHAR(20) NOT NULL,
    grade_at_response     SMALLINT    NOT NULL,
    dept_code_at_response VARCHAR(10) NOT NULL,
    responded_at          TIMESTAMPTZ NOT NULL,
    is_completed          BOOLEAN     NOT NULL,
    CONSTRAINT uq_p3_response UNIQUE (survey_id, student_no),
    CONSTRAINT ck_p3_response_grade CHECK (grade_at_response BETWEEN 1 AND 4),
    CONSTRAINT fk_p3_response_survey FOREIGN KEY (survey_id) REFERENCES pbl3.survey (survey_id),
    CONSTRAINT fk_p3_response_student FOREIGN KEY (student_no) REFERENCES pbl3.student (student_no),
    CONSTRAINT fk_p3_response_dept FOREIGN KEY (dept_code_at_response) REFERENCES pbl3.department (dept_code)
);
CREATE INDEX ix_p3_response_student ON pbl3.survey_response (student_no);

CREATE TABLE pbl3.survey_response_detail (
    response_id BIGINT       NOT NULL,
    question_id INT          NOT NULL,
    score       SMALLINT,
    text_answer VARCHAR(500),
    CONSTRAINT pk_p3_detail PRIMARY KEY (response_id, question_id),
    CONSTRAINT ck_p3_detail_score CHECK (score IS NULL OR score BETWEEN 1 AND 5),
    CONSTRAINT ck_p3_detail_answer CHECK ((score IS NOT NULL AND text_answer IS NULL)
                                       OR (score IS NULL AND text_answer IS NOT NULL)),
    CONSTRAINT fk_p3_detail_response FOREIGN KEY (response_id) REFERENCES pbl3.survey_response (response_id),
    CONSTRAINT fk_p3_detail_question FOREIGN KEY (question_id) REFERENCES pbl3.survey_question (question_id)
);
CREATE INDEX ix_p3_detail_question ON pbl3.survey_response_detail (question_id);

-- =====================================================================
-- 지출 (public.expenditure의 프로그램 연관 부분만. session_id는 확장)
-- =====================================================================
CREATE TABLE pbl3.expenditure (
    expenditure_id   BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    program_id       INT          NOT NULL,
    session_id       INT,
    budget_item_code VARCHAR(20)  NOT NULL,
    expenditure_date DATE         NOT NULL,
    amount           BIGINT       NOT NULL,
    description      VARCHAR(200) NOT NULL,
    status           VARCHAR(10)  NOT NULL,
    comment          VARCHAR(200),
    CONSTRAINT ck_p3_exp_amount CHECK (amount > 0),
    CONSTRAINT ck_p3_exp_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT fk_p3_exp_program FOREIGN KEY (program_id) REFERENCES pbl3.program (program_id),
    CONSTRAINT fk_p3_exp_session FOREIGN KEY (session_id) REFERENCES pbl3.program_session (session_id),
    CONSTRAINT fk_p3_exp_item FOREIGN KEY (budget_item_code) REFERENCES pbl3.budget_item (item_code)
);
CREATE INDEX ix_p3_exp_program ON pbl3.expenditure (program_id);
CREATE INDEX ix_p3_exp_session ON pbl3.expenditure (session_id);

-- 생성 메타 (기준일)
CREATE TABLE pbl3.generation_meta (
    as_of_date    DATE        NOT NULL,
    generator_ver VARCHAR(20) NOT NULL,
    generated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- 분석 공통 함수 (분석·모델이 같은 기준으로 계산하도록 한 곳에 둔다)
-- =====================================================================
-- 학년도: 3월 시작
CREATE FUNCTION pbl3.fn_academic_year(p_date DATE) RETURNS INT
LANGUAGE sql IMMUTABLE AS $$
    SELECT EXTRACT(YEAR FROM p_date)::INT - CASE WHEN EXTRACT(MONTH FROM p_date) < 3 THEN 1 ELSE 0 END
$$;

-- 특정 일자의 학년. 재학 범위(1~4) 밖이면 NULL
CREATE FUNCTION pbl3.fn_grade_at(p_admission_date DATE, p_admission_type TEXT, p_date DATE) RETURNS INT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN g BETWEEN 1 AND 4 THEN g END
      FROM (SELECT pbl3.fn_academic_year(p_date) - pbl3.fn_academic_year(p_admission_date) + 1
                   + CASE WHEN p_admission_type = 'TRANSFER' THEN 2 ELSE 0 END AS g) x
     WHERE p_date >= p_admission_date
$$;

-- 회차 시간에 해당 학과·학년의 전공 수업이 겹치는가
CREATE FUNCTION pbl3.fn_class_conflict(p_dept TEXT, p_grade INT, p_date DATE, p_start TIME, p_end TIME)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
          FROM pbl3.course_timetable ct
          JOIN pbl3.academic_term t ON t.term_id = ct.term_id
         WHERE ct.dept_code = p_dept AND ct.grade = p_grade
           AND p_date BETWEEN t.start_date AND t.end_date
           AND ct.weekday_iso = EXTRACT(ISODOW FROM p_date)
           AND p_start < ct.end_time AND p_end > ct.start_time)
$$;

-- 시험기간 전후 3일 포함 여부
CREATE FUNCTION pbl3.fn_near_exam(p_date DATE) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM pbl3.academic_event e
                    WHERE e.event_type IN ('MIDTERM', 'FINAL')
                      AND p_date BETWEEN e.start_date - 3 AND e.end_date + 3)
$$;

-- 정규학기(1·2학기) 수업기간 여부. 아니면 방학
CREATE FUNCTION pbl3.fn_in_semester(p_date DATE) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM pbl3.academic_term t
                    WHERE t.term_code IN ('1', '2') AND p_date BETWEEN t.start_date AND t.end_date)
$$;

-- =====================================================================
-- 정답지 (pbl3_truth)
-- =====================================================================
-- 효과 계수: 한 행짜리 표. 컬럼 하나가 생성기에 심은 효과 하나 (로지스틱 회귀 계수 단위)
CREATE TABLE pbl3_truth.coef (
    -- 신청 확률 logit
    reg_intercept        NUMERIC NOT NULL,
    reg_engagement       NUMERIC NOT NULL,
    reg_class_conflict   NUMERIC NOT NULL,
    reg_near_exam        NUMERIC NOT NULL,
    reg_vacation         NUMERIC NOT NULL,
    reg_session_fatigue  NUMERIC NOT NULL,   -- 회차가 1 늘 때마다
    reg_prev_content     NUMERIC NOT NULL,   -- 직전 회차 평균 내용 만족도(3.5 기준) 1점당 (입소문)
    reg_returning        NUMERIC NOT NULL,   -- 직전 회차 출석자
    ret_content          NUMERIC NOT NULL,   -- 직전 회차 출석자의 실제 내용 만족도(3 기준) 1점당
    ret_instructor       NUMERIC NOT NULL,
    ret_operation        NUMERIC NOT NULL,   -- 운영 만족도는 재참여에 영향 없음 (함정)
    reg_cross_campus     NUMERIC NOT NULL,
    reg_online           NUMERIC NOT NULL,
    reg_friday           NUMERIC NOT NULL,
    reg_saturday         NUMERIC NOT NULL,
    reg_evening          NUMERIC NOT NULL,   -- 18시 이후 시작
    reg_mileage_per_pt   NUMERIC NOT NULL,
    reg_program_appeal   NUMERIC NOT NULL,
    -- 출석 확률 logit (신청자 중)
    att_intercept        NUMERIC NOT NULL,
    att_engagement       NUMERIC NOT NULL,
    att_class_conflict   NUMERIC NOT NULL,
    att_near_exam        NUMERIC NOT NULL,
    att_online           NUMERIC NOT NULL,
    att_cross_campus     NUMERIC NOT NULL,
    att_evening          NUMERIC NOT NULL,
    cancel_rate          NUMERIC NOT NULL,   -- 신청자 중 사전 취소 비율
    -- 만족도 (실제 만족도 = 평균 + 품질 효과 + 성향 효과 + 개인 잡음)
    sat_mean_content     NUMERIC NOT NULL,
    sat_mean_instructor  NUMERIC NOT NULL,
    sat_mean_operation   NUMERIC NOT NULL,
    sat_mean_facility    NUMERIC NOT NULL,
    sat_mean_schedule    NUMERIC NOT NULL,
    sat_quality_content  NUMERIC NOT NULL,
    sat_quality_instr    NUMERIC NOT NULL,
    sat_quality_oper     NUMERIC NOT NULL,
    sat_engagement       NUMERIC NOT NULL,
    sat_conflict_sched   NUMERIC NOT NULL,   -- 수업이 겹쳤는데 온 학생의 일정 만족도
    sat_noise_sd         NUMERIC NOT NULL,
    straightline_base    NUMERIC NOT NULL,   -- 모든 문항 같은 점수 응답 확률
    straightline_low_eng NUMERIC NOT NULL,   -- 적극성 낮은 학생 추가 확률
    -- 학생 잠재 변수
    eng_transfer_dai     NUMERIC NOT NULL,   -- 신관캠(DAI) 편입생 적극성 (숨겨진 소외 집단)
    eng_fading_drop      NUMERIC NOT NULL,   -- 이탈 학생의 이탈 이후 적극성 감소
    fading_ratio         NUMERIC NOT NULL
);

COMMENT ON TABLE pbl3_truth.coef IS '생성기 효과 계수. 모델 복원 정확도 채점용 정답';

-- 프로그램 유형 × 학년 선호 (logit 가산)
CREATE TABLE pbl3_truth.type_grade_affinity (
    program_type_code VARCHAR(20) NOT NULL,
    grade             SMALLINT    NOT NULL,
    value             NUMERIC     NOT NULL,
    CONSTRAINT pk_p3t_affinity PRIMARY KEY (program_type_code, grade)
);

CREATE TABLE pbl3_truth.student_latent (
    student_no  VARCHAR(20) PRIMARY KEY,
    engagement  NUMERIC     NOT NULL,             -- 표준정규 기반 적극성
    is_fading   BOOLEAN     NOT NULL,
    fade_start  DATE,
    CONSTRAINT fk_p3t_student FOREIGN KEY (student_no) REFERENCES pbl3.student (student_no)
);

CREATE TABLE pbl3_truth.program_latent (
    program_id  INT     PRIMARY KEY,
    quality     NUMERIC NOT NULL,                 -- 내용 품질 (만족도의 원인)
    appeal      NUMERIC NOT NULL,                 -- 홍보·주제 매력 (신청의 원인)
    story       VARCHAR(200),                     -- 시연용으로 의도적으로 심은 상황 설명
    CONSTRAINT fk_p3t_program FOREIGN KEY (program_id) REFERENCES pbl3.program (program_id)
);

-- 출석자의 실제(관측되지 않은) 만족도. 응답 여부와 무관하게 모든 출석자에게 존재
CREATE TABLE pbl3_truth.attendee_satisfaction (
    session_id      INT         NOT NULL,
    student_no      VARCHAR(20) NOT NULL,
    true_content    NUMERIC     NOT NULL,
    true_instructor NUMERIC     NOT NULL,
    true_operation  NUMERIC     NOT NULL,
    true_facility   NUMERIC     NOT NULL,
    true_schedule   NUMERIC     NOT NULL,
    is_straightliner BOOLEAN    NOT NULL,
    CONSTRAINT pk_p3t_sat PRIMARY KEY (session_id, student_no)
);

-- 생성기 내부 난수 (md5 기반, 실행 순서와 무관하게 같은 값)
CREATE FUNCTION pbl3_truth.fn_u(p_key TEXT) RETURNS DOUBLE PRECISION
LANGUAGE sql IMMUTABLE AS $$
    SELECT (('x' || substr(md5(p_key), 1, 8))::bit(32)::bigint + 0.5) / 4294967296.0
$$;

CREATE FUNCTION pbl3_truth.fn_n(p_key TEXT) RETURNS DOUBLE PRECISION
LANGUAGE sql IMMUTABLE AS $$
    SELECT sqrt(-2 * ln(pbl3_truth.fn_u(p_key || '#a'))) * cos(2 * pi() * pbl3_truth.fn_u(p_key || '#b'))
$$;

CREATE FUNCTION pbl3_truth.fn_sigmoid(x DOUBLE PRECISION) RETURNS DOUBLE PRECISION
LANGUAGE sql IMMUTABLE AS $$ SELECT 1.0 / (1.0 + exp(-x)) $$;

-- 분석 계정: pbl3 조회 허용, 정답지는 차단
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analytics_reader') THEN
        CREATE ROLE analytics_reader NOLOGIN;
    END IF;
END $$;
GRANT USAGE ON SCHEMA pbl3 TO analytics_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA pbl3 TO analytics_reader;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pbl3 TO analytics_reader;
REVOKE ALL ON SCHEMA pbl3_truth FROM PUBLIC;
