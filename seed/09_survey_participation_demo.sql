-- 선택적 합성 시드 전용. 공통 public 참여 테이블은 만들지 않는다.
-- generate_demo --with-participation이 1개 트랜잭션 안에서 실행한다.
DO $$ BEGIN
    IF to_regclass('analytics.survey_participation_setting') IS NULL THEN
        RAISE EXCEPTION '06_survey_participation.sql을 먼저 적용하세요';
    END IF;
    IF EXISTS(SELECT 1 FROM analytics.survey_participation_setting
              WHERE attendance_connected OR opportunity_connected) THEN
        RAISE EXCEPTION '연결된 참여 VIEW를 합성 시드로 덮어쓰지 않습니다. 별도 시연 DB를 사용하세요';
    END IF;
END $$;
CREATE TABLE analytics.survey_demo_attendance (
    student_no VARCHAR(20) NOT NULL REFERENCES public.student(student_no),
    program_id INT NOT NULL REFERENCES public.program(program_id),
    attended_at TIMESTAMPTZ NOT NULL CHECK (isfinite(attended_at)),
    PRIMARY KEY(student_no,program_id)
);
CREATE INDEX ix_survey_demo_attendance_program ON analytics.survey_demo_attendance(program_id);
CREATE TABLE analytics.survey_demo_opportunity (
    student_no VARCHAR(20) NOT NULL REFERENCES public.student(student_no),
    program_id INT NOT NULL REFERENCES public.program(program_id),
    offered_at TIMESTAMPTZ NOT NULL CHECK (isfinite(offered_at)),
    scheduled_at TIMESTAMPTZ NOT NULL CHECK (isfinite(scheduled_at)),
    PRIMARY KEY(student_no,program_id),
    CHECK (offered_at<=scheduled_at)
);
CREATE INDEX ix_survey_demo_opportunity_program ON analytics.survey_demo_opportunity(program_id);
CREATE OR REPLACE VIEW analytics.v_attendance_event AS
SELECT student_no,program_id,attended_at FROM analytics.survey_demo_attendance;
CREATE OR REPLACE VIEW analytics.v_program_opportunity AS
SELECT student_no,program_id,offered_at,scheduled_at FROM analytics.survey_demo_opportunity;
UPDATE analytics.survey_participation_setting SET attendance_connected=TRUE,opportunity_connected=TRUE;
