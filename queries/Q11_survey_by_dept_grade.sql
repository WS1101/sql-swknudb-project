\encoding UTF8
-- =====================================================================
-- Q11_survey_by_dept_grade.sql : 학과별·학년별 만족도 결과 및 의견
-- 담당: 임영효
--
-- 목적
--   [1] 척도 문항 점수를 학과·학년별로 집계한다 (숫자).
--   [2] 주관식 의견을 학과·학년별로 보여준다 (텍스트).
--   숫자 평균과 주관식 의견은 성격이 달라 분리해서 조회한다.
--
-- 입력
--   q11_min_group : 의견 공개 최소 응답자 수   기본 3
--
-- 기준
--   - Q10과 같은 완료 응답 기준: 학생·조사별 최신 완료 응답 1건
--   - 학과·학년: 응답 당시 스냅샷 (dept_code_at_response, grade_at_response)
--   - [1] 응답자수 = 최종 응답 수, 점수응답수 = 척도 문항 답변 수, 평균 = 척도 점수 평균
--         학과×학년, 학과 소계, 학년 소계, 전체를 GROUPING SETS로 함께 표시
--   - 개인정보 노출 최소화
--       · 학번·성명·연락처를 출력하지 않는다
--       · [2]에서 같은 조사·학과·학년 응답자가 q11_min_group 미만이면 학과·학년을 가린다
--         (소수 집단은 학과+학년만으로 누가 썼는지 추정될 수 있음)
--       · 같은 내용의 의견은 묶어서 건수로 보여준다
--
-- 예상 결과
--   [1] 학과×학년 16칸 모두 응답자 8, 점수응답수 24
--       학과 소계: CS 3.01 / SW 2.98 / MATH 2.98 / BIO 3.01 (각 응답자 32, 점수 96)
--       학년 소계: 1학년 2.99 / 2학년 3.00 / 3학년 3.01 / 4학년 2.98 (각 32, 96)
--       전체: 응답자 128, 점수응답수 384, 평균 2.99
--   [2] 의견 4종류, 최종 응답 128건 (미완료·이전 응답의 의견은 제외)
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q11_min_group}
\else
\set q11_min_group 3
\endif
\pset null '-'

\echo '=== Q11 학과별·학년별 만족도 / 의견 공개 최소 응답자:' :q11_min_group

-- [1] 척도 점수 (숫자)
WITH final_response AS (
    SELECT DISTINCT ON (r.survey_id, r.student_no)
           r.response_id, r.survey_id,
           r.dept_code_at_response AS dept_code,
           r.grade_at_response     AS grade
      FROM survey_response r
     WHERE r.is_completed
     ORDER BY r.survey_id, r.student_no, r.responded_at DESC, r.response_id DESC
), scored AS (
    SELECT f.response_id, f.dept_code, f.grade, d.score
      FROM final_response f
      JOIN survey_response_detail d ON d.response_id = f.response_id
      JOIN survey_question q        ON q.question_id = d.question_id
     WHERE q.question_type = 'SCALE'
)
SELECT CASE
           WHEN GROUPING(sc.dept_code) = 0 AND GROUPING(sc.grade) = 0 THEN '학과×학년'
           WHEN GROUPING(sc.dept_code) = 0                            THEN '학과 소계'
           WHEN GROUPING(sc.grade) = 0                                THEN '학년 소계'
           ELSE '전체'
       END                                AS 집계단위,
       dp.dept_name                       AS 학과,
       sc.grade                           AS 학년,
       count(DISTINCT sc.response_id)     AS 응답자수,
       count(sc.score)                    AS 점수응답수,
       round(avg(sc.score), 2)            AS 평균,
       round(100.0 * count(*) FILTER (WHERE sc.score >= 4) / NULLIF(count(sc.score), 0), 1) AS 만족비율
  FROM scored sc
  JOIN department dp ON dp.dept_code = sc.dept_code
 GROUP BY GROUPING SETS (
       (sc.dept_code, dp.dept_name, sc.grade),
       (sc.dept_code, dp.dept_name),
       (sc.grade),
       ()
 )
 ORDER BY GROUPING(sc.dept_code), sc.dept_code, GROUPING(sc.grade), sc.grade;

-- [2] 주관식 의견 (텍스트)
WITH final_response AS (
    SELECT DISTINCT ON (r.survey_id, r.student_no)
           r.response_id, r.survey_id,
           r.dept_code_at_response AS dept_code,
           r.grade_at_response     AS grade
      FROM survey_response r
     WHERE r.is_completed
     ORDER BY r.survey_id, r.student_no, r.responded_at DESC, r.response_id DESC
), group_size AS (
    SELECT survey_id, dept_code, grade, count(*) AS respondents
      FROM final_response
     GROUP BY survey_id, dept_code, grade
), opinion AS (
    SELECT f.survey_id, f.dept_code, f.grade, btrim(d.text_answer) AS text_answer
      FROM final_response f
      JOIN survey_response_detail d ON d.response_id = f.response_id
      JOIN survey_question q        ON q.question_id = d.question_id
     WHERE q.question_type = 'TEXT'
       AND d.text_answer IS NOT NULL
       AND btrim(d.text_answer) <> ''
)
SELECT p.program_name                                                    AS 프로그램,
       CASE WHEN g.respondents >= :q11_min_group THEN dp.dept_name
            ELSE '(소수 응답 비공개)' END                                 AS 학과,
       CASE WHEN g.respondents >= :q11_min_group THEN o.grade::text
            ELSE '(비공개)' END                                          AS 학년,
       o.text_answer                                                     AS 의견,
       count(*)                                                          AS 건수
  FROM opinion o
  JOIN group_size g   ON g.survey_id = o.survey_id
                     AND g.dept_code = o.dept_code
                     AND g.grade = o.grade
  JOIN survey s       ON s.survey_id = o.survey_id
  JOIN program p      ON p.program_id = s.program_id
  JOIN department dp  ON dp.dept_code = o.dept_code
 GROUP BY p.program_id, p.program_name, p.program_date, 2, 3, o.text_answer
 ORDER BY p.program_date, 2, 3, o.text_answer;
