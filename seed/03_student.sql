-- 승인 결과를 포함한 고정 스냅샷을 삽입한다. 기존 학생에 대한 UPDATE는 수행하지 않는다.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
SELECT pg_advisory_xact_lock(20261015, 3);

DO $$
DECLARE
    ordinal INT;
    seed_student student%ROWTYPE;
    existing_student student%ROWTYPE;
    seed_request RECORD;
    stored_request student_info_change_request%ROWTYPE;
    initial_request JSONB;
    seed_log RECORD;
    v_request_id BIGINT;
BEGIN
    FOR ordinal IN 1..32 LOOP
        seed_student.student_no := (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0');
        seed_student.user_type := 'STUDENT';
        seed_student.dept_code := (ARRAY['SEED_CS', 'SEED_SW', 'SEED_MATH', 'SEED_BIO'])[(ordinal - 1) % 4 + 1];
        seed_student.grade := 4 - (ordinal - 1) / 8;
        seed_student.enrollment_status := CASE WHEN ordinal % 7 = 0 THEN 'ON_LEAVE' ELSE 'ENROLLED' END;
        seed_student.status_change_type := CASE
            WHEN ordinal % 7 = 0 THEN 'LEAVE'
            WHEN ordinal % 11 = 0 THEN 'RETURN'
            ELSE NULL END;
        seed_student.status_change_date := CASE
            WHEN ordinal % 7 = 0 THEN DATE '2026-09-01'
            WHEN ordinal % 11 = 0 THEN DATE '2026-03-02'
            ELSE NULL END;
        seed_student.admission_type := CASE WHEN ordinal IN (8, 16) THEN 'TRANSFER' ELSE 'NEW' END;
        seed_student.admission_date := make_date(
            CASE WHEN ordinal = 8 THEN 2025 WHEN ordinal = 16 THEN 2026
                 ELSE 2023 + (ordinal - 1) / 8 END, 3, 1
        );
        -- 연락처는 변경 전 값. 승인된 변경은 아래 요청 처리에서 함수가 반영한다.
        seed_student.phone_number := '000-0000-' || lpad(ordinal::TEXT, 4, '0');
        seed_student.sms_opt_in := ordinal % 2 = 1;
        seed_student.email := 'student' || lpad(ordinal::TEXT, 2, '0') || '@example.invalid';
        seed_student.cumulative_mileage := 0;

        INSERT INTO student SELECT seed_student.*
        ON CONFLICT (student_no) DO NOTHING;
        SELECT * INTO STRICT existing_student FROM student WHERE student_no = seed_student.student_no;
        -- 누적 마일리지는 뒤의 마일리지 Seed가 관리하는 저장형 집계값이다.
        -- 재실행 시 이 값이 0이 아니어도 학생 기준정보가 충돌한 것은 아니다.
        -- 연락처 3개는 변경 요청 승인으로 바뀌는 값이므로 비교에서 제외한다.
        IF (to_jsonb(existing_student) - 'cumulative_mileage'
                - 'phone_number' - 'email' - 'sms_opt_in')
           IS DISTINCT FROM (to_jsonb(seed_student) - 'cumulative_mileage'
                - 'phone_number' - 'email' - 'sms_opt_in') THEN
            RAISE EXCEPTION 'Seed 학생 기존 정보 충돌: % (기존 행을 변경하지 않음)', seed_student.student_no;
        END IF;
    END LOOP;

    -- 학생정보 변경 요청은 업무 함수로 요청일시 순서대로 만든다.
    -- old_value는 함수가 현재 값으로 채우고, 승인 시 학생 정보와 로그도 함수가 처리한다.
    FOR seed_request IN SELECT * FROM (VALUES
        ('20230001', 'phone_number', '000-0000-9001',
         TIMESTAMPTZ '2026-09-01 10:00:00+09', 'APPROVED', '90000002',
         TIMESTAMPTZ '2026-09-02 09:00:00+09', '연락처 변경 확인'),
        ('20230001', 'email', 'student01.pending@example.invalid',
         TIMESTAMPTZ '2026-10-13 10:00:00+09', 'PENDING', NULL, NULL, NULL),
        ('20230001', 'phone_number', '000-0000-9101',
         TIMESTAMPTZ '2026-10-02 10:00:00+09', 'REJECTED', '90000003',
         TIMESTAMPTZ '2026-10-03 09:00:00+09', '재변경 사유 확인 필요'),
        ('20230002', 'email', 'student02.updated@example.invalid',
         TIMESTAMPTZ '2026-09-05 10:00:00+09', 'APPROVED', '90000001',
         TIMESTAMPTZ '2026-09-06 09:00:00+09', '이메일 변경 확인'),
        ('20230002', 'phone_number', '000-0000-9002',
         TIMESTAMPTZ '2026-09-09 10:00:00+09', 'REJECTED', '90000002',
         TIMESTAMPTZ '2026-09-10 09:00:00+09', '연락처 확인 자료 보완 필요'),
        ('20230003', 'sms_opt_in', 'false',
         TIMESTAMPTZ '2026-09-11 10:00:00+09', 'APPROVED', '90000001',
         TIMESTAMPTZ '2026-09-12 09:00:00+09', 'SMS 수신 동의 철회 반영'),
        ('20230003', 'email', 'student03.rejected@example.invalid',
         TIMESTAMPTZ '2026-09-15 10:00:00+09', 'REJECTED', '90000003',
         TIMESTAMPTZ '2026-09-16 09:00:00+09', '이메일 확인 자료 보완 필요'),
        ('20230004', 'phone_number', '000-0000-9004',
         TIMESTAMPTZ '2026-10-14 10:00:00+09', 'PENDING', NULL, NULL, NULL),
        ('20230005', 'sms_opt_in', 'false',
         TIMESTAMPTZ '2026-10-14 11:00:00+09', 'PENDING', NULL, NULL, NULL),
        ('20230006', 'phone_number', '000-0000-9006',
         TIMESTAMPTZ '2026-10-04 10:00:00+09', 'APPROVED', '90000002',
         TIMESTAMPTZ '2026-10-05 09:00:00+09', '연락처 변경 확인')
    ) AS expected(student_no, field_name, new_value, requested_at,
                  status, processed_by, processed_at, comment)
    ORDER BY requested_at   -- 순서가 바뀌면 기존 값이 맞지 않아 승인 함수가 거부함
    LOOP
        SELECT request_id INTO v_request_id
          FROM student_info_change_request
         WHERE student_no = seed_request.student_no
           AND field_name = seed_request.field_name
           AND requested_at = seed_request.requested_at;

        IF NOT FOUND THEN
            v_request_id := fn_create_student_info_change_request(
                seed_request.student_no, seed_request.field_name,
                seed_request.new_value, seed_request.requested_at);

            IF seed_request.status = 'APPROVED' THEN
                PERFORM fn_approve_student_info_change(v_request_id,
                    seed_request.processed_by, 'SEED: ' || seed_request.comment,
                    seed_request.processed_at);
            ELSIF seed_request.status = 'REJECTED' THEN
                PERFORM fn_reject_student_info_change(v_request_id,
                    seed_request.processed_by, 'SEED: ' || seed_request.comment,
                    seed_request.processed_at);
            END IF;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM student_info_change_request
             WHERE request_id = v_request_id AND status = seed_request.status
        ) THEN
            RAISE EXCEPTION 'Seed 학생정보 요청 상태 충돌: %', v_request_id;
        END IF;
    END LOOP;
END;
$$;

COMMIT;
