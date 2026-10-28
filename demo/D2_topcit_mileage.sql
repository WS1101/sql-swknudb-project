-- D2_topcit_mileage.sql : TOPCIT·마일리지 시연 (김건희)
-- 실행: psql -d swknu_demo -f demo/D2_topcit_mileage.sql
-- 시연 데이터는 마지막 ROLLBACK으로 되돌린다.

\ir _setup.sql
BEGIN;

\echo ''
\echo '========== [1] 같은 학생·같은 회차 점수 재등록 → UNIQUE가 막아야 함 =========='
INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
SELECT '20230001', round_id, 500, '90000001'
  FROM topcit_exam_round WHERE round_name = 'SEED_TOPCIT_2026_2';

\echo ''
\echo '========== [2] 점수를 1001로 → CHECK(0~1000)가 막아야 함 =========='
UPDATE topcit_score SET total_score = 1001
 WHERE student_no = '20230001'
   AND round_id = (SELECT round_id FROM topcit_exam_round WHERE round_name = 'SEED_TOPCIT_2026_2');

\echo ''
\echo '========== [3] 기존 구간과 겹치는 마일리지 구간 → EXCLUDE가 막아야 함 =========='
INSERT INTO topcit_mileage_criteria (min_score, max_score, mileage_awarded) VALUES (100, 200, 40);

\echo ''
\echo '--- 확인: 20230001 점수와 구간 그대로'
SELECT r.round_name, ts.total_score
  FROM topcit_score ts JOIN topcit_exam_round r ON r.round_id = ts.round_id
 WHERE ts.student_no = '20230001' ORDER BY r.exam_date;

\echo ''
\echo '========== [4] 마일리지 승인 전후 (20230001 해커톤 참여 신청) =========='
SELECT application_id AS app FROM mileage_application
 WHERE student_no = '20230001' AND status = 'PENDING' AND source_type = 'PROGRAM' \gset

\echo '--- [승인 전] 신청 상태와 누적 마일리지'
SELECT application_id, status, requested_mileage FROM mileage_application WHERE application_id = :app;
SELECT student_no, cumulative_mileage FROM student WHERE student_no = '20230001';

\echo '--- 일반관리자 90000002가 승인 시도 → 마일리지 처리 권한 없음'
SELECT fn_approve_mileage_application(:app, '90000002');

\echo '--- 마스터관리자 90000001이 승인'
SELECT fn_approve_mileage_application(:app, '90000001', '시연 승인');

\echo '--- [승인 후] APPROVED, 누적 +40'
SELECT application_id, status, approved_by FROM mileage_application WHERE application_id = :app;
SELECT student_no, cumulative_mileage FROM student WHERE student_no = '20230001';

\echo '--- 로그 2건: 신청 승인 + 누적 마일리지 변경'
SELECT target_type, target_id, action_type, before_value, after_value
  FROM change_log ORDER BY log_id DESC LIMIT 2;

\echo '--- 같은 신청 재승인 → 이중 적립 방지'
SELECT fn_approve_mileage_application(:app, '90000001');

\echo ''
\echo '========== [5] 이미 승인된 프로그램에 또 신청 → 중복 신청 차단 =========='
SELECT fn_create_mileage_application('20230001', 'PROGRAM', '20230001', 'STUDENT_REQUEST',
       (SELECT program_id FROM mileage_application WHERE application_id = :app),
       NULL, 'PARTICIPATION');

\echo ''
\echo '========== [6] 다른 학생 명의로 신청 → 본인 명의만 가능 =========='
SELECT fn_create_mileage_application('20230001', 'PROGRAM', '20230002', 'STUDENT_REQUEST',
       (SELECT program_id FROM program WHERE program_name = 'SEED AI 집중교육'),
       NULL, 'PARTICIPATION');

\echo ''
\echo '--- 확인: 누적 마일리지 = 승인 신청 합계'
SELECT s.cumulative_mileage AS 저장값,
       (SELECT sum(requested_mileage) FROM mileage_application
         WHERE student_no = '20230001' AND status = 'APPROVED') AS 승인합계
  FROM student s WHERE s.student_no = '20230001';

ROLLBACK;
\echo ''
\echo '========== 시연 끝: ROLLBACK으로 seed 데이터는 그대로 =========='
