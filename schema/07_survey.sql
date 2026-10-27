\encoding UTF8
-- 07_survey.sql | 프로그램 만족도 (임영효)
-- 의존성: 02_master(survey_question_category, department), 03_student, 05_mileage(program)
-- 중복 응답 허용. 조회는 학생·조사별 최신 완료 응답만 선택함.

CREATE TABLE survey (
    survey_id     INT GENERATED ALWAYS AS IDENTITY,
    program_id    INT NOT NULL,
    survey_name   VARCHAR(100) NOT NULL,
    start_date    DATE NOT NULL,
    end_date      DATE NOT NULL,
    status        VARCHAR(10) NOT NULL DEFAULT 'DRAFT',
    CONSTRAINT pk_survey PRIMARY KEY (survey_id),
    CONSTRAINT ck_survey_period CHECK (end_date >= start_date),
    CONSTRAINT ck_survey_status CHECK (status IN ('DRAFT', 'OPEN', 'CLOSED')),
    CONSTRAINT fk_survey_program FOREIGN KEY (program_id) REFERENCES program (program_id),
    CONSTRAINT uq_survey_program_name UNIQUE (program_id, survey_name)
);

CREATE TABLE survey_question (
    question_id    INT GENERATED ALWAYS AS IDENTITY,
    survey_id      INT NOT NULL,
    category_code  VARCHAR(20) NOT NULL,
    display_order  SMALLINT NOT NULL,
    question_text  VARCHAR(200) NOT NULL,
    question_type  VARCHAR(15) NOT NULL,
    scale_max      SMALLINT,
    CONSTRAINT pk_survey_question PRIMARY KEY (question_id),
    CONSTRAINT uq_survey_question_order UNIQUE (survey_id, display_order),
    CONSTRAINT ck_survey_question_display_order CHECK (display_order > 0),
    CONSTRAINT ck_survey_question_text CHECK (btrim(question_text) <> ''),
    CONSTRAINT ck_survey_question_type CHECK (question_type IN ('SCALE', 'TEXT')),
    CONSTRAINT ck_survey_question_scale CHECK (
        (question_type = 'SCALE' AND scale_max IS NOT NULL AND scale_max = 5)
        OR (question_type = 'TEXT' AND scale_max IS NULL)
    ),
    CONSTRAINT fk_survey_question_survey FOREIGN KEY (survey_id) REFERENCES survey (survey_id),
    CONSTRAINT fk_survey_question_category FOREIGN KEY (category_code)
        REFERENCES survey_question_category (category_code)
);

CREATE TABLE survey_response (
    response_id           BIGINT GENERATED ALWAYS AS IDENTITY,
    survey_id             INT NOT NULL,
    student_no            VARCHAR(20) NOT NULL,
    grade_at_response     SMALLINT NOT NULL,
    dept_code_at_response VARCHAR(10) NOT NULL,
    responded_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_completed          BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_survey_response PRIMARY KEY (response_id),
    CONSTRAINT ck_survey_response_grade CHECK (grade_at_response BETWEEN 1 AND 4),
    CONSTRAINT fk_survey_response_survey FOREIGN KEY (survey_id) REFERENCES survey (survey_id),
    CONSTRAINT fk_survey_response_student FOREIGN KEY (student_no) REFERENCES student (student_no),
    CONSTRAINT fk_survey_response_department FOREIGN KEY (dept_code_at_response)
        REFERENCES department (dept_code)
);

CREATE TABLE survey_response_detail (
    response_id BIGINT NOT NULL,
    question_id INT NOT NULL,
    score       SMALLINT,
    text_answer VARCHAR(500),
    CONSTRAINT pk_survey_response_detail PRIMARY KEY (response_id, question_id),
    CONSTRAINT ck_survey_detail_score CHECK (score IS NULL OR score BETWEEN 1 AND 5),
    CONSTRAINT ck_survey_detail_answer CHECK (
        (score IS NOT NULL AND text_answer IS NULL)
        OR (score IS NULL AND text_answer IS NOT NULL AND btrim(text_answer) <> '')
    ),
    CONSTRAINT fk_survey_detail_response FOREIGN KEY (response_id)
        REFERENCES survey_response (response_id),
    CONSTRAINT fk_survey_detail_question FOREIGN KEY (question_id)
        REFERENCES survey_question (question_id)
);

CREATE INDEX ix_survey_program ON survey (program_id);
CREATE INDEX ix_survey_question_category ON survey_question (category_code);
CREATE INDEX ix_survey_response_latest ON survey_response
    (survey_id, student_no, responded_at DESC, response_id DESC)
    WHERE is_completed = TRUE;
CREATE INDEX ix_survey_response_dept_grade ON survey_response
    (dept_code_at_response, grade_at_response);
CREATE INDEX ix_survey_detail_question ON survey_response_detail (question_id);

-- TOPCIT와 동일한 방식으로 학생의 응답 시점 학년·학과를 기록한다.
CREATE OR REPLACE FUNCTION fn_survey_response_fill_snapshot()
RETURNS trigger AS $$
BEGIN
    IF NEW.grade_at_response IS NULL OR NEW.dept_code_at_response IS NULL THEN
        SELECT COALESCE(NEW.grade_at_response, s.grade),
               COALESCE(NEW.dept_code_at_response, s.dept_code)
          INTO NEW.grade_at_response, NEW.dept_code_at_response
          FROM student s WHERE s.student_no = NEW.student_no;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_survey_response_fill_snapshot
    BEFORE INSERT ON survey_response
    FOR EACH ROW EXECUTE FUNCTION fn_survey_response_fill_snapshot();

-- 해당 조사 문항에만 답할 수 있고, 문항 유형에 맞는 답을 입력하도록 강제한다.
CREATE OR REPLACE FUNCTION fn_survey_detail_validate()
RETURNS trigger AS $$
DECLARE
    v_response_survey INT;
    v_question_survey INT;
    v_type VARCHAR(15);
    v_max SMALLINT;
    v_completed BOOLEAN;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT is_completed INTO v_completed FROM survey_response WHERE response_id = OLD.response_id;
        IF v_completed THEN
            RAISE EXCEPTION '완료된 만족도 응답의 상세는 삭제할 수 없습니다';
        END IF;
        RETURN OLD;
    END IF;

    SELECT survey_id, is_completed INTO v_response_survey, v_completed
      FROM survey_response WHERE response_id = NEW.response_id;
    SELECT survey_id, question_type, scale_max INTO v_question_survey, v_type, v_max
      FROM survey_question WHERE question_id = NEW.question_id;
    IF v_completed THEN
        RAISE EXCEPTION '완료된 만족도 응답의 상세는 수정할 수 없습니다';
    END IF;
    IF v_response_survey IS NOT NULL AND v_question_survey IS NOT NULL THEN
        IF v_response_survey <> v_question_survey THEN
            RAISE EXCEPTION '응답과 문항은 동일한 조사에 속해야 합니다' USING ERRCODE = '23514';
        END IF;
        IF (v_type = 'SCALE' AND (NEW.score IS NULL OR NEW.text_answer IS NOT NULL OR NEW.score > v_max))
           OR (v_type = 'TEXT' AND (NEW.score IS NOT NULL OR NEW.text_answer IS NULL)) THEN
            RAISE EXCEPTION '문항 유형과 답변 유형이 일치하지 않습니다' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_survey_detail_validate
    BEFORE INSERT OR UPDATE OR DELETE ON survey_response_detail
    FOR EACH ROW EXECUTE FUNCTION fn_survey_detail_validate();

-- 헤더는 미완료로 생성 -> 상세 삽입 -> 완료 처리한다.
-- 문항 전체에 답했을 때만 완료 가능하게 보장한다.
CREATE OR REPLACE FUNCTION fn_survey_response_check_complete()
RETURNS trigger AS $$
DECLARE
    v_expected INT;
    v_answered INT;
BEGIN
    IF NEW.is_completed THEN
        IF TG_OP = 'INSERT' THEN
            RAISE EXCEPTION '응답 상세를 입력한 뒤 완료 처리해야 합니다' USING ERRCODE = '23514';
        END IF;
        SELECT count(*) INTO v_expected FROM survey_question WHERE survey_id = NEW.survey_id;
        SELECT count(*) INTO v_answered FROM survey_response_detail WHERE response_id = NEW.response_id;
        IF v_expected = 0 OR v_answered <> v_expected THEN
            RAISE EXCEPTION '모든 문항에 답한 후 완료할 수 있습니다: % / %', v_answered, v_expected
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_survey_response_check_complete
    BEFORE INSERT OR UPDATE ON survey_response
    FOR EACH ROW EXECUTE FUNCTION fn_survey_response_check_complete();

COMMENT ON TABLE survey IS '프로그램별 만족도 조사. 학기는 program.program_date로 판정';
COMMENT ON TABLE survey_response IS '중복 응답 허용. 통계에서는 학생·조사별 최신 완료 응답을 사용';
COMMENT ON COLUMN survey_response.grade_at_response IS '응답 당시 학년 스냅샷';
COMMENT ON COLUMN survey_response.dept_code_at_response IS '응답 당시 학과 스냅샷';
