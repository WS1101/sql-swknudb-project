-- reset.sql : 로컬 DB를 비우고 스키마 생성 + 정상 데이터 입력
-- 로컬 전용. 공용 DB에서 실행 금지
-- 실행: psql -U postgres -d pbl_db -f reset.sql
\encoding UTF8
\set ON_ERROR_STOP on

DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

\ir 01_schema.sql
\ir 02_seed.sql
