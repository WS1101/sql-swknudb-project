-- 프로그램·마일리지 신청·증빙. 모든 상태 변경은 업무 함수를 통해 로그와 함께 만든다.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
SELECT pg_advisory_xact_lock(20261015, 5);

DO $$
DECLARE
    seed_record RECORD;
    v_program_id INT;
    v_application_id BIGINT;
    v_count INT;
BEGIN
    FOR seed_record IN SELECT * FROM (VALUES
        ('SEED [테스트용 가상] SW·AI 경진대회',             'SEED_CONTEST',  DATE '2026-03-28', '국립공주대학교 SW중심대학사업단(테스트용)', 80, 40, 100),
        ('SEED [테스트용 가상] SW·AI 집중교육',              'SEED_TRAINING', DATE '2026-04-11', '국립공주대학교 SW중심대학사업단(테스트용)', 60, 35,  80),
        ('SEED [테스트용 가상] SW전문가 특강',               'SEED_TRAINING', DATE '2026-05-09', '국립공주대학교 SW중심대학사업단(테스트용)', 50, 30,  70),
        ('SEED [테스트용 가상] 산학캡스톤디자인',            'SEED_CAMP',     DATE '2026-06-20', '국립공주대학교 SW중심대학사업단(테스트용)', 70, 45, 120),
        ('SEED [테스트용 가상] SW 가치확산 활동',            'SEED_MENTORING',DATE '2026-07-15', '국립공주대학교 SW중심대학사업단(테스트용)',100, 25,  60),
        ('SEED [테스트용 가상] SW중심대학 에세이 공모전',    'SEED_CONTEST',  DATE '2026-08-22', 'SW중심대학협의회(테스트용)',               120, 50, 150),
        ('SEED [테스트용 가상] TOPCIT 대비 특강',            'SEED_TRAINING', DATE '2026-09-05', '국립공주대학교 SW중심대학사업단(테스트용)', 45, 35,  75),
        ('SEED [테스트용 가상] AI·SW중심대학 디지털 경진대회','SEED_CONTEST', DATE '2026-09-19', 'SW중심대학협의회(테스트용)',                90, 45, 130),
        ('SEED [테스트용 가상] 산학캡스톤디자인 캠프',       'SEED_CAMP',     DATE '2026-10-03', '국립공주대학교 SW중심대학사업단(테스트용)', 80, 30,  65),
        ('SEED [테스트용 가상] 지역사회 SW 가치확산 활동',   'SEED_MENTORING',DATE '2026-10-17', '국립공주대학교 SW중심대학사업단(테스트용)', 55, 40,  90)
    ) AS expected(program_name, program_type_code, program_date, organizer, capacity,
                  participation_mileage, award_mileage)
    LOOP
        SELECT count(*), min(program_id) INTO v_count, v_program_id
          FROM program WHERE program_name = seed_record.program_name;
        IF v_count = 0 THEN
            INSERT INTO program (program_type_code, program_name, program_date, organizer, capacity)
            VALUES (seed_record.program_type_code, seed_record.program_name,
                    seed_record.program_date, seed_record.organizer, seed_record.capacity)
            RETURNING program_id INTO v_program_id;
        ELSIF v_count > 1 THEN
            RAISE EXCEPTION 'Seed 프로그램 업무키 중복: %', seed_record.program_name;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM program
             WHERE program_id = v_program_id
               AND program_type_code = seed_record.program_type_code
               AND program_date = seed_record.program_date
               AND organizer = seed_record.organizer
               AND capacity = seed_record.capacity
        ) THEN
            RAISE EXCEPTION 'Seed 프로그램 충돌: %', seed_record.program_name;
        END IF;

        INSERT INTO mileage_criteria (program_id, participation_mileage, award_mileage)
        VALUES (v_program_id, seed_record.participation_mileage, seed_record.award_mileage)
        ON CONFLICT (program_id) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM mileage_criteria
             WHERE program_id = v_program_id
               AND participation_mileage = seed_record.participation_mileage
               AND award_mileage = seed_record.award_mileage
        ) THEN
            RAISE EXCEPTION 'Seed 프로그램 마일리지 기준 충돌: %', seed_record.program_name;
        END IF;
    END LOOP;

    -- 학생마다 서로 다른 두 프로그램을 연결한다.
    FOR seed_record IN
        WITH students AS (
            SELECT ordinal,
                   (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0') AS student_no
              FROM generate_series(1, 32) AS student_number(ordinal)
        ), programs AS (
            SELECT program_id, program_name, program_date,
                   row_number() OVER (ORDER BY program_date)::INT AS program_order
              FROM program WHERE program_name LIKE 'SEED %'
        ), applications AS (
            SELECT s.ordinal, s.student_no, p.program_id, p.program_name,
                   'PARTICIPATION'::TEXT AS participation_type,
                   CASE WHEN s.ordinal % 8 = 6 THEN 'ADMIN_DIRECT'
                        ELSE 'STUDENT_REQUEST' END AS registration_path,
                   CASE s.ordinal % 8 WHEN 0 THEN 'REVOKED' WHEN 1 THEN 'PENDING'
                       WHEN 2 THEN 'APPROVED' WHEN 3 THEN 'REJECTED'
                       WHEN 4 THEN 'CANCELLED' WHEN 5 THEN 'APPROVED'
                       WHEN 6 THEN 'APPROVED' ELSE 'REJECTED' END AS final_status,
                   (p.program_date + 2)::TIMESTAMP AT TIME ZONE 'Asia/Seoul' + INTERVAL '10 hours' AS applied_at,
                   1 AS application_order
              FROM students s JOIN programs p ON p.program_order = ((s.ordinal - 1) % 10) + 1
            UNION ALL
            SELECT s.ordinal, s.student_no, p.program_id, p.program_name,
                   'AWARD'::TEXT,
                   'STUDENT_REQUEST',
                   CASE s.ordinal % 5 WHEN 0 THEN 'PENDING' WHEN 1 THEN 'APPROVED'
                       WHEN 2 THEN 'APPROVED' WHEN 3 THEN 'REJECTED' ELSE 'CANCELLED' END,
                   (p.program_date + 3)::TIMESTAMP AT TIME ZONE 'Asia/Seoul' + INTERVAL '11 hours',
                   2
              FROM students s JOIN programs p ON p.program_order = ((s.ordinal + 3) % 10) + 1
        )
        SELECT * FROM applications ORDER BY ordinal, application_order
    LOOP
        SELECT count(*), min(application_id) INTO v_count, v_application_id
          FROM mileage_application
         WHERE student_no = seed_record.student_no
           AND source_type = 'PROGRAM'
           AND program_id = seed_record.program_id
           AND applied_at = seed_record.applied_at;

        IF v_count = 0 AND seed_record.registration_path = 'ADMIN_DIRECT' THEN
            -- 관리자 직권등록: 등록 함수가 즉시 승인까지 처리 (보고서 6.2)
            v_application_id := fn_create_mileage_application(
                seed_record.student_no, 'PROGRAM', '90000001', 'ADMIN_DIRECT',
                seed_record.program_id, NULL, seed_record.participation_type,
                'SEED: 참여 명단 확인 후 직권 등록', seed_record.applied_at);
        ELSIF v_count = 0 THEN
            v_application_id := fn_create_mileage_application(
                seed_record.student_no, 'PROGRAM', seed_record.student_no,
                'STUDENT_REQUEST', seed_record.program_id, NULL,
                seed_record.participation_type,
                'SEED: ' || seed_record.program_name || ' 증빙 신청', seed_record.applied_at);

            IF seed_record.final_status = 'APPROVED' THEN
                PERFORM fn_approve_mileage_application(v_application_id, '90000001',
                    'SEED: 참여 사실 확인', seed_record.applied_at + INTERVAL '1 day');
            ELSIF seed_record.final_status = 'REJECTED' THEN
                PERFORM fn_reject_mileage_application(v_application_id, '90000001',
                    'SEED: 증빙의 참가자 정보가 불충분함', seed_record.applied_at + INTERVAL '1 day');
            ELSIF seed_record.final_status = 'CANCELLED' THEN
                PERFORM fn_cancel_mileage_application(v_application_id, seed_record.student_no,
                    'SEED: 학생 본인 신청 취소', seed_record.applied_at + INTERVAL '6 hours');
            ELSIF seed_record.final_status = 'REVOKED' THEN
                PERFORM fn_approve_mileage_application(v_application_id, '90000001',
                    'SEED: 최초 승인', seed_record.applied_at + INTERVAL '1 day');
                PERFORM fn_revoke_mileage_application(v_application_id, '90000001',
                    'SEED: 중복 참가 확인으로 적립 회수', seed_record.applied_at + INTERVAL '2 days');
            END IF;
        ELSIF v_count > 1 THEN
            RAISE EXCEPTION 'Seed 프로그램 마일리지 신청 중복: % / %',
                seed_record.student_no, seed_record.program_name;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM mileage_application
             WHERE application_id = v_application_id
               AND participation_type = seed_record.participation_type
               AND status = seed_record.final_status
        ) THEN
            RAISE EXCEPTION 'Seed 프로그램 마일리지 신청 충돌: %', v_application_id;
        END IF;

        INSERT INTO attachment (application_id, file_name, file_path, uploaded_at)
        SELECT v_application_id,
               CASE seed_record.participation_type WHEN 'AWARD' THEN '가상_상장.pdf' ELSE '가상_참가확인서.pdf' END,
               'seed/mileage/' || v_application_id || '/evidence.pdf',
               seed_record.applied_at + INTERVAL '5 minutes'
         WHERE seed_record.registration_path = 'STUDENT_REQUEST'   -- 직권등록은 증빙 0건
           AND NOT EXISTS (
               SELECT 1 FROM attachment
                WHERE application_id = v_application_id
                  AND file_path = 'seed/mileage/' || v_application_id || '/evidence.pdf'
         );
    END LOOP;

    -- 최근 TOPCIT 회차 중 20명은 점수 기반 마일리지도 신청한다.
    FOR seed_record IN
        WITH candidates AS (
            SELECT ordinal,
                   (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0') AS student_no
              FROM generate_series(1, 20) AS student_number(ordinal)
        )
        SELECT c.ordinal, c.student_no, ts.score_id,
               CASE c.ordinal % 4 WHEN 0 THEN 'PENDING' WHEN 1 THEN 'APPROVED'
                    WHEN 2 THEN 'REJECTED' ELSE 'CANCELLED' END AS final_status,
               TIMESTAMPTZ '2026-10-14 13:00:00+09' + c.ordinal * INTERVAL '10 minutes' AS applied_at
          FROM candidates c
          JOIN topcit_exam_round r ON r.round_name = 'SEED_TOPCIT_2026_2'
          JOIN topcit_score ts ON ts.round_id = r.round_id AND ts.student_no = c.student_no
         ORDER BY c.ordinal
    LOOP
        SELECT count(*), min(application_id) INTO v_count, v_application_id
          FROM mileage_application
         WHERE student_no = seed_record.student_no
           AND source_type = 'TOPCIT'
           AND topcit_score_id = seed_record.score_id
           AND applied_at = seed_record.applied_at;
        IF v_count = 0 THEN
            v_application_id := fn_create_mileage_application(
                seed_record.student_no, 'TOPCIT', seed_record.student_no,
                'STUDENT_REQUEST', NULL, seed_record.score_id, NULL,
                'SEED: TOPCIT 성적 적립 신청', seed_record.applied_at);
            IF seed_record.final_status = 'APPROVED' THEN
                PERFORM fn_approve_mileage_application(v_application_id, '90000001',
                    'SEED: TOPCIT 성적 확인', seed_record.applied_at + INTERVAL '1 day');
            ELSIF seed_record.final_status = 'REJECTED' THEN
                PERFORM fn_reject_mileage_application(v_application_id, '90000001',
                    'SEED: 성적표 식별정보 확인 필요', seed_record.applied_at + INTERVAL '1 day');
            ELSIF seed_record.final_status = 'CANCELLED' THEN
                PERFORM fn_cancel_mileage_application(v_application_id, seed_record.student_no,
                    'SEED: 학생 본인 신청 취소', seed_record.applied_at + INTERVAL '2 hours');
            END IF;
        ELSIF v_count > 1 THEN
            RAISE EXCEPTION 'Seed TOPCIT 마일리지 신청 중복: %', seed_record.student_no;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM mileage_application
                        WHERE application_id = v_application_id
                          AND status = seed_record.final_status) THEN
            RAISE EXCEPTION 'Seed TOPCIT 마일리지 신청 충돌: %', v_application_id;
        END IF;
        INSERT INTO attachment (application_id, file_name, file_path, uploaded_at)
        SELECT v_application_id, '가상_TOPCIT성적표.pdf',
               'seed/mileage/' || v_application_id || '/topcit-score.pdf',
               seed_record.applied_at + INTERVAL '5 minutes'
         WHERE NOT EXISTS (
               SELECT 1 FROM attachment
                WHERE application_id = v_application_id
                  AND file_path = 'seed/mileage/' || v_application_id || '/topcit-score.pdf'
         );
    END LOOP;

    -- 저장형 집계값은 승인 상태만의 합과 항상 같아야 한다.
    IF EXISTS (
        SELECT 1 FROM student s
         WHERE s.student_no IN (
             SELECT (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0')
             FROM generate_series(1, 32) AS student_number(ordinal)
         )
           AND s.cumulative_mileage <> (
               SELECT COALESCE(sum(ma.requested_mileage), 0)
                 FROM mileage_application ma
                WHERE ma.student_no = s.student_no AND ma.status = 'APPROVED'
           )
    ) THEN
        RAISE EXCEPTION 'Seed 학생 누적 마일리지와 승인 합계 불일치';
    END IF;
END;
$$;

COMMIT;
