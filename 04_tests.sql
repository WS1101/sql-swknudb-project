\encoding UTF8
-- =====================================================================
-- 04_tests.sql : 검증 테스트 전체 실행 (tests/ 파일을 순서대로 실행)
--   각 테스트는 자체 데이터를 만들고 ROLLBACK하므로 seed를 바꾸지 않는다.
--   하나씩 실행하려면: psql -d swknu_db -f tests/T01_duplicate_key.sql
--   reset.sql 실행 직후(seed 적용 상태)를 기준으로 한다.
-- =====================================================================
\ir tests/T01_duplicate_key.sql
\ir tests/T02_fk_violation.sql
\ir tests/T03_topcit_duplicate.sql
\ir tests/T04_range_violation.sql
\ir tests/T05_student_change_approval.sql
\ir tests/T06_mileage_approval.sql
\ir tests/T07_expenditure_approval.sql
\ir tests/T08_budget_limit.sql
\ir tests/T09_survey_range_duplicate.sql
\ir tests/T10_access_control.sql
\ir tests/T11_rollback.sql
\ir tests/T12_seed_integrity.sql
\ir tests/T13_analytics_access.sql
