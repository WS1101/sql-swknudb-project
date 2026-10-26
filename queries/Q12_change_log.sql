-- =====================================================================
-- Q12_change_log.sql : 대상별 변경·승인 로그 조회
-- 담당: 서우진
--
-- 목적
--   [1] 특정 대상(테이블 + PK)의 변경·승인 이력을 시간 순으로 보여준다.
--       대상·작업·처리자·일시·변경 전후 값·사유를 확인한다.
--   [2] 대상 유형·작업 유형별 로그 건수 요약
--
-- 입력
--   q12_target_type : 대상 테이블명            기본 student
--   q12_target_id   : 대상 PK 값, 또는 ALL     기본 20230001
--   예) 마일리지 신청 한 건:  -v q12_target_type=mileage_application -v q12_target_id=1
--       최초예산 한 건:       -v q12_target_type=initial_budget -v q12_target_id=1:1   (사업ID:항목ID)
--
-- 기준
--   - change_log.target_id는 FK가 없는 다형 참조 (원본이 삭제돼도 로그 보존)
--   - 처리자는 app_user FK가 보장되므로 INNER JOIN으로 이름을 붙인다
--   - 변경 전후 값: CREATE는 변경후에 생성된 행 전체, 그 외는 바뀐 항목만
--   - 일시는 한국 시간
--
-- 예상 결과 (기본 입력)
--   [1] 3행
--     2026-07-19 11:00  UPDATE  90000001 가상관리자한별
--        {"cumulative_mileage": 0} → {"cumulative_mileage": 60}     사유: 마일리지 신청 N 승인 반영 (전공 멘토링 입상)
--     2026-09-02 09:00  UPDATE  90000002 가상관리자다온
--        {"phone_number": "000-0000-0001"} → {"phone_number": "000-0000-9001"}  사유: 변경 요청 1 승인 반영
--     2026-10-15 13:10  UPDATE  90000001 가상관리자한별
--        {"cumulative_mileage": 60} → {"cumulative_mileage": 160}   사유: 마일리지 신청 N 승인 반영 (TOPCIT)
--   [2] 전체 305건 (reset 직후)
--     expenditure                  CREATE 42 / APPROVE 19 / REJECT 9        소계 70
--     initial_budget               APPROVE 14                               소계 14
--     mileage_application          CREATE 84 / APPROVE 35 / REJECT 19 / CANCEL 15 / REVOKE 4   소계 157
--     student                      UPDATE 43 (학생정보 승인 4 + 마일리지 승인 35 + 회수 4)
--     student_info_change_request  CREATE 10 / APPROVE 4 / REJECT 3         소계 17
--     topcit_score                 UPDATE 4
--     (마일리지 APPROVE 35 = 현재 승인 31 + 승인 후 회수된 4)
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q12_target_type}
\else
\set q12_target_type student
\endif
\if :{?q12_target_id}
\else
\set q12_target_id 20230001
\endif
\pset null '-'

\echo '=== Q12 변경·승인 로그 / 대상:' :q12_target_type :q12_target_id

-- [1] 대상별 이력
SELECT l.log_id                                     AS 로그id,
       (l.processed_at AT TIME ZONE 'Asia/Seoul')   AS 처리일시,
       l.target_type                                AS 대상,
       l.target_id                                  AS 대상id,
       l.action_type                                AS 작업,
       CASE l.action_type
            WHEN 'CREATE'  THEN '등록'
            WHEN 'UPDATE'  THEN '수정'
            WHEN 'APPROVE' THEN '승인'
            WHEN 'REJECT'  THEN '반려'
            WHEN 'CANCEL'  THEN '취소'
            WHEN 'DELETE'  THEN '삭제'
            WHEN 'REVOKE'  THEN '회수' END          AS 작업명,
       l.processed_by                               AS 처리자id,
       u.user_name                                  AS 처리자,
       u.user_type                                  AS 처리자유형,
       l.before_value                               AS 변경전,
       l.after_value                                AS 변경후,
       l.reason                                     AS 사유
  FROM change_log l
  JOIN app_user u ON u.user_id = l.processed_by
 WHERE l.target_type = :'q12_target_type'
   AND (:'q12_target_id' = 'ALL' OR l.target_id = :'q12_target_id')
 ORDER BY l.processed_at, l.log_id;

-- [2] 대상 유형·작업별 건수
SELECT COALESCE(target_type, '◆ 전체')                         AS 대상,
       CASE WHEN GROUPING(action_type) = 1 AND GROUPING(target_type) = 0
            THEN '소계' ELSE action_type END                     AS 작업,
       count(*)                                                  AS 건수,
       min(processed_at AT TIME ZONE 'Asia/Seoul')               AS 최초,
       max(processed_at AT TIME ZONE 'Asia/Seoul')               AS 최근
  FROM change_log
 GROUP BY GROUPING SETS ((target_type, action_type), (target_type), ())
 ORDER BY GROUPING(target_type), target_type, GROUPING(action_type), action_type;
