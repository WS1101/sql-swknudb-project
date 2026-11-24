\encoding UTF8
\set ON_ERROR_STOP on
-- reset_pbl3.sql : pbl3·pbl3_truth 삭제 → 생성 → 데이터 생성 → 분석 뷰 → 1·2번 분석 준비 → 검증
-- public(미션2)과 독립적이라 reset.sql 실행 여부와 관계없이 단독 실행 가능 (약 40초)
--   psql -d swknu_db -f pbl3/reset_pbl3.sql   (약 40초)
\ir 10_pbl3_schema.sql
\ir 11_pbl3_generate.sql
\ir 12_pbl3_views.sql
\ir 14_pbl3_survey_insight.sql
\ir 15_pbl3_participation.sql
\ir 16_pbl3_student_activity.sql
\ir 13_pbl3_verify.sql
