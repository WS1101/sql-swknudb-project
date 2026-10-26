-- 프로그램 6개의 만족도 조사, 객관식 3문항과 주관식 1문항, 학과·학년별 응답.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
SELECT pg_advisory_xact_lock(20261015, 7);

DO $$
DECLARE
    seed_record RECORD;
    question_record RECORD;
    v_survey_id INT;
    v_response_id BIGINT;
    v_count INT;
    v_new BOOLEAN;
BEGIN
    FOR seed_record IN
        SELECT p.program_id, p.program_name, p.program_date,
               row_number() OVER (ORDER BY p.program_date)::INT AS survey_order
          FROM program p
         WHERE p.program_name IN (
             'SEED [테스트용 가상] SW·AI 경진대회', 'SEED [테스트용 가상] SW·AI 집중교육',
             'SEED [테스트용 가상] SW전문가 특강', 'SEED [테스트용 가상] 산학캡스톤디자인',
             'SEED [테스트용 가상] SW 가치확산 활동', 'SEED [테스트용 가상] SW중심대학 에세이 공모전'
         )
         ORDER BY p.program_date
    LOOP
        SELECT count(*), min(survey_id) INTO v_count, v_survey_id
          FROM survey
         WHERE program_id = seed_record.program_id
           AND survey_name = 'SEED ' || seed_record.program_name || ' 만족도 조사';
        IF v_count = 0 THEN
            INSERT INTO survey (program_id, survey_name, start_date, end_date, status)
            VALUES (seed_record.program_id, 'SEED ' || seed_record.program_name || ' 만족도 조사',
                    seed_record.program_date, seed_record.program_date + 14, 'CLOSED')
            RETURNING survey_id INTO v_survey_id;
        ELSIF v_count > 1 THEN
            RAISE EXCEPTION 'Seed 만족도 조사 업무키 중복: %', seed_record.program_name;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM survey WHERE survey_id = v_survey_id
             AND start_date = seed_record.program_date
             AND end_date = seed_record.program_date + 14
             AND status = 'CLOSED'
        ) THEN
            RAISE EXCEPTION 'Seed 만족도 조사 충돌: %', seed_record.program_name;
        END IF;

        FOR question_record IN SELECT * FROM (VALUES
            (1::SMALLINT, 'SEED_CONTENT',   '프로그램 내용이 전공 역량 향상에 도움이 되었습니까?', 'SCALE', 5::SMALLINT),
            (2::SMALLINT, 'SEED_OPERATION', '일정과 운영 지원이 원활했습니까?',                 'SCALE', 5::SMALLINT),
            (3::SMALLINT, 'SEED_OVERALL',   '프로그램 전반에 만족하십니까?',                   'SCALE', 5::SMALLINT),
            (4::SMALLINT, 'SEED_OPINION',   '좋았던 점이나 개선 의견을 적어 주세요.',           'TEXT',  NULL::SMALLINT)
        ) AS expected(display_order, category_code, question_text, question_type, scale_max)
        LOOP
            INSERT INTO survey_question (
                survey_id, category_code, display_order, question_text, question_type, scale_max
            ) VALUES (
                v_survey_id, question_record.category_code, question_record.display_order,
                question_record.question_text, question_record.question_type, question_record.scale_max
            ) ON CONFLICT (survey_id, display_order) DO NOTHING;
            IF NOT EXISTS (
                SELECT 1 FROM survey_question
                 WHERE survey_id = v_survey_id
                   AND display_order = question_record.display_order
                   AND category_code = question_record.category_code
                   AND question_text = question_record.question_text
                   AND question_type = question_record.question_type
                   AND scale_max IS NOT DISTINCT FROM question_record.scale_max
            ) THEN
                RAISE EXCEPTION 'Seed 만족도 문항 충돌: 조사 %, 순번 %',
                    v_survey_id, question_record.display_order;
            END IF;
        END LOOP;
    END LOOP;

    FOR seed_record IN
        WITH surveys AS (
            SELECT s.survey_id, p.program_date,
                   row_number() OVER (ORDER BY p.program_date)::INT AS survey_order
              FROM survey s JOIN program p USING (program_id)
             WHERE s.survey_name LIKE 'SEED % 만족도 조사'
        ), students AS (
            SELECT ordinal,
                   (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0') AS student_no
              FROM generate_series(1, 32) AS student_number(ordinal)
        ), responses AS (
            SELECT sv.survey_id, sv.survey_order, st.ordinal, st.student_no, 1 AS attempt,
                   (sv.program_date + 4)::TIMESTAMP AT TIME ZONE 'Asia/Seoul'
                       + INTERVAL '10 hours' + st.ordinal * INTERVAL '3 minutes' AS responded_at
              FROM surveys sv CROSS JOIN students st
             WHERE (st.ordinal + sv.survey_order) % 3 <> 0
            UNION ALL
            SELECT sv.survey_id, sv.survey_order, 1, '20230001', 2,
                   (sv.program_date + 7)::TIMESTAMP AT TIME ZONE 'Asia/Seoul' + INTERVAL '15 hours'
              FROM surveys sv WHERE sv.survey_order = 1
        )
        SELECT * FROM responses ORDER BY survey_order, ordinal, attempt
    LOOP
        SELECT count(*), min(response_id) INTO v_count, v_response_id
          FROM survey_response
         WHERE survey_id = seed_record.survey_id
           AND student_no = seed_record.student_no
           AND responded_at = seed_record.responded_at;
        v_new := v_count = 0;
        IF v_new THEN
            INSERT INTO survey_response (
                survey_id, student_no, grade_at_response, dept_code_at_response,
                responded_at, is_completed
            ) VALUES (
                seed_record.survey_id, seed_record.student_no, NULL, NULL,
                seed_record.responded_at, FALSE
            ) RETURNING response_id INTO v_response_id;
        ELSIF v_count > 1 THEN
            RAISE EXCEPTION 'Seed 만족도 응답 업무키 중복: 조사 %, 학생 %, 시각 %',
                seed_record.survey_id, seed_record.student_no, seed_record.responded_at;
        END IF;

        IF v_new THEN
            FOR question_record IN
                SELECT question_id, display_order, question_type
                  FROM survey_question
                 WHERE survey_id = seed_record.survey_id
                 ORDER BY display_order
            LOOP
                IF question_record.question_type = 'SCALE' THEN
                    INSERT INTO survey_response_detail (response_id, question_id, score, text_answer)
                    VALUES (
                        v_response_id, question_record.question_id,
                        1 + ((seed_record.ordinal + question_record.display_order
                              + seed_record.survey_order + seed_record.attempt) % 5), NULL
                    );
                ELSE
                    INSERT INTO survey_response_detail (response_id, question_id, score, text_answer)
                    VALUES (
                        v_response_id, question_record.question_id, NULL,
                        (ARRAY[
                            '실습 시간이 충분해서 이해에 도움이 되었습니다.',
                            '팀 활동 안내를 조금 더 일찍 제공하면 좋겠습니다.',
                            '다른 학과 학생과 협업할 수 있어 유익했습니다.',
                            '후속 심화 프로그램도 개설되기를 바랍니다.'
                        ])[((seed_record.ordinal + seed_record.survey_order + seed_record.attempt - 1) % 4) + 1]
                    );
                END IF;
            END LOOP;
            UPDATE survey_response SET is_completed = TRUE WHERE response_id = v_response_id;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM survey_response
                        WHERE response_id = v_response_id AND is_completed)
           OR (SELECT count(*) FROM survey_response_detail
                WHERE response_id = v_response_id) <> 4 THEN
            RAISE EXCEPTION 'Seed 만족도 완료 응답 충돌: %', v_response_id;
        END IF;
    END LOOP;

    -- 미완료(임시저장) 응답: 완료 응답 기준(Q10) 검증용. 통계에서 제외되어야 한다.
    FOR seed_record IN
        SELECT s.survey_id, st.student_no
          FROM survey s
          JOIN (VALUES ('20240010'), ('20250018'), ('20260027')) AS st(student_no) ON TRUE
         WHERE s.survey_name LIKE '%SW·AI 경진대회 만족도 조사'
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM survey_response
             WHERE survey_id = seed_record.survey_id
               AND student_no = seed_record.student_no
               AND responded_at = TIMESTAMPTZ '2026-04-05 20:00:00+09'
        ) THEN
            INSERT INTO survey_response (survey_id, student_no, responded_at, is_completed)
            VALUES (seed_record.survey_id, seed_record.student_no,
                    TIMESTAMPTZ '2026-04-05 20:00:00+09', FALSE)
            RETURNING response_id INTO v_response_id;

            INSERT INTO survey_response_detail (response_id, question_id, score)
            SELECT v_response_id, question_id, 1
              FROM survey_question
             WHERE survey_id = seed_record.survey_id AND display_order IN (1, 2);
        END IF;
    END LOOP;
END;
$$;

COMMIT;
