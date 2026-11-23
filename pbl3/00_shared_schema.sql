\encoding UTF8
\set ON_ERROR_STOP on
-- PBL3 공통 분석용 확장 테이블. 기존 public 테이블은 수정하지 않는다.
BEGIN;
CREATE SCHEMA IF NOT EXISTS pbl3;

CREATE TABLE IF NOT EXISTS pbl3.program_session (
    session_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    program_id       INT NOT NULL REFERENCES public.program(program_id),
    session_no       SMALLINT NOT NULL CHECK (session_no BETWEEN 1 AND 20),
    session_date     DATE NOT NULL,
    start_time       TIME NOT NULL,
    end_time         TIME NOT NULL,
    campus_code      VARCHAR(10) REFERENCES public.campus(campus_code),
    location_name    VARCHAR(80) NOT NULL,
    series_code      VARCHAR(40) NOT NULL,
    delivery_mode    VARCHAR(10) NOT NULL DEFAULT 'OFFLINE'
                     CHECK (delivery_mode IN ('OFFLINE', 'ONLINE')),
    data_source      VARCHAR(30) NOT NULL DEFAULT 'PBL3_SYNTHETIC',
    CONSTRAINT uq_pbl3_program_session UNIQUE (program_id, session_no),
    CONSTRAINT ck_pbl3_session_time CHECK (end_time > start_time)
);

CREATE TABLE IF NOT EXISTS pbl3.program_participant (
    session_id       INT NOT NULL REFERENCES pbl3.program_session(session_id),
    student_no       VARCHAR(20) NOT NULL REFERENCES public.student(student_no),
    attendance_status VARCHAR(12) NOT NULL
                       CHECK (attendance_status IN ('ATTENDED','NO_SHOW','CANCELLED','REGISTERED')),
    registered_at    TIMESTAMPTZ NOT NULL,
    attended_at      TIMESTAMPTZ,
    data_source      VARCHAR(30) NOT NULL DEFAULT 'PBL3_SYNTHETIC',
    CONSTRAINT pk_pbl3_program_participant PRIMARY KEY (session_id, student_no),
    CONSTRAINT ck_pbl3_attended_at CHECK
        ((attendance_status = 'ATTENDED') = (attended_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_pbl3_participant_student
    ON pbl3.program_participant (student_no, attendance_status);

-- 가상 시간표: 개인별 실제 수강 내역이 아닌 학과·학년 그룹 대표 시간표.
CREATE TABLE IF NOT EXISTS pbl3.course_timetable (
    course_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dept_code        VARCHAR(10) NOT NULL REFERENCES public.department(dept_code),
    grade            SMALLINT NOT NULL CHECK (grade BETWEEN 1 AND 4),
    weekday_iso      SMALLINT NOT NULL CHECK (weekday_iso BETWEEN 1 AND 7),
    start_time       TIME NOT NULL,
    end_time         TIME NOT NULL,
    term_start       DATE NOT NULL,
    term_end         DATE NOT NULL,
    course_label     VARCHAR(80) NOT NULL,
    data_source      VARCHAR(30) NOT NULL DEFAULT 'PBL3_SYNTHETIC',
    CONSTRAINT ck_pbl3_course_time CHECK (end_time > start_time),
    CONSTRAINT ck_pbl3_course_term CHECK (term_end >= term_start),
    CONSTRAINT uq_pbl3_course_slot UNIQUE
      (dept_code, grade, weekday_iso, start_time, term_start)
);
CREATE INDEX IF NOT EXISTS ix_pbl3_course_match
    ON pbl3.course_timetable(dept_code, grade, weekday_iso, term_start, term_end);

CREATE TABLE IF NOT EXISTS pbl3.academic_event (
    event_id         INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_name       VARCHAR(80) NOT NULL,
    event_type       VARCHAR(20) NOT NULL CHECK (event_type IN ('MIDTERM','FINAL','OTHER')),
    start_date       DATE NOT NULL,
    end_date         DATE NOT NULL,
    data_source      VARCHAR(30) NOT NULL DEFAULT 'PBL3_SYNTHETIC',
    CONSTRAINT ck_pbl3_event_period CHECK (end_date >= start_date),
    CONSTRAINT uq_pbl3_event UNIQUE(event_name, start_date)
);
COMMIT;
