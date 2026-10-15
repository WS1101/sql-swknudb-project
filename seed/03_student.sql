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
        seed_student.phone_number := CASE
            WHEN ordinal = 1 THEN '000-0000-9001'
            WHEN ordinal = 6 THEN '000-0000-9006'
            ELSE '000-0000-' || lpad(ordinal::TEXT, 4, '0') END;
        seed_student.sms_opt_in := ordinal % 2 = 1 AND ordinal <> 3;
        seed_student.email := CASE WHEN ordinal = 2 THEN 'student02.updated@example.invalid'
            ELSE 'student' || lpad(ordinal::TEXT, 2, '0') || '@example.invalid' END;
        seed_student.cumulative_mileage := 0;

        INSERT INTO student SELECT seed_student.*
        ON CONFLICT (student_no) DO NOTHING;
        SELECT * INTO STRICT existing_student FROM student WHERE student_no = seed_student.student_no;
        IF existing_student IS DISTINCT FROM seed_student THEN
            RAISE EXCEPTION 'Seed 학생 기존 정보 충돌: % (기존 행을 변경하지 않음)', seed_student.student_no;
        END IF;
    END LOOP;

    -- 같은 학생의 승인 후 재요청도 포함한다. 요청 식별은 학생·항목·고정 요청일시를 함께 사용한다.
    FOR seed_request IN SELECT * FROM (VALUES
        ('20230001', 'phone_number', '000-0000-0001', '000-0000-9001',
         TIMESTAMPTZ '2026-09-01 10:00:00+09', 'APPROVED', '90000002',
         TIMESTAMPTZ '2026-09-02 09:00:00+09', '연락처 변경 확인'),
        ('20230001', 'email', 'student01@example.invalid', 'student01.pending@example.invalid',
         TIMESTAMPTZ '2026-10-13 10:00:00+09', 'PENDING', NULL, NULL, NULL),
        ('20230001', 'phone_number', '000-0000-9001', '000-0000-9101',
         TIMESTAMPTZ '2026-10-02 10:00:00+09', 'REJECTED', '90000003',
         TIMESTAMPTZ '2026-10-03 09:00:00+09', '재변경 사유 확인 필요'),
        ('20230002', 'email', 'student02@example.invalid', 'student02.updated@example.invalid',
         TIMESTAMPTZ '2026-09-05 10:00:00+09', 'APPROVED', '90000001',
         TIMESTAMPTZ '2026-09-06 09:00:00+09', '이메일 변경 확인'),
        ('20230002', 'phone_number', '000-0000-0002', '000-0000-9002',
         TIMESTAMPTZ '2026-09-09 10:00:00+09', 'REJECTED', '90000002',
         TIMESTAMPTZ '2026-09-10 09:00:00+09', '연락처 확인 자료 보완 필요'),
        ('20230003', 'sms_opt_in', 'true', 'false',
         TIMESTAMPTZ '2026-09-11 10:00:00+09', 'APPROVED', '90000001',
         TIMESTAMPTZ '2026-09-12 09:00:00+09', 'SMS 수신 동의 철회 반영'),
        ('20230003', 'email', 'student03@example.invalid', 'student03.rejected@example.invalid',
         TIMESTAMPTZ '2026-09-15 10:00:00+09', 'REJECTED', '90000003',
         TIMESTAMPTZ '2026-09-16 09:00:00+09', '이메일 확인 자료 보완 필요'),
        ('20230004', 'phone_number', '000-0000-0004', '000-0000-9004',
         TIMESTAMPTZ '2026-10-14 10:00:00+09', 'PENDING', NULL, NULL, NULL),
        ('20230005', 'sms_opt_in', 'true', 'false',
         TIMESTAMPTZ '2026-10-14 11:00:00+09', 'PENDING', NULL, NULL, NULL),
        ('20230006', 'phone_number', '000-0000-0006', '000-0000-9006',
         TIMESTAMPTZ '2026-10-04 10:00:00+09', 'APPROVED', '90000002',
         TIMESTAMPTZ '2026-10-05 09:00:00+09', '연락처 변경 확인')
    ) AS expected(student_no, field_name, old_value, new_value, requested_at,
                  status, processed_by, processed_at, comment)
    LOOP
        IF (SELECT count(*) FROM student_info_change_request
            WHERE student_no = seed_request.student_no AND field_name = seed_request.field_name
              AND requested_at = seed_request.requested_at) > 1 THEN
            RAISE EXCEPTION 'Seed 요청 식별값 중복: % %', seed_request.student_no, seed_request.field_name;
        END IF;

        INSERT INTO student_info_change_request (
            student_no, field_name, old_value, new_value, requested_at,
            status, processed_by, processed_at, comment
        ) SELECT seed_request.student_no, seed_request.field_name, seed_request.old_value,
            seed_request.new_value, seed_request.requested_at, seed_request.status,
            seed_request.processed_by, seed_request.processed_at, seed_request.comment
        WHERE NOT EXISTS (
            SELECT 1 FROM student_info_change_request
            WHERE student_no = seed_request.student_no AND field_name = seed_request.field_name
              AND requested_at = seed_request.requested_at
        );

        SELECT * INTO STRICT stored_request FROM student_info_change_request
        WHERE student_no = seed_request.student_no AND field_name = seed_request.field_name
          AND requested_at = seed_request.requested_at;
        IF NOT (to_jsonb(stored_request) @> to_jsonb(seed_request)) THEN
            RAISE EXCEPTION 'Seed 요청 내용 충돌: %', stored_request.request_id;
        END IF;
        IF (SELECT to_jsonb(student) ->> seed_request.field_name FROM student
            WHERE student_no = seed_request.student_no) IS DISTINCT FROM
            (CASE WHEN seed_request.status = 'APPROVED' THEN seed_request.new_value ELSE seed_request.old_value END) THEN
            RAISE EXCEPTION 'Seed 학생 기본정보와 요청 처리 결과 불일치: %', stored_request.request_id;
        END IF;

        initial_request := to_jsonb(stored_request) || jsonb_build_object(
            'status', 'PENDING', 'processed_by', NULL, 'processed_at', NULL, 'comment', NULL
        );

        -- 자동 감사 트리거는 없으므로 고정 스냅샷과 일치하는 이력만 직접 삽입한다.
        FOR seed_log IN
            SELECT 'student_info_change_request'::VARCHAR AS target_type,
                stored_request.request_id::VARCHAR AS target_id, 'CREATE'::VARCHAR AS action_type,
                NULL::JSONB AS before_value, initial_request AS after_value,
                stored_request.student_no AS processed_by, stored_request.requested_at AS processed_at,
                'SEED: 학생정보 수정 요청'::TEXT AS reason
            UNION ALL
            SELECT 'student_info_change_request', stored_request.request_id::VARCHAR,
                CASE WHEN stored_request.status = 'APPROVED' THEN 'APPROVE' ELSE 'REJECT' END,
                initial_request, to_jsonb(stored_request), stored_request.processed_by,
                stored_request.processed_at, 'SEED: ' || stored_request.comment
            WHERE stored_request.status <> 'PENDING'
            UNION ALL
            SELECT 'student', stored_request.student_no, 'UPDATE',
                jsonb_build_object(stored_request.field_name,
                    CASE WHEN stored_request.field_name = 'sms_opt_in'
                         THEN to_jsonb(stored_request.old_value::BOOLEAN) ELSE to_jsonb(stored_request.old_value) END),
                jsonb_build_object(stored_request.field_name,
                    CASE WHEN stored_request.field_name = 'sms_opt_in'
                         THEN to_jsonb(stored_request.new_value::BOOLEAN) ELSE to_jsonb(stored_request.new_value) END),
                stored_request.processed_by, stored_request.processed_at,
                'SEED: 수정 요청 ' || stored_request.request_id::TEXT || ' 승인 반영'
            WHERE stored_request.status = 'APPROVED'
        LOOP
            INSERT INTO change_log (
                target_type, target_id, action_type, before_value, after_value,
                processed_by, processed_at, reason
            ) SELECT seed_log.target_type, seed_log.target_id, seed_log.action_type,
                seed_log.before_value, seed_log.after_value, seed_log.processed_by,
                seed_log.processed_at, seed_log.reason
            WHERE NOT EXISTS (
                SELECT 1 FROM change_log
                WHERE target_type = seed_log.target_type AND target_id = seed_log.target_id
                  AND action_type = seed_log.action_type AND processed_at = seed_log.processed_at
            );
            IF (SELECT count(*) FROM change_log
                WHERE target_type = seed_log.target_type AND target_id = seed_log.target_id
                  AND action_type = seed_log.action_type AND processed_at = seed_log.processed_at
                  AND to_jsonb(change_log) @> to_jsonb(seed_log)) <> 1 THEN
                RAISE EXCEPTION 'Seed 변경로그 충돌: % %', seed_log.target_type, seed_log.target_id;
            END IF;
        END LOOP;
    END LOOP;
END;
$$;

COMMIT;
