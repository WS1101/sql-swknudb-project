\encoding UTF8
-- 04_topcit.sql : TOPCIT 회차, 점수, TOPCIT 마일리지 기준
-- 담당: 김건희
-- 생성 순서: topcit_exam_round -> topcit_score -> 스냅샷 트리거
--            -> topcit_mileage_criteria
-- TOPCIT 관리 기준
--   - 학생별 TOPCIT 점수는 시험 회차별 이력으로 관리한다.
--   - 동일 학생의 동일 시험 회차 중복 등록을 방지한다.
--   - 회차별/학과별/학년별 평균, 학생별 점수 변화를 조회할 수 있어야 한다.
--   - 유효 점수 범위는 채택한 기준과 근거를 명시한다.
-- 총점 범위
--   TOPCIT 공식 평가체계의 총점 1,000점을 기준으로 0~1000점을 허용한다.

-- TOPCIT 시험 회차
CREATE TABLE topcit_exam_round (
    round_id        INT          GENERATED ALWAYS AS IDENTITY,
    round_name      VARCHAR(30)  NOT NULL,
    exam_date       DATE         NOT NULL,

    CONSTRAINT pk_topcit_exam_round PRIMARY KEY (round_id),
    CONSTRAINT uq_topcit_exam_round_name UNIQUE (round_name)
);

COMMENT ON TABLE topcit_exam_round IS 'TOPCIT 시험 회차';
COMMENT ON COLUMN topcit_exam_round.round_id IS '시험 회차 ID';
COMMENT ON COLUMN topcit_exam_round.round_name IS '시험 회차명';
COMMENT ON COLUMN topcit_exam_round.exam_date IS '시험 일자';

-- 학생별 TOPCIT 점수 이력
--   점수는 student에 단일 컬럼으로 저장하지 않고 회차별 이력으로 관리한다.
--   grade_at_exam, dept_code_at_exam은 응시 당시 기준의 학년/학과 스냅샷이다.
--   INSERT 시 값을 생략하면 트리거가 student의 현재 값으로 채운다.
CREATE TABLE topcit_score (
    score_id          BIGINT       GENERATED ALWAYS AS IDENTITY,
    student_no        VARCHAR(20)  NOT NULL,
    round_id          INT          NOT NULL,
    total_score       INT          NOT NULL,
    grade_at_exam     SMALLINT     NOT NULL,
    dept_code_at_exam VARCHAR(10)  NOT NULL,
    created_by        VARCHAR(20)  NOT NULL,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by        VARCHAR(20),
    updated_at        TIMESTAMPTZ,
    note              VARCHAR(200),

    CONSTRAINT pk_topcit_score PRIMARY KEY (score_id),
    CONSTRAINT uq_topcit_score_student_round UNIQUE (student_no, round_id),
    CONSTRAINT ck_topcit_score_total_score CHECK (total_score BETWEEN 0 AND 1000),
    CONSTRAINT ck_topcit_score_grade_at_exam CHECK (grade_at_exam BETWEEN 1 AND 4),
    -- 수정자와 수정일시는 둘 다 있거나 둘 다 없어야 함
    CONSTRAINT ck_topcit_score_updated_pair CHECK ((updated_by IS NULL) = (updated_at IS NULL)),
    CONSTRAINT fk_topcit_score_student FOREIGN KEY (student_no) REFERENCES student (student_no),
    CONSTRAINT fk_topcit_score_topcit_exam_round FOREIGN KEY (round_id) REFERENCES topcit_exam_round (round_id),
    CONSTRAINT fk_topcit_score_department FOREIGN KEY (dept_code_at_exam) REFERENCES department (dept_code),
    CONSTRAINT fk_topcit_score_created_by_app_user FOREIGN KEY (created_by) REFERENCES app_user (user_id),
    CONSTRAINT fk_topcit_score_updated_by_app_user FOREIGN KEY (updated_by) REFERENCES app_user (user_id)
);

-- student_no 단독 인덱스는 만들지 않음:
--   uq_topcit_score_student_round (student_no, round_id) 인덱스가 student_no로 시작하므로 대신 사용됨
CREATE INDEX ix_topcit_score_round_id ON topcit_score (round_id);
CREATE INDEX ix_topcit_score_dept_code_at_exam_grade_at_exam
    ON topcit_score (dept_code_at_exam, grade_at_exam);

COMMENT ON TABLE topcit_score IS '학생별 TOPCIT 회차별 점수 이력';
COMMENT ON COLUMN topcit_score.score_id IS '점수 ID';
COMMENT ON COLUMN topcit_score.student_no IS '학생 학번';
COMMENT ON COLUMN topcit_score.round_id IS 'TOPCIT 시험 회차 ID';
COMMENT ON COLUMN topcit_score.total_score IS 'TOPCIT 총점(0~1000)';
COMMENT ON COLUMN topcit_score.grade_at_exam IS '응시 당시 학년 (생략 시 트리거가 입력)';
COMMENT ON COLUMN topcit_score.dept_code_at_exam IS '응시 당시 학과 코드 (생략 시 트리거가 입력)';
COMMENT ON COLUMN topcit_score.created_by IS '등록자';
COMMENT ON COLUMN topcit_score.created_at IS '등록일시';
COMMENT ON COLUMN topcit_score.updated_by IS '최종 수정자';
COMMENT ON COLUMN topcit_score.updated_at IS '최종 수정일시';
COMMENT ON COLUMN topcit_score.note IS '비고';

-- 스냅샷 자동 입력 트리거
--   INSERT 시 grade_at_exam / dept_code_at_exam이 비어 있으면 student 현재 값으로 채운다.
--   값을 직접 넣으면 그대로 둔다 (과거 회차 데이터 입력용).
--   NOT NULL 검사는 BEFORE 트리거 이후에 일어나므로 생략해도 에러가 나지 않는다.
CREATE OR REPLACE FUNCTION fn_topcit_score_fill_snapshot()
RETURNS trigger AS $$
BEGIN
    IF NEW.grade_at_exam IS NULL OR NEW.dept_code_at_exam IS NULL THEN
        SELECT COALESCE(NEW.grade_at_exam, s.grade),
               COALESCE(NEW.dept_code_at_exam, s.dept_code)
          INTO NEW.grade_at_exam, NEW.dept_code_at_exam
          FROM student s
         WHERE s.student_no = NEW.student_no;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_topcit_score_fill_snapshot
    BEFORE INSERT ON topcit_score
    FOR EACH ROW EXECUTE FUNCTION fn_topcit_score_fill_snapshot();

-- TOPCIT 점수별 마일리지 부여 기준
--   구간은 [min_score, max_score) : 최소 포함, 최대 미포함 (1차 설계 확정)
--   예) 0~150:30, 150~250:50 → 150점은 두 번째 구간
--   max_score가 NULL이면 상한 없음 (예: 500점 이상)
--   점수 구간이 겹치면 지급 기준이 모호해지므로 EXCLUDE 제약으로 차단한다.
--   조회: int4range(min_score, max_score, '[)') @> 점수
CREATE TABLE topcit_mileage_criteria (
    criteria_id      INT  GENERATED ALWAYS AS IDENTITY,
    min_score        INT  NOT NULL,
    max_score        INT,
    mileage_awarded  INT  NOT NULL,

    CONSTRAINT pk_topcit_mileage_criteria PRIMARY KEY (criteria_id),
    CONSTRAINT ck_topcit_mileage_criteria_score_range CHECK (
        min_score BETWEEN 0 AND 1000
        AND (max_score IS NULL OR (max_score <= 1000 AND min_score < max_score))
    ),
    CONSTRAINT ck_topcit_mileage_criteria_mileage_awarded CHECK (mileage_awarded >= 0),
    CONSTRAINT ex_topcit_mileage_criteria_score_overlap
        EXCLUDE USING gist (int4range(min_score, max_score, '[)') WITH &&)
);

COMMENT ON TABLE topcit_mileage_criteria IS 'TOPCIT 점수 구간별 마일리지 부여 기준';
COMMENT ON COLUMN topcit_mileage_criteria.criteria_id IS '마일리지 기준 ID';
COMMENT ON COLUMN topcit_mileage_criteria.min_score IS '최소 점수 (포함)';
COMMENT ON COLUMN topcit_mileage_criteria.max_score IS '최대 점수 (미포함, NULL = 상한 없음)';
COMMENT ON COLUMN topcit_mileage_criteria.mileage_awarded IS '부여 마일리지';
