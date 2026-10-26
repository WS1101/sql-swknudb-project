-- =====================================================================
-- Q04_topcit_average.sql : TOPCIT 회차별·학과별·학년별 평균
-- 담당: 김건희
--
-- 목적
--   회차마다 전체 평균, 학과별 평균, 학년별 평균과 응시자 수를 한 번에 보여준다.
--
-- 입력
--   없음 (전체 회차)
--
-- 기준 (집계 단위)
--   - 회차 전체 : 해당 회차 응시자 전원
--   - 학과별    : 회차 × 응시 당시 학과 (dept_code_at_exam)
--   - 학년별    : 회차 × 응시 당시 학년 (grade_at_exam)
--   응시자 수 = 해당 단위의 점수 행 수. (student_no, round_id) UNIQUE이므로 학생 수와 같다.
--   현재 학과·학년이 아니라 응시 시점 스냅샷으로 묶으므로, 진급 후에도 과거 회차 집계가 바뀌지 않는다.
--   평균은 소수 첫째 자리 반올림.
--
-- 예상 결과
--   회차 전체
--     2025_1  23명  평균 304.3  최저 212  최고 400
--     2025_2  23명  평균 339.3  최저 247  최고 435
--     2026_1  32명  평균 404.0  최저 282  최고 526
--     2026_2  32명  평균 439.0  최저 317  최고 561
--   (2025 회차는 2026년 입학생 8명과 2026년 편입생 1명이 응시 전이라 23명)
--   학과별 2025_1: CS 6명 282.0 / SW 6명 298.0 / MATH 6명 314.0 / BIO 5명 327.2
--   학년별 2025_1: 1학년 8명 362.0 / 2학년 7명 300.6 / 3학년 8명 250.0
--   학과별 2026_2: CS 415.0 / SW 431.0 / MATH 447.0 / BIO 463.0 (각 8명)
--   학년별 2026_2: 1학년 523.0 / 2학년 467.0 / 3학년 411.0 / 4학년 355.0 (각 8명)
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\pset null '-'
\echo '=== Q04 TOPCIT 회차별·학과별·학년별 평균'

SELECT r.round_name                                     AS 회차,
       r.exam_date                                      AS 시험일,
       CASE WHEN GROUPING(d.dept_code) = 0      THEN '학과별'
            WHEN GROUPING(ts.grade_at_exam) = 0 THEN '학년별'
            ELSE '회차 전체' END                         AS 집계단위,
       d.dept_name                                      AS 응시학과,
       ts.grade_at_exam                                 AS 응시학년,
       count(*)                                         AS 응시자수,
       round(avg(ts.total_score), 1)                    AS 평균,
       min(ts.total_score)                              AS 최저,
       max(ts.total_score)                              AS 최고
  FROM topcit_score ts
  JOIN topcit_exam_round r ON r.round_id = ts.round_id
  JOIN department d        ON d.dept_code = ts.dept_code_at_exam
 GROUP BY GROUPING SETS (
       (r.round_id, r.round_name, r.exam_date),
       (r.round_id, r.round_name, r.exam_date, d.dept_code, d.dept_name),
       (r.round_id, r.round_name, r.exam_date, ts.grade_at_exam)
 )
 ORDER BY r.exam_date,
          r.round_id,
          CASE WHEN GROUPING(d.dept_code) = 0      THEN 1
               WHEN GROUPING(ts.grade_at_exam) = 0 THEN 2
               ELSE 0 END,
          d.dept_code,
          ts.grade_at_exam;
