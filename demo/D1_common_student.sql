-- =====================================================================
-- D1_common_student.sql : 공통·학생 시연 (서우진)
-- 실행: psql -d swknu_demo -f demo/D1_common_student.sql
-- 전체가 BEGIN … ROLLBACK 이라 실행 후 데이터는 그대로다.
-- =====================================================================
\ir _setup.sql
BEGIN;

\echo ''
\echo '========== [1] 이미 있는 학번으로 사용자 등록 → PK가 막아야 함 =========='
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type)
VALUES ('20230001', 'demo.dup', 'x', '중복학생', 'STUDENT');

\echo ''
\echo '========== [2] 이미 있는 로그인 ID → UNIQUE가 막아야 함 =========='
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type)
VALUES ('99990000', 'seed.student.01', 'x', '중복로그인', 'STUDENT');

\echo ''
\echo '========== [3] 학생 계정을 관리자로 등록 → 복합 FK가 막아야 함 (학생·관리자 배타성) =========='
INSERT INTO admin (staff_no) VALUES ('20230001');

\echo ''
\echo '========== [4] 학년을 5로 → CHECK(1~4)가 막아야 함 =========='
UPDATE student SET grade = 5 WHERE student_no = '20230001';

\echo ''
\echo '--- 확인: 20230001은 그대로 (4학년, 사용자 1명)'
SELECT s.student_no, u.user_name, s.grade,
       (SELECT count(*) FROM app_user WHERE user_id = '20230001') AS 사용자수
  FROM student s JOIN app_user u ON u.user_id = s.student_no
 WHERE s.student_no = '20230001';

\echo ''
\echo '========== [5] 학생정보 변경 요청 승인 전후 =========='
\echo '--- 대기 중인 이메일 변경 요청'
SELECT request_id, old_value, new_value, status
  FROM student_info_change_request
 WHERE student_no = '20230001' AND field_name = 'email' AND status = 'PENDING';
SELECT request_id AS req
  FROM student_info_change_request
 WHERE student_no = '20230001' AND field_name = 'email' AND status = 'PENDING' \gset

\echo '--- 대기 중인 이메일 요청이 있는데 또 요청 → 부분 UNIQUE가 막아야 함'
SELECT fn_create_student_info_change_request('20230001', 'email', 'again@example.invalid');

\echo '--- 학생(20230002)이 승인 시도 → 관리자가 아니라 거부'
SELECT fn_approve_student_info_change(:req, '20230002');

\echo '--- [승인 전] 이메일'
SELECT student_no, email FROM student WHERE student_no = '20230001';

\echo '--- 일반관리자 90000002가 승인'
SELECT fn_approve_student_info_change(:req, '90000002', '시연 승인');

\echo '--- [승인 후] 이메일 변경, 요청 APPROVED'
SELECT student_no, email FROM student WHERE student_no = '20230001';
SELECT request_id, status, processed_by FROM student_info_change_request WHERE request_id = :req;

\echo '--- 로그 2건: 요청 승인 + 학생 정보 변경 (바뀐 항목만)'
SELECT target_type, target_id, action_type, before_value, after_value
  FROM change_log ORDER BY log_id DESC LIMIT 2;

\echo '--- 같은 요청 재승인 → 이중 처리 방지'
SELECT fn_approve_student_info_change(:req, '90000002');

\echo ''
\echo '========== [6] 승인 중 실패 → 아무것도 바뀌지 않아야 함 (롤백) =========='
\echo '--- 잘못된 이메일로 요청 (요청 접수는 됨)'
SELECT fn_create_student_info_change_request('20230004', 'email', 'invalid-email') AS bad \gset

\echo '--- 승인 시도 → 학생 이메일 CHECK 위반으로 실패'
SELECT fn_approve_student_info_change(:bad, '90000002');

\echo '--- 확인: 요청은 PENDING, 이메일 그대로, 승인 로그 0건'
SELECT r.status, s.email,
       (SELECT count(*) FROM change_log
         WHERE target_type = 'student_info_change_request'
           AND target_id = :'bad' AND action_type = 'APPROVE') AS 승인로그
  FROM student_info_change_request r JOIN student s ON s.student_no = r.student_no
 WHERE r.request_id = :bad;

\echo ''
\echo '========== [7] 변경 로그 삭제 → 트리거가 막아야 함 =========='
DELETE FROM change_log WHERE log_id = 1;

ROLLBACK;
\echo ''
\echo '========== 시연 끝: ROLLBACK으로 seed 데이터는 그대로 =========='
