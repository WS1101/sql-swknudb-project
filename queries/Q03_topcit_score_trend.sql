\encoding UTF8
-- =====================================================================
-- Q03_topcit_score_trend.sql : 학생별 TOPCIT 회차별 점수 및 변화
-- 담당: 김건희
--
-- 목적
--   학생의 TOPCIT 점수를 시험일 순으로 나열하고, 직전 회차·첫 응시 대비 변화를 계산한다.
--
-- 입력
--   q03_student_no : 학번, 또는 ALL           기본 20230001
--
-- 기준
--   회차 순서: 해당 학생이 응시한 회차를 시험일(같으면 round_id) 순으로 1, 2, 3 ...
--   직전대비: 이번 점수 - 바로 앞 응시 점수 (첫 응시는 없음)
--   응시학년·응시학과: 응시 당시 스냅샷 (현재 학년이 아님)
--   정정여부: 점수가 수정된 적 있으면 true (updated_at 존재)
--
-- 예상 결과 (기본 입력)
--   4행
--   1  SEED_TOPCIT_2025_1  2025-05-17  3학년  컴퓨터공학과  345  직전 -    첫응시대비 0
--   2  SEED_TOPCIT_2025_2  2025-10-11  3학년                    380  +35        +35
--   3  SEED_TOPCIT_2026_1  2026-05-16  4학년                    465  +85        +120
--   4  SEED_TOPCIT_2026_2  2026-10-10  4학년                    500  +35        +155
--   (점수식 160 + 50×응시학년 + 35×회차순서 + 9×((순번-1)%4), 20230001은 순번 1)
--   정정 사례를 보려면 q03_student_no=20230003 (2026_2 회차 정정여부 true)
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q03_student_no}
\else
\set q03_student_no 20230001
\endif
\pset null '-'

\echo '=== Q03 TOPCIT 회차별 점수 변화 / 대상:' :q03_student_no

WITH score_history AS (
    SELECT ts.student_no,
           u.user_name,
           r.round_name,
           r.exam_date,
           ts.grade_at_exam,
           d.dept_name                              AS dept_at_exam,
           ts.total_score,
           (ts.updated_at IS NOT NULL)              AS corrected,
           row_number()  OVER w                     AS seq,
           lag(ts.total_score) OVER w               AS prev_score,
           first_value(ts.total_score) OVER w       AS first_score
      FROM topcit_score ts
      JOIN topcit_exam_round r ON r.round_id = ts.round_id
      JOIN app_user u          ON u.user_id = ts.student_no
      JOIN department d        ON d.dept_code = ts.dept_code_at_exam
    WINDOW w AS (PARTITION BY ts.student_no ORDER BY r.exam_date, r.round_id)
)
SELECT student_no                 AS 학번,
       user_name                  AS 성명,
       seq                        AS 응시순서,
       round_name                 AS 회차,
       exam_date                  AS 시험일,
       grade_at_exam              AS 응시학년,
       dept_at_exam               AS 응시학과,
       total_score                AS 총점,
       prev_score                 AS 직전점수,
       total_score - prev_score   AS 직전대비,
       total_score - first_score  AS 첫응시대비,
       corrected                  AS 정정여부
  FROM score_history
 WHERE :'q03_student_no' = 'ALL' OR student_no = :'q03_student_no'
 ORDER BY student_no, seq;
