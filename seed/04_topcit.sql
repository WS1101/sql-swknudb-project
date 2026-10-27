\encoding UTF8
-- TOPCIT 4개 회차와 학생별 응시 이력. 학년은 응시 시점 스냅샷으로 보존한다.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
SELECT pg_advisory_xact_lock(20261015, 4);

DO $$
DECLARE
    seed_record RECORD;
    stored_score topcit_score%ROWTYPE;
BEGIN
    FOR seed_record IN SELECT * FROM (VALUES
        ('SEED_TOPCIT_2025_1', DATE '2025-05-17'),
        ('SEED_TOPCIT_2025_2', DATE '2025-10-11'),
        ('SEED_TOPCIT_2026_1', DATE '2026-05-16'),
        ('SEED_TOPCIT_2026_2', DATE '2026-10-10')
    ) AS expected(round_name, exam_date)
    LOOP
        INSERT INTO topcit_exam_round (round_name, exam_date)
        VALUES (seed_record.round_name, seed_record.exam_date)
        ON CONFLICT (round_name) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM topcit_exam_round
             WHERE round_name = seed_record.round_name AND exam_date = seed_record.exam_date
        ) THEN
            RAISE EXCEPTION 'Seed TOPCIT 회차 충돌: %', seed_record.round_name;
        END IF;
    END LOOP;

    FOR seed_record IN SELECT * FROM (VALUES
        (0,   150, 30), (150, 250, 50), (250, 300, 75),
        (300, 400, 100), (400, 500, 150), (500, NULL::INT, 250)
    ) AS expected(min_score, max_score, mileage_awarded)
    LOOP
        INSERT INTO topcit_mileage_criteria (min_score, max_score, mileage_awarded)
        VALUES (seed_record.min_score, seed_record.max_score, seed_record.mileage_awarded)
        ON CONFLICT DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM topcit_mileage_criteria
             WHERE min_score = seed_record.min_score
               AND max_score IS NOT DISTINCT FROM seed_record.max_score
               AND mileage_awarded = seed_record.mileage_awarded
        ) THEN
            RAISE EXCEPTION 'Seed TOPCIT 마일리지 구간 충돌: % ~ %',
                seed_record.min_score, seed_record.max_score;
        END IF;
    END LOOP;

    FOR seed_record IN
        WITH rounds AS (
            SELECT round_id, round_name, exam_date,
                   row_number() OVER (ORDER BY exam_date)::INT AS round_order
              FROM topcit_exam_round
             WHERE round_name LIKE 'SEED_TOPCIT_%'
        ), candidates AS (
            SELECT ordinal,
                   (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0') AS student_no,
                   4 - (ordinal - 1) / 8 AS current_grade,
                   CASE WHEN ordinal = 8 THEN DATE '2025-03-01'
                        WHEN ordinal = 16 THEN DATE '2026-03-01'
                        ELSE make_date(2023 + (ordinal - 1) / 8, 3, 1) END AS admission_date
              FROM generate_series(1, 32) AS student_number(ordinal)
        )
        SELECT c.student_no, r.round_id,
               170 + c.ordinal * 7 + r.round_order * 35 + ((c.ordinal - 1) % 4) * 9 AS total_score,
               greatest(1, c.current_grade - (2026 - extract(year FROM r.exam_date)::INT))::SMALLINT AS grade_at_exam,
               (ARRAY['SEED_CS', 'SEED_SW', 'SEED_MATH', 'SEED_BIO'])[(c.ordinal - 1) % 4 + 1] AS dept_code_at_exam,
               '90000002'::VARCHAR AS created_by,
               (r.exam_date + 3)::TIMESTAMP AT TIME ZONE 'Asia/Seoul' + INTERVAL '9 hours' AS created_at,
               CASE WHEN r.round_name = 'SEED_TOPCIT_2026_2' AND c.ordinal IN (3, 10, 19, 27)
                    THEN '90000001'::VARCHAR END AS updated_by,
               CASE WHEN r.round_name = 'SEED_TOPCIT_2026_2' AND c.ordinal IN (3, 10, 19, 27)
                    THEN ((r.exam_date + 5)::TIMESTAMP AT TIME ZONE 'Asia/Seoul' + INTERVAL '14 hours') END AS updated_at,
               CASE WHEN r.round_name = 'SEED_TOPCIT_2026_2' AND c.ordinal IN (3, 10, 19, 27)
                    THEN 'SEED: 성적표 대조 후 12점 정정'::VARCHAR
                    ELSE 'SEED: 정기 성적 등록'::VARCHAR END AS note
          FROM candidates c CROSS JOIN rounds r
         WHERE c.admission_date <= r.exam_date
         ORDER BY r.exam_date, c.ordinal
    LOOP
        INSERT INTO topcit_score (
            student_no, round_id, total_score, grade_at_exam, dept_code_at_exam,
            created_by, created_at, updated_by, updated_at, note
        ) VALUES (
            seed_record.student_no, seed_record.round_id, seed_record.total_score,
            seed_record.grade_at_exam, seed_record.dept_code_at_exam,
            seed_record.created_by, seed_record.created_at, seed_record.updated_by,
            seed_record.updated_at, seed_record.note
        ) ON CONFLICT (student_no, round_id) DO NOTHING;

        SELECT * INTO STRICT stored_score FROM topcit_score
         WHERE student_no = seed_record.student_no AND round_id = seed_record.round_id;
        IF NOT (to_jsonb(stored_score) @> to_jsonb(seed_record)) THEN
            RAISE EXCEPTION 'Seed TOPCIT 점수 충돌: 학생 %, 회차 %',
                seed_record.student_no, seed_record.round_id;
        END IF;

        IF seed_record.updated_by IS NOT NULL THEN
            INSERT INTO change_log (
                target_type, target_id, action_type, before_value, after_value,
                processed_by, processed_at, reason
            ) SELECT 'topcit_score', stored_score.score_id::TEXT, 'UPDATE',
                     jsonb_build_object('total_score', seed_record.total_score - 12),
                     jsonb_build_object('total_score', seed_record.total_score),
                     seed_record.updated_by, seed_record.updated_at,
                     'SEED: 성적표 재확인에 따른 TOPCIT 점수 정정'
              WHERE NOT EXISTS (
                    SELECT 1 FROM change_log
                     WHERE target_type = 'topcit_score'
                       AND target_id = stored_score.score_id::TEXT
                       AND action_type = 'UPDATE'
                       AND processed_at = seed_record.updated_at
              );
        END IF;
    END LOOP;

    IF (SELECT count(*) FROM topcit_score ts JOIN topcit_exam_round r USING (round_id)
         WHERE r.round_name LIKE 'SEED_TOPCIT_%') <> 110 THEN
        RAISE EXCEPTION 'Seed TOPCIT 점수 건수 불일치';
    END IF;
END;
$$;

COMMIT;
