\encoding UTF8
-- =====================================================================
-- Q02_student_change_history.sql : 학생정보 수정 요청과 처리 이력 조회
-- 담당: 서우진
--
-- 목적
--   학생정보 변경 요청의 기존 값·변경 값·상태·처리자를 조회하고,
--   승인된 요청만 학생 기본정보에 반영되었는지 현재 값과 비교한다.
--   이어서 change_log에서 요청 생성·승인·반려와 학생정보 변경 이력을 시간 순으로 보여준다.
--
-- 입력
--   q02_student_no : 학번, 또는 ALL (전체)       기본 20230001
--
-- 기준
--   상태: PENDING 대기 / APPROVED 승인 / REJECTED 반려
--   현재값: student 테이블의 지금 값. 승인 건은 이후 다른 변경이 없으면 변경값과 같고,
--           대기·반려 건은 기존값과 같아야 한다 (반영 안 됨).
--
-- 예상 결과 (기본 입력, reset 직후. 요청ID는 reset 직후 기준)
--   [1] 3행 (요청일시 순)
--     1  phone_number  000-0000-0001 → 000-0000-9001  승인  처리자 90000002 가상관리자다온  9/2 09:00
--        'SEED: 연락처 변경 확인'           현재값 000-0000-9001
--     6  phone_number  000-0000-9001 → 000-0000-9101  반려  처리자 90000003 가상관리자라온  10/3 09:00
--        'SEED: 재변경 사유 확인 필요'      현재값 000-0000-9001 (= 기존값, 미반영)
--     8  email  student01@example.invalid → student01.pending@example.invalid  대기  처리자 없음
--                                           현재값 student01@example.invalid (= 기존값, 미반영)
--   [2] 6행
--     9/1  CREATE  (요청 1, 처리자 20230001)
--     9/2  APPROVE (요청 1) before {"status":"PENDING"}
--     9/2  UPDATE  (student) {"phone_number":"000-0000-0001"} → {"phone_number":"000-0000-9001"}
--     10/2 CREATE  (요청 6)
--     10/3 REJECT  (요청 6)
--     10/13 CREATE (요청 8)
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q02_student_no}
\else
\set q02_student_no 20230001
\endif
\pset null '-'

\echo '=== Q02 학생정보 수정 요청·처리 이력 / 대상:' :q02_student_no

-- [1] 요청과 처리 결과
SELECT r.request_id                                   AS 요청id,
       r.student_no                                   AS 학번,
       su.user_name                                   AS 성명,
       r.field_name                                   AS 요청항목,
       r.old_value                                    AS 기존값,
       r.new_value                                    AS 변경값,
       CASE r.status WHEN 'PENDING'  THEN '대기'
                     WHEN 'APPROVED' THEN '승인'
                     WHEN 'REJECTED' THEN '반려' END  AS 상태,
       (r.requested_at AT TIME ZONE 'Asia/Seoul')     AS 요청일시,
       r.processed_by                                 AS 처리자id,
       pu.user_name                                   AS 처리자,
       (r.processed_at AT TIME ZONE 'Asia/Seoul')     AS 처리일시,
       r.comment                                      AS 처리의견,
       to_jsonb(s) ->> r.field_name                   AS 현재값
  FROM student_info_change_request r
  JOIN student s        ON s.student_no = r.student_no
  JOIN app_user su      ON su.user_id = r.student_no
  LEFT JOIN app_user pu ON pu.user_id = r.processed_by
 WHERE :'q02_student_no' = 'ALL' OR r.student_no = :'q02_student_no'
 ORDER BY r.student_no, r.requested_at, r.request_id;

-- [2] 처리 이력 (change_log)
SELECT l.log_id                                   AS 로그id,
       (l.processed_at AT TIME ZONE 'Asia/Seoul') AS 처리일시,
       l.target_type                              AS 대상,
       l.target_id                                AS 대상id,
       l.action_type                              AS 작업,
       l.processed_by                             AS 처리자id,
       u.user_name                                AS 처리자,
       l.before_value                             AS 변경전,
       l.after_value                              AS 변경후,
       l.reason                                   AS 사유
  FROM change_log l
  JOIN app_user u ON u.user_id = l.processed_by
 WHERE (    l.target_type = 'student_info_change_request'
        AND EXISTS (SELECT 1 FROM student_info_change_request r
                     WHERE r.request_id::text = l.target_id
                       AND (:'q02_student_no' = 'ALL' OR r.student_no = :'q02_student_no')))
    OR (    l.target_type = 'student'
        AND l.reason LIKE '변경 요청 %'
        AND (:'q02_student_no' = 'ALL' OR l.target_id = :'q02_student_no'))
 ORDER BY l.processed_at, l.log_id;
