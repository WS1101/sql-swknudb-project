\encoding UTF8
-- Q12_change_log.sql | 대상별 변경 이력과 대상·작업 유형별 로그 건수 조회.
-- 담당: 서우진
-- q12_target_type: 대상 테이블명(기본 student)
-- q12_target_id: 대상 PK 또는 ALL(기본 20230001)
-- 처리자·변경 전후 값·처리일시를 확인한다. CREATE의 이전 값은 NULL이다.
-- 예상 결과(초기 데이터 기준)
--   [1] 3행
--     2026-07-19 11:00  UPDATE  90000001 가상관리자한별
--        {"cumulative_mileage": 0} → {"cumulative_mileage": 60}     사유: 마일리지 신청 N 승인 반영 (SW 가치확산 활동 입상)
--     2026-09-02 09:00  UPDATE  90000002 가상관리자다온
--        {"phone_number": "000-0000-0001"} → {"phone_number": "000-0000-9001"}  사유: 변경 요청 1 승인 반영
--     2026-10-15 13:10  UPDATE  90000001 가상관리자한별
--        {"cumulative_mileage": 60} → {"cumulative_mileage": 310}   사유: 마일리지 신청 N 승인 반영 (TOPCIT)
--   [2] 전체 305건 (reset 직후)
--     expenditure                  CREATE 42 / APPROVE 19 / REJECT 9        소계 70
--     initial_budget               APPROVE 14                               소계 14
--     mileage_application          CREATE 84 / APPROVE 35 / REJECT 19 / CANCEL 15 / REVOKE 4   소계 157
--     student                      UPDATE 43 (학생정보 승인 4 + 마일리지 승인 35 + 회수 4)
--     student_info_change_request  CREATE 10 / APPROVE 4 / REJECT 3         소계 17
--     topcit_score                 UPDATE 4
--     (마일리지 APPROVE 35 = 현재 승인 31 + 승인 후 회수된 4)

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
