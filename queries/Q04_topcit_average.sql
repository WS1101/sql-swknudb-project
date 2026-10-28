\encoding UTF8
-- Q04_topcit_average.sql | TOPCIT 회차 전체, 학과별, 학년별 평균과 응시자 수 조회.
-- 담당: 김건희
-- 응시 당시 학과·학년으로 집계하고, 평균은 소수 첫째 자리까지 표시한다.
-- 예상 결과(초기 데이터 기준)
--   회차 전체
--     2025_1  23명  평균 307.9  최저 245  최고 372
--     2025_2  23명  평균 342.9  최저 280  최고 407
--     2026_1  32명  평균 403.5  최저 315  최고 492
--     2026_2  32명  평균 438.5  최저 350  최고 527
--   (2025 회차는 2026년 입학생 8명과 2026년 편입생 1명이 응시 전이라 23명)
--   학과별 2025_1: CS 6명 295.0 / SW 6명 304.0 / SIT 6명 313.0 / AI 5명 312.0
--   학년별 2025_1: 1학년 8명 258.5 / 2학년 7명 306.6 / 3학년 8명 358.5
--   학과별 2026_2: CS 425.0 / SW 434.0 / SIT 443.0 / AI 452.0 (각 8명)
--   학년별 2026_2: 1학년 363.5 / 2학년 413.5 / 3학년 463.5 / 4학년 513.5 (각 8명)

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
