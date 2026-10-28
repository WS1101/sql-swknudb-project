\encoding UTF8
-- Q05_cumulative_mileage.sql | 승인된 신청 합계와 학생 테이블의 누적 마일리지를 비교한다.
-- 담당: 김건희
-- q05_student_no: 학번 또는 ALL(기본 ALL)
-- APPROVED만 합산한다. 적립 이력이 없는 학생은 LEFT JOIN으로 포함한다.
-- 예상 결과(초기 데이터 기준)
--   32행, 승인합계 전체 2,825 (프로그램 1,875 + TOPCIT 950), 모든 행 일치 = true
--   0점(미적립) 10명: 20230003, 20230004, 20230008, 20240015, 20250019,
--                     20250020, 20250023, 20250024, 20260025, 20260028
--   상위: 20230001 310 / 20230005 275 / 20250017 250 / 20230002 185 / 20250022 185
--   [2] 요약: 학생 32, 적립 22, 미적립 10, 승인합계 2,825, 저장합계 2,825, 불일치 0

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
