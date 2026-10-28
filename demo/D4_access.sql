-- D4_access.sql : 조회 범위와 분석 계정 권한 시연 (서우진, Wrap-up)
-- 실행: psql -d swknu_demo -f demo/D4_access.sql
-- SET ROLE 검사는 관리자 권한으로 실행한다.

\ir _setup.sql
BEGIN;

\echo ''
\echo '========== [1] 분석 계정으로 전환 =========='
SET LOCAL ROLE analytics_reader;
SELECT current_user;

\echo ''
\echo '--- 분석 뷰는 조회됨 (이름·연락처 없음)'
SELECT student_no, dept_name, grade, approved_mileage, topcit_latest_score, avg_satisfaction
  FROM analytics.v_student_features ORDER BY student_no LIMIT 5;

\echo ''
\echo '--- 학생 연락처 직접 조회 → 권한 없음'
SELECT student_no, phone_number, email FROM public.student LIMIT 1;

\echo '--- 계정·비밀번호 해시 조회 → 권한 없음'
SELECT login_id, password_hash FROM public.app_user LIMIT 1;

\echo '--- 변경 로그 조회 → 권한 없음'
SELECT * FROM public.change_log LIMIT 1;

RESET ROLE;
\echo ''
\echo '========== [2] 원래 계정으로 복귀 =========='
SELECT current_user;

ROLLBACK;
\echo ''
\echo '========== 시연 끝 =========='
