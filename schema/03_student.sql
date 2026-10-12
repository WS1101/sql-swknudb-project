-- =====================================================================
-- 03_student.sql : 학생 인적사항
-- 담당: 서우진
-- 참조: app_user, department
-- 생성 순서: student → student_info_change_request
-- =====================================================================

-- ---------------------------------------------------------------------
-- 학생 (app_user의 서브타입, 1:1)
--   user_type을 'STUDENT'로 고정하고 (student_no, user_type) 복합 FK로
--   ADMIN 유형 사용자가 student 행을 가질 수 없도록 DB 차원에서 강제
--   성명은 app_user.user_name 사용 (중복 저장 안 함)
--   소속대학·캠퍼스는 department를 통해 조회
-- ---------------------------------------------------------------------
CREATE TABLE student (
    student_no          VARCHAR(20)  PRIMARY KEY,
    user_type           VARCHAR(10)  NOT NULL DEFAULT 'STUDENT',
    dept_code           VARCHAR(10)  NOT NULL,
    grade               SMALLINT     NOT NULL,
    enrollment_status   VARCHAR(10)  NOT NULL,           -- 학적상태
    status_change_type  VARCHAR(20),                     -- 학적변동 (휴학, 복학 등)
    status_change_date  DATE,                            -- 학적변동일자
    admission_type      VARCHAR(10)  NOT NULL,           -- 입학구분
    admission_date      DATE         NOT NULL,
    phone_number        VARCHAR(20),                     -- PII: 암호화 미구현 (README 참고)
    sms_opt_in          BOOLEAN      NOT NULL DEFAULT TRUE,
    email               VARCHAR(100),                    -- PII: 암호화 미구현 (README 참고)
    cumulative_mileage  INT          NOT NULL DEFAULT 0, -- 캐시값, 승인 트랜잭션에서 갱신

    CONSTRAINT ck_student_user_type CHECK (user_type = 'STUDENT'),
    -- 초과학기 학생도 학년은 4로 유지
    CONSTRAINT ck_student_grade CHECK (grade BETWEEN 1 AND 4),
    CONSTRAINT ck_student_enrollment_status CHECK (enrollment_status IN
        ('ENROLLED', 'ON_LEAVE', 'GRADUATED', 'WITHDRAWN')),   -- 재학/휴학/졸업/제적·자퇴
    CONSTRAINT ck_student_admission_type CHECK (admission_type IN ('NEW', 'TRANSFER')),
    -- 학적변동 구분과 일자는 둘 다 있거나 둘 다 없어야 함
    CONSTRAINT ck_student_status_change_pair CHECK
        ((status_change_type IS NULL) = (status_change_date IS NULL)),
    CONSTRAINT ck_student_email CHECK (email IS NULL OR email LIKE '%_@_%'),
    CONSTRAINT ck_student_cumulative_mileage CHECK (cumulative_mileage >= 0),

    CONSTRAINT fk_student_app_user FOREIGN KEY (student_no, user_type)
        REFERENCES app_user (user_id, user_type),
    CONSTRAINT fk_student_department FOREIGN KEY (dept_code)
        REFERENCES department (dept_code)
);

-- PostgreSQL은 FK 컬럼에 인덱스를 자동으로 만들지 않음 → 조회·JOIN용으로 직접 생성
CREATE INDEX ix_student_dept_code ON student (dept_code);

-- ---------------------------------------------------------------------
-- 학생정보 변경 요청
--   승인 전 값은 student에 반영하지 않고 여기에만 저장 (DR-3-02)
--   학생이 요청할 수 있는 항목은 연락처 관련으로 제한
--   (학적·학년 등은 관리자가 직접 변경하는 항목)
-- ---------------------------------------------------------------------
CREATE TABLE student_info_change_request (
    request_id      BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_no      VARCHAR(20)  NOT NULL,
    field_name      VARCHAR(30)  NOT NULL,
    old_value       VARCHAR(200),
    new_value       VARCHAR(200) NOT NULL,
    requested_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    status          VARCHAR(10)  NOT NULL DEFAULT 'PENDING',
    processed_by    VARCHAR(20),
    processed_at    TIMESTAMPTZ,
    comment         VARCHAR(200),                        -- 처리의견 (반려 사유 등)

    CONSTRAINT ck_sicr_field_name CHECK (field_name IN ('phone_number', 'email', 'sms_opt_in')),
    CONSTRAINT ck_sicr_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    -- 대기 중이면 처리자·처리일시가 없고, 처리됐으면 둘 다 있어야 함
    CONSTRAINT ck_sicr_processed CHECK (
        (status = 'PENDING' AND processed_by IS NULL AND processed_at IS NULL)
     OR (status <> 'PENDING' AND processed_by IS NOT NULL AND processed_at IS NOT NULL)
    ),

    CONSTRAINT fk_sicr_student      FOREIGN KEY (student_no)   REFERENCES student (student_no),
    CONSTRAINT fk_sicr_processed_by FOREIGN KEY (processed_by) REFERENCES app_user (user_id)
);

CREATE INDEX ix_sicr_student_no ON student_info_change_request (student_no);

-- 같은 학생이 같은 항목에 대해 대기 중인 요청을 두 건 이상 가질 수 없음
-- (처리 완료된 요청은 여러 건 있어도 됨 → 부분 UNIQUE 인덱스)
CREATE UNIQUE INDEX uq_sicr_one_pending
    ON student_info_change_request (student_no, field_name)
    WHERE status = 'PENDING';
