-- =====================================================================
-- D3_budget_survey.sql : 예산·만족도 시연 (임영효)
-- 실행: psql -d swknu_demo -f demo/D3_budget_survey.sql
-- 전체가 BEGIN … ROLLBACK 이라 실행 후 데이터는 그대로다.
-- =====================================================================
\ir _setup.sql
BEGIN;

SELECT project_id AS p FROM budget_project WHERE project_year = 2026 \gset
SELECT budget_item_id AS i FROM budget_item WHERE item_code = 'INDIRECT' \gset

\echo ''
\echo '========== [1] 지출금액 0원 → CHECK(amount > 0)가 막아야 함 =========='
INSERT INTO expenditure (project_id, budget_item_id, expenditure_date, subject_type_code,
                         professor_id, amount, description, created_by)
VALUES (:p, :i, '2026-11-01', 'MAJOR', '91000001', 0, '시연', '90000001');

\echo ''
\echo '========== [2] 지출한도를 최초예산보다 크게 → CHECK가 막아야 함 =========='
UPDATE initial_budget SET expenditure_limit = initial_amount + 1
 WHERE project_id = :p AND budget_item_id = :i;

\echo ''
\echo '========== [3] 사업에 배정되지 않은 항목으로 지출 → 복합 FK가 막아야 함 =========='
INSERT INTO expenditure (project_id, budget_item_id, expenditure_date, subject_type_code,
                         professor_id, amount, description, created_by)
VALUES (-1, -1, '2026-11-01', 'MAJOR', '91000001', 1000, '시연', '90000001');

\echo ''
\echo '========== [4] 지출 승인 전후 집계 (2026 간접비: 예산 45,000,000 / 한도 42,000,000) =========='
\echo '--- [승인 전] 승인 지출 0, 잔액 = 예산, 집행률 0'
SELECT ib.initial_amount AS 예산, ib.expenditure_limit AS 한도,
       COALESCE(sum(e.amount), 0) AS 승인지출,
       ib.initial_amount - COALESCE(sum(e.amount), 0) AS 잔액,
       round(100.0 * COALESCE(sum(e.amount), 0) / NULLIF(ib.initial_amount, 0), 2) AS 집행률
  FROM initial_budget ib
  LEFT JOIN expenditure e ON e.project_id = ib.project_id
                         AND e.budget_item_id = ib.budget_item_id AND e.status = 'APPROVED'
 WHERE ib.project_id = :p AND ib.budget_item_id = :i
 GROUP BY ib.initial_amount, ib.expenditure_limit;

\echo '--- 38,000,000원 지출 등록 → 승인 (한도 90% 이상이라 경고 후 승인)'
SELECT fn_create_expenditure(:p, :i, '2026-11-02', 'MAJOR', '91000001',
                             38000000, '시연: 장비 구입', '90000001') AS e1 \gset
SELECT fn_approve_expenditure(:e1, '90000001');

\echo '--- [승인 후] 승인 38,000,000, 잔액·집행률 자동 계산'
SELECT ib.initial_amount AS 예산, ib.expenditure_limit AS 한도,
       COALESCE(sum(e.amount), 0) AS 승인지출,
       ib.initial_amount - COALESCE(sum(e.amount), 0) AS 잔액,
       round(100.0 * COALESCE(sum(e.amount), 0) / NULLIF(ib.initial_amount, 0), 2) AS 집행률
  FROM initial_budget ib
  LEFT JOIN expenditure e ON e.project_id = ib.project_id
                         AND e.budget_item_id = ib.budget_item_id AND e.status = 'APPROVED'
 WHERE ib.project_id = :p AND ib.budget_item_id = :i
 GROUP BY ib.initial_amount, ib.expenditure_limit;

\echo ''
\echo '========== [5] 5,000,000원 추가 → 43,000,000 > 한도 42,000,000 =========='
SELECT fn_create_expenditure(:p, :i, '2026-11-03', 'MAJOR', '91000001',
                             5000000, '시연: 추가 지출', '90000001') AS e2 \gset

\echo '--- 일반관리자 90000002가 승인 시도 → 지출 처리 권한 없음'
SELECT fn_approve_expenditure(:e2, '90000002');

\echo '--- 마스터관리자 승인 시도 → 한도 초과로 차단'
SELECT fn_approve_expenditure(:e2, '90000001');

\echo '--- 확인: 추가 지출은 PENDING, 승인 합계는 38,000,000 그대로'
SELECT expenditure_id, amount, status FROM expenditure WHERE expenditure_id IN (:e1, :e2);

\echo ''
\echo '========== [6] 만족도 응답 검증 =========='
INSERT INTO survey_response (survey_id, student_no)
VALUES ((SELECT min(survey_id) FROM survey), '20230001')
RETURNING response_id AS r \gset

SELECT question_id AS q_scale FROM survey_question
 WHERE survey_id = (SELECT min(survey_id) FROM survey) AND display_order = 1 \gset
SELECT question_id AS q_text FROM survey_question
 WHERE survey_id = (SELECT min(survey_id) FROM survey) AND question_type = 'TEXT' \gset

\echo '--- 척도 문항에 0점 → CHECK(1~5)가 막아야 함'
INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (:r, :q_scale, 0);

\echo '--- 척도 문항에 의견만 → 문항 유형 불일치로 막아야 함'
INSERT INTO survey_response_detail (response_id, question_id, text_answer) VALUES (:r, :q_scale, '좋음');

\echo '--- 주관식 문항에 점수 → 문항 유형 불일치로 막아야 함'
INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (:r, :q_text, 3);

\echo '--- 척도 1번만 답하고 완료 처리 → 전 문항 미응답이라 막아야 함'
INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (:r, :q_scale, 5);
UPDATE survey_response SET is_completed = true WHERE response_id = :r;

\echo '--- 이미 완료된 응답의 점수 수정 → 막아야 함'
UPDATE survey_response_detail SET score = 5
 WHERE response_id = (SELECT min(response_id) FROM survey_response WHERE is_completed);

ROLLBACK;
\echo ''
\echo '========== 시연 끝: ROLLBACK으로 seed 데이터는 그대로 =========='
