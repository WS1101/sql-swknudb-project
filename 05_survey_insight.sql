\encoding UTF8
\set ON_ERROR_STOP on
-- 기본판: 기존 01_schema.sql 실행 후 적용. 출석 테이블 없이 실행 가능.
-- 출석·재참여는 필요할 때 06_survey_participation.sql로 별도 적용.
\ir schema/10_survey_insight.sql
