\encoding UTF8
-- Seed 적용 직후 실행되는 읽기 전용 무결성·집계 검증.
\set ON_ERROR_STOP on
SET search_path = public, pg_temp;

DO $$
DECLARE
    v_seed_log_count INT;
BEGIN
    IF (SELECT count(*) FROM app_user WHERE login_id LIKE 'seed.student.%') <> 32
       OR (SELECT count(*) FROM app_user WHERE login_id IN ('seed.master', 'seed.admin.1', 'seed.admin.2')) <> 3 THEN
        RAISE EXCEPTION 'VERIFY 사용자 수 불일치';
    END IF;
    IF (SELECT count(*) FROM student WHERE student_no IN (
        SELECT (2023 + (ordinal - 1) / 8)::TEXT || lpad(ordinal::TEXT, 4, '0')
        FROM generate_series(1, 32) AS student_number(ordinal))) <> 32 THEN
        RAISE EXCEPTION 'VERIFY 학생 수 불일치';
    END IF;
    IF (SELECT count(*) FROM professor WHERE professor_id LIKE '9100000_') <> 4 THEN
        RAISE EXCEPTION 'VERIFY 교수 수 불일치';
    END IF;

    IF (SELECT count(*) FROM topcit_exam_round WHERE round_name LIKE 'SEED_TOPCIT_%') <> 4
       OR (SELECT count(*) FROM topcit_score ts JOIN topcit_exam_round r USING (round_id)
            WHERE r.round_name LIKE 'SEED_TOPCIT_%') <> 110 THEN
        RAISE EXCEPTION 'VERIFY TOPCIT 회차 또는 점수 수 불일치';
    END IF;
    IF EXISTS (
        SELECT student_no, round_id FROM topcit_score
         GROUP BY student_no, round_id HAVING count(*) > 1
    ) OR EXISTS (
        SELECT s.student_no FROM student s
         WHERE s.student_no LIKE '202_____'
           AND (SELECT count(*) FROM topcit_score ts
                 JOIN topcit_exam_round r USING (round_id)
                WHERE ts.student_no = s.student_no AND r.round_name LIKE 'SEED_TOPCIT_%') < 2
    ) THEN
        RAISE EXCEPTION 'VERIFY TOPCIT 학생·회차 중복 또는 다회차 이력 부족';
    END IF;

    IF (SELECT count(*) FROM program WHERE program_name LIKE 'SEED %') <> 10
       OR (SELECT count(*) FROM mileage_application ma
            JOIN app_user u ON u.user_id = ma.student_no
           WHERE u.login_id LIKE 'seed.student.%') <> 84
       OR (SELECT count(*) FROM attachment a JOIN mileage_application ma USING (application_id)
            JOIN app_user u ON u.user_id = ma.student_no
           WHERE u.login_id LIKE 'seed.student.%' AND a.file_path LIKE 'seed/mileage/%') <> 80 THEN
        RAISE EXCEPTION 'VERIFY 프로그램·마일리지·첨부 수 불일치';
    END IF;
    IF EXISTS (
        SELECT 1 FROM student s
         JOIN app_user u ON u.user_id = s.student_no AND u.login_id LIKE 'seed.student.%'
         WHERE s.cumulative_mileage <> (
             SELECT COALESCE(sum(ma.requested_mileage), 0)
               FROM mileage_application ma
              WHERE ma.student_no = s.student_no AND ma.status = 'APPROVED')
    ) THEN
        RAISE EXCEPTION 'VERIFY 누적 마일리지와 승인 합계 불일치';
    END IF;
    IF (SELECT count(DISTINCT status) FROM mileage_application ma
        JOIN app_user u ON u.user_id = ma.student_no
        WHERE u.login_id LIKE 'seed.student.%') <> 5 THEN
        RAISE EXCEPTION 'VERIFY 마일리지 상태 시나리오 부족';
    END IF;

    IF (SELECT count(*) FROM budget_project WHERE project_name LIKE 'SEED % SW중심대학사업') <> 2
       OR (SELECT count(*) FROM initial_budget ib JOIN budget_project bp USING (project_id)
            WHERE bp.project_name LIKE 'SEED % SW중심대학사업') <> 14
       OR (SELECT count(*) FROM expenditure WHERE description LIKE 'SEED-%') <> 42 THEN
        RAISE EXCEPTION 'VERIFY 사업·최초예산·지출 수 불일치';
    END IF;
    IF EXISTS (
        SELECT 1 FROM initial_budget ib
        LEFT JOIN expenditure e ON e.project_id = ib.project_id
                               AND e.budget_item_id = ib.budget_item_id
                               AND e.status = 'APPROVED'
         GROUP BY ib.project_id, ib.budget_item_id, ib.expenditure_limit
        HAVING COALESCE(sum(e.amount), 0) > ib.expenditure_limit
           OR ib.expenditure_limit - COALESCE(sum(e.amount), 0) < 0
    ) THEN
        RAISE EXCEPTION 'VERIFY 승인 지출 합계·예산 잔액·한도 불일치';
    END IF;
    IF (SELECT count(DISTINCT status) FROM expenditure WHERE description LIKE 'SEED-%') <> 3 THEN
        RAISE EXCEPTION 'VERIFY 지출 상태 시나리오 부족';
    END IF;

    IF (SELECT count(*) FROM survey WHERE survey_name LIKE 'SEED % 만족도 조사') <> 6
       OR (SELECT count(*) FROM survey_question q JOIN survey s USING (survey_id)
            WHERE s.survey_name LIKE 'SEED % 만족도 조사') <> 24
       OR (SELECT count(*) FROM survey_response r JOIN survey s USING (survey_id)
            WHERE s.survey_name LIKE 'SEED % 만족도 조사') <> 132 THEN
        RAISE EXCEPTION 'VERIFY 만족도 조사·문항·응답 수 불일치';
    END IF;
    IF EXISTS (
        SELECT 1 FROM survey_response r
        JOIN survey s USING (survey_id)
        LEFT JOIN LATERAL (
            SELECT count(*) AS answered FROM survey_response_detail d
             WHERE d.response_id = r.response_id
        ) x ON TRUE
        WHERE s.survey_name LIKE 'SEED % 만족도 조사'
          AND r.is_completed AND x.answered <> 4   -- 미완료 응답은 일부 문항만 있어도 정상
    ) OR EXISTS (
        SELECT 1 FROM survey_response_detail d
        JOIN survey_response r USING (response_id)
        JOIN survey_question q USING (question_id)
        JOIN survey s ON s.survey_id = r.survey_id
        WHERE s.survey_name LIKE 'SEED % 만족도 조사'
          AND (q.survey_id <> r.survey_id
               OR (q.question_type = 'SCALE' AND (d.score IS NULL OR d.text_answer IS NOT NULL))
               OR (q.question_type = 'TEXT' AND (d.score IS NOT NULL OR d.text_answer IS NULL)))
    ) THEN
        RAISE EXCEPTION 'VERIFY 만족도 응답·문항 연결 불일치';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM change_log WHERE target_type = 'student_info_change_request' AND action_type = 'APPROVE')
       OR NOT EXISTS (SELECT 1 FROM change_log WHERE target_type = 'topcit_score' AND action_type = 'UPDATE')
       OR NOT EXISTS (SELECT 1 FROM change_log WHERE target_type = 'mileage_application' AND action_type = 'REJECT')
       OR NOT EXISTS (SELECT 1 FROM change_log WHERE target_type = 'mileage_application' AND action_type = 'REVOKE')
       OR NOT EXISTS (SELECT 1 FROM change_log WHERE target_type = 'initial_budget' AND action_type = 'APPROVE')
       OR NOT EXISTS (SELECT 1 FROM change_log WHERE target_type = 'expenditure' AND action_type = 'APPROVE') THEN
        RAISE EXCEPTION 'VERIFY 필수 변경 이력 시나리오 부족';
    END IF;
    IF EXISTS (SELECT 1 FROM change_log l LEFT JOIN app_user u ON u.user_id = l.processed_by
               WHERE u.user_id IS NULL) THEN
        RAISE EXCEPTION 'VERIFY 변경 이력 처리자 사용자 연결 불일치';
    END IF;

    SELECT count(*) INTO v_seed_log_count
      FROM change_log l
     WHERE (l.target_type = 'student_info_change_request' AND EXISTS (
            SELECT 1 FROM student_info_change_request r
              JOIN app_user u ON u.user_id = r.student_no
             WHERE r.request_id::TEXT = l.target_id AND u.login_id LIKE 'seed.student.%'))
        OR (l.target_type = 'student' AND l.reason LIKE '변경 요청 %'
            AND EXISTS (SELECT 1 FROM app_user u WHERE u.user_id = l.target_id
                         AND u.login_id LIKE 'seed.student.%'))
        OR (l.target_type = 'student' AND l.reason LIKE '마일리지 신청 %'
            AND EXISTS (SELECT 1 FROM app_user u WHERE u.user_id = l.target_id
                         AND u.login_id LIKE 'seed.student.%'))
        OR (l.target_type = 'topcit_score' AND EXISTS (
            SELECT 1 FROM topcit_score ts JOIN topcit_exam_round r USING (round_id)
             WHERE ts.score_id::TEXT = l.target_id AND r.round_name LIKE 'SEED_TOPCIT_%'))
        OR (l.target_type = 'mileage_application' AND EXISTS (
            SELECT 1 FROM mileage_application ma
             WHERE ma.application_id::TEXT = l.target_id AND ma.memo LIKE 'SEED:%'))
        OR (l.target_type = 'initial_budget' AND EXISTS (
            SELECT 1 FROM initial_budget ib JOIN budget_project bp USING (project_id)
             WHERE l.target_id = ib.project_id::TEXT || ':' || ib.budget_item_id::TEXT
               AND bp.project_name LIKE 'SEED %'))
        OR (l.target_type = 'expenditure' AND EXISTS (
            SELECT 1 FROM expenditure e
             WHERE e.expenditure_id::TEXT = l.target_id AND e.description LIKE 'SEED-%'));
    IF v_seed_log_count <> 305 THEN
        RAISE EXCEPTION 'VERIFY Seed 변경 로그 수 불일치: %', v_seed_log_count;
    END IF;
END;
$$;

WITH seed_log AS (
    SELECT l.log_id FROM change_log l
     WHERE (l.target_type = 'student_info_change_request' AND EXISTS (
            SELECT 1 FROM student_info_change_request r
              JOIN app_user u ON u.user_id = r.student_no
             WHERE r.request_id::TEXT = l.target_id AND u.login_id LIKE 'seed.student.%'))
        OR (l.target_type = 'student' AND l.reason LIKE '변경 요청 %'
            AND EXISTS (SELECT 1 FROM app_user u WHERE u.user_id = l.target_id
                         AND u.login_id LIKE 'seed.student.%'))
        OR (l.target_type = 'student' AND l.reason LIKE '마일리지 신청 %'
            AND EXISTS (SELECT 1 FROM app_user u WHERE u.user_id = l.target_id AND u.login_id LIKE 'seed.student.%'))
        OR (l.target_type = 'topcit_score' AND EXISTS (SELECT 1 FROM topcit_score ts JOIN topcit_exam_round r USING (round_id) WHERE ts.score_id::TEXT=l.target_id AND r.round_name LIKE 'SEED_TOPCIT_%'))
        OR (l.target_type = 'mileage_application' AND EXISTS (SELECT 1 FROM mileage_application ma WHERE ma.application_id::TEXT=l.target_id AND ma.memo LIKE 'SEED:%'))
        OR (l.target_type = 'initial_budget' AND EXISTS (SELECT 1 FROM initial_budget ib JOIN budget_project bp USING(project_id) WHERE l.target_id=ib.project_id::TEXT||':'||ib.budget_item_id::TEXT AND bp.project_name LIKE 'SEED %'))
        OR (l.target_type = 'expenditure' AND EXISTS (SELECT 1 FROM expenditure e WHERE e.expenditure_id::TEXT=l.target_id AND e.description LIKE 'SEED-%'))
)
SELECT entity, row_count
FROM (VALUES
    ('app_user',             (SELECT count(*) FROM app_user WHERE login_id LIKE 'seed.%')),
    ('student',              (SELECT count(*) FROM app_user WHERE login_id LIKE 'seed.student.%')),
    ('admin',                (SELECT count(*) FROM app_user WHERE login_id IN ('seed.master','seed.admin.1','seed.admin.2'))),
    ('professor',            (SELECT count(*) FROM professor WHERE professor_id LIKE '9100000_')),
    ('topcit_exam_round',    (SELECT count(*) FROM topcit_exam_round WHERE round_name LIKE 'SEED_TOPCIT_%')),
    ('topcit_score',         (SELECT count(*) FROM topcit_score ts JOIN topcit_exam_round r USING (round_id) WHERE r.round_name LIKE 'SEED_TOPCIT_%')),
    ('program',              (SELECT count(*) FROM program WHERE program_name LIKE 'SEED %')),
    ('mileage_application',  (SELECT count(*) FROM mileage_application ma JOIN app_user u ON u.user_id=ma.student_no WHERE u.login_id LIKE 'seed.student.%')),
    ('attachment',           (SELECT count(*) FROM attachment WHERE file_path LIKE 'seed/mileage/%')),
    ('budget_project',       (SELECT count(*) FROM budget_project WHERE project_name LIKE 'SEED % SW중심대학사업')),
    ('initial_budget',       (SELECT count(*) FROM initial_budget ib JOIN budget_project bp USING(project_id) WHERE bp.project_name LIKE 'SEED % SW중심대학사업')),
    ('expenditure',          (SELECT count(*) FROM expenditure WHERE description LIKE 'SEED-%')),
    ('survey',               (SELECT count(*) FROM survey WHERE survey_name LIKE 'SEED % 만족도 조사')),
    ('survey_question',      (SELECT count(*) FROM survey_question q JOIN survey s USING(survey_id) WHERE s.survey_name LIKE 'SEED % 만족도 조사')),
    ('survey_response',      (SELECT count(*) FROM survey_response r JOIN survey s USING(survey_id) WHERE s.survey_name LIKE 'SEED % 만족도 조사')),
    ('survey_detail',        (SELECT count(*) FROM survey_response_detail d JOIN survey_response r USING(response_id) JOIN survey s USING(survey_id) WHERE s.survey_name LIKE 'SEED % 만족도 조사')),
    ('change_log',           (SELECT count(*) FROM seed_log))
) AS counts(entity, row_count)
ORDER BY entity;

\echo 'Seed verification passed.'
