\encoding UTF8
-- =====================================================================
-- Q10_survey_by_question.sql : 프로그램별·문항별 만족도 평균 및 응답 수
-- 담당: 임영효
--
-- 목적
--   조사의 문항마다 응답 수와 평균(척도 문항)을 보여준다. 주관식은 응답 수만 집계하고
--   내용은 Q11에서 본다.
--
-- 입력
--   q10_program : 프로그램명 일부(LIKE), 또는 ALL   기본 ALL
--
-- 기준 (완료 응답 기준)
--   - 미완료(is_completed = false) 응답은 제외
--   - 같은 학생이 같은 조사에 여러 번 응답했으면 가장 최근(responded_at, 같으면 response_id가 큰 것)
--     완료 응답 1건만 사용 → DISTINCT ON
--   - 척도(SCALE): 평균·최저·최고·만족비율(4점 이상 비율)
--   - 주관식(TEXT): 응답 수만. 평균 등은 '-' 로 표시
--   - 응답 수 = 해당 문항에 답한 최종 응답 수
--
-- 예상 결과 (기본 입력)
--   [1] 6개 조사 × 4문항 = 24행
--     해커톤 기초과정    응답 21  Q1 2.90 / Q2 2.95 / Q3 3.00 / 주관식 21
--     AI 집중교육        응답 21  Q1 2.95 / Q2 3.00 / Q3 3.05
--     오픈소스 워크숍    응답 22  Q1 2.95 / Q2 3.05 / Q3 3.14
--     창업 아이디어 캠프 응답 21  Q1 3.00 / Q2 3.05 / Q3 3.10
--     전공 멘토링        응답 21  Q1 3.10 / Q2 2.90 / Q3 2.95
--     알고리즘 경진대회  응답 22  Q1 3.00 / Q2 2.86 / Q3 2.95
--   [2] 해커톤 Q1·Q2 집계 기준 비교 (완료 응답 기준을 쓰는 이유)
--     Q1  원본 전체 25건 2.76 / 완료 전체 22건 3.00 / 최신 완료 21건 2.90
--     Q2  원본 전체 25건 2.64 / 완료 전체 22건 2.86 / 최신 완료 21건 2.95
--     원본 전체에는 미완료 3건(1점)이, 완료 전체에는 20230001의 이전 응답이 섞여 있음
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q10_program}
\else
\set q10_program ALL
\endif
\pset null '-'

\echo '=== Q10 프로그램별·문항별 만족도 / 프로그램:' :q10_program

-- [1] 문항별 집계 (최신 완료 응답 기준)
WITH final_response AS (
    SELECT DISTINCT ON (r.survey_id, r.student_no)
           r.response_id, r.survey_id, r.student_no
      FROM survey_response r
     WHERE r.is_completed
     ORDER BY r.survey_id, r.student_no, r.responded_at DESC, r.response_id DESC
)
SELECT p.program_name                                         AS 프로그램,
       pt.program_type_name                                   AS 유형,
       s.survey_name                                          AS 조사,
       q.display_order                                        AS 순번,
       c.category_name                                        AS 문항분류,
       q.question_text                                        AS 문항,
       q.question_type                                        AS 유형구분,
       count(d.response_id)                                   AS 응답수,
       CASE WHEN q.question_type = 'SCALE'
            THEN round(avg(d.score), 2) END                   AS 평균,
       min(d.score)                                           AS 최저,
       max(d.score)                                           AS 최고,
       CASE WHEN q.question_type = 'SCALE'
            THEN round(100.0 * count(*) FILTER (WHERE d.score >= 4)
                       / NULLIF(count(d.score), 0), 1) END    AS 만족비율
  FROM survey s
  JOIN program p                    ON p.program_id = s.program_id
  JOIN program_type pt              ON pt.program_type_code = p.program_type_code
  JOIN survey_question q            ON q.survey_id = s.survey_id
  JOIN survey_question_category c   ON c.category_code = q.category_code
  LEFT JOIN final_response f        ON f.survey_id = s.survey_id
  LEFT JOIN survey_response_detail d ON d.response_id = f.response_id
                                    AND d.question_id = q.question_id
 WHERE :'q10_program' = 'ALL' OR p.program_name LIKE '%' || :'q10_program' || '%'
 GROUP BY p.program_id, p.program_name, p.program_date, pt.program_type_name,
          s.survey_id, s.survey_name,
          q.question_id, q.display_order, c.category_name, q.question_text, q.question_type
 ORDER BY p.program_date, s.survey_id, q.display_order;

-- [2] 집계 기준 비교: 가장 먼저 열린 조사의 척도 문항 1·2번
WITH target_survey AS (
    SELECT s.survey_id
      FROM survey s JOIN program p ON p.program_id = s.program_id
     ORDER BY p.program_date, s.survey_id
     LIMIT 1
), final_response AS (
    SELECT DISTINCT ON (r.survey_id, r.student_no) r.response_id
      FROM survey_response r
     WHERE r.is_completed
       AND r.survey_id = (SELECT survey_id FROM target_survey)
     ORDER BY r.survey_id, r.student_no, r.responded_at DESC, r.response_id DESC
)
SELECT q.display_order                                         AS 문항순번,
       count(d.score)                                          AS 원본전체_건수,
       round(avg(d.score), 2)                                  AS 원본전체_평균,
       count(d.score) FILTER (WHERE r.is_completed)            AS 완료전체_건수,
       round(avg(d.score) FILTER (WHERE r.is_completed), 2)    AS 완료전체_평균,
       count(d.score) FILTER (WHERE fr.response_id IS NOT NULL)            AS 최신완료_건수,
       round(avg(d.score) FILTER (WHERE fr.response_id IS NOT NULL), 2)    AS 최신완료_평균
  FROM survey_question q
  JOIN survey_response_detail d ON d.question_id = q.question_id
  JOIN survey_response r        ON r.response_id = d.response_id
  LEFT JOIN final_response fr   ON fr.response_id = r.response_id
 WHERE q.survey_id = (SELECT survey_id FROM target_survey)
   AND q.question_type = 'SCALE'
   AND q.display_order IN (1, 2)
 GROUP BY q.display_order
 ORDER BY q.display_order;
