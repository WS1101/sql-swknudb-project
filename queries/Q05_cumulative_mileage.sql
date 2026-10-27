\encoding UTF8
-- =====================================================================
-- Q05_cumulative_mileage.sql : 학생별 누적 마일리지
-- 담당: 김건희
--
-- 목적
--   학생별 누적 마일리지를 승인 내역에서 다시 계산하고, 저장된 캐시값
--   (student.cumulative_mileage)과 일치하는지 함께 보여준다.
--
-- 입력
--   q05_student_no : 학번, 또는 ALL           기본 ALL
--
-- 기준
--   - 집계 대상: status = 'APPROVED' 만. 대기·반려·취소·회수는 제외 (회수는 상태가 REVOKED로 바뀜)
--   - 금액: requested_mileage (신청 시점 기준표 값, 보고서 4.3 스냅샷)
--   - 미적립 학생도 표시: student 기준 LEFT JOIN, 없으면 0
--   - 승인 내역을 학생별로 먼저 합산한 뒤 JOIN → 다른 상세 테이블과 곱해져 합계가 부풀지 않음
--
-- 예상 결과 (기본 입력)
--   32행, 승인합계 전체 2,475 (프로그램 1,875 + TOPCIT 600), 모든 행 일치 = true
--   0점(미적립) 10명: 20230003, 20230004, 20230008, 20240015, 20250019,
--                     20250020, 20250023, 20250024, 20260025, 20260028
--   상위: 20250017 250 / 20230002 185 / 20250022 185 / 20240013 180 / 20230001 160
--   [2] 요약: 학생 32, 적립 22, 미적립 10, 승인합계 2,475, 저장합계 2,475, 불일치 0
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q05_student_no}
\else
\set q05_student_no ALL
\endif
\pset null '-'

\echo '=== Q05 학생별 누적 마일리지 / 대상:' :q05_student_no

-- [1] 학생별
WITH approved AS (
    SELECT student_no,
           sum(requested_mileage) FILTER (WHERE source_type = 'PROGRAM') AS program_mileage,
           sum(requested_mileage) FILTER (WHERE source_type = 'TOPCIT')  AS topcit_mileage,
           sum(requested_mileage)                                        AS total_mileage,
           count(*)                                                      AS approved_count
      FROM mileage_application
     WHERE status = 'APPROVED'
     GROUP BY student_no
)
SELECT s.student_no                                      AS 학번,
       u.user_name                                       AS 성명,
       d.dept_name                                       AS 학과,
       s.grade                                           AS 학년,
       COALESCE(a.program_mileage, 0)                    AS 프로그램,
       COALESCE(a.topcit_mileage, 0)                     AS topcit,
       COALESCE(a.total_mileage, 0)                      AS 승인합계,
       COALESCE(a.approved_count, 0)                     AS 승인건수,
       s.cumulative_mileage                              AS 저장값,
       (COALESCE(a.total_mileage, 0) = s.cumulative_mileage) AS 일치
  FROM student s
  JOIN app_user u       ON u.user_id = s.student_no
  JOIN department d     ON d.dept_code = s.dept_code
  LEFT JOIN approved a  ON a.student_no = s.student_no
 WHERE :'q05_student_no' = 'ALL' OR s.student_no = :'q05_student_no'
 ORDER BY COALESCE(a.total_mileage, 0) DESC, s.student_no;

-- [2] 요약 (검증용)
WITH approved AS (
    SELECT student_no, sum(requested_mileage) AS total_mileage
      FROM mileage_application
     WHERE status = 'APPROVED'
     GROUP BY student_no
)
SELECT count(*)                                                        AS 학생수,
       count(*) FILTER (WHERE COALESCE(a.total_mileage, 0) > 0)        AS 적립학생,
       count(*) FILTER (WHERE COALESCE(a.total_mileage, 0) = 0)        AS 미적립학생,
       sum(COALESCE(a.total_mileage, 0))                               AS 승인합계,
       sum(s.cumulative_mileage)                                       AS 저장합계,
       count(*) FILTER (WHERE COALESCE(a.total_mileage, 0) <> s.cumulative_mileage) AS 불일치
  FROM student s
  LEFT JOIN approved a ON a.student_no = s.student_no
 WHERE :'q05_student_no' = 'ALL' OR s.student_no = :'q05_student_no';
