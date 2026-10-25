-- reset.sql : 로컬 DB를 비우고 스키마 생성 + 정상 데이터 입력
-- 로컬 전용. 공용 DB에서 실행 금지
-- 실행: psql -U postgres -d pbl_db -f reset.sql
\encoding UTF8
\set ON_ERROR_STOP on

-- public 스키마 전체 삭제는 명시적인 로컬 초기화 확인값이 있어야만 실행한다.
\if :{?reset_confirm}
\else
\set reset_confirm RESET_LOCAL_DB
\endif
\if :{?seed_environment}
\else
\set seed_environment development
\endif
SELECT :'reset_confirm' = 'RESET_LOCAL_DB'
   AND lower(:'seed_environment') IN ('development', 'test', 'local')
   AND current_database() !~* '(^|[_-])(prod|production)([_-]|$)'
   AS reset_allowed \gset
\if :reset_allowed
\else
\echo 'ERROR: reset is allowed only for an explicitly confirmed non-production database'
DO $$ BEGIN RAISE EXCEPTION 'Reset guard rejected execution'; END $$;
\endif

DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

\ir 01_schema.sql
\ir 02_seed.sql
