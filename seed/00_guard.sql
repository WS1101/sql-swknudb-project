-- Seed는 psql에서 실행하며, 환경을 명시하지 않으면 아무 데이터도 변경하지 않는다.
\set ON_ERROR_STOP on
\if :{?seed_environment}
\else
\set seed_environment development
\endif

SELECT lower(:'seed_environment') IN ('development', 'test', 'local')
   AND current_database() !~* '(^|[_-])(prod|production)([_-]|$)'
   AS seed_environment_allowed \gset
\if :seed_environment_allowed
\else
\echo 'ERROR: seed execution is blocked outside development/test/local or on a production-named database'
DO $$ BEGIN RAISE EXCEPTION 'Seed guard rejected execution'; END $$;
\endif
