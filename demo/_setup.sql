-- 시연 스크립트 공통 설정 (각 시연 파일이 맨 위에서 \ir 로 불러온다)
--   실패한 문장만 취소하고 계속 진행, 실행하는 SQL을 화면에 출력, 넘김 화면 끄기
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
\set ECHO queries
\pset pager off
\pset null '-'
\encoding UTF8
