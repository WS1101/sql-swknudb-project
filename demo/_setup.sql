-- 시연용 psql 설정
-- 오류가 난 문장만 롤백하고 SQL 출력 및 pager를 설정한다.
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
\set ECHO queries
\pset pager off
\pset null '-'
\encoding UTF8
