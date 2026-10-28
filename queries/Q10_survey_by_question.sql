\encoding UTF8
-- Q10_survey_by_question.sql | 프로그램별 문항 응답 수와 점수형 문항의 평균·만족비율 조회.
-- 담당: 임영효
-- q10_program: 프로그램명 일부 또는 ALL(기본 ALL)
-- 학생·조사별 최신 완료 응답만 사용한다(DISTINCT ON).
-- 주관식 문항은 응답 수만 집계하며, 평균은 계산하지 않는다.
-- 예상 결과(초기 데이터 기준)
--   [1] 6개 조사 × 4문항 = 24행
--     SW·AI 경진대회          응답 21  Q1 2.90 / Q2 2.95 / Q3 3.00 / 주관식 21
--     SW·AI 집중교육          응답 21  Q1 2.95 / Q2 3.00 / Q3 3.05
--     SW전문가 특강           응답 22  Q1 2.95 / Q2 3.05 / Q3 3.14
--     산학캡스톤디자인        응답 21  Q1 3.00 / Q2 3.05 / Q3 3.10
--     SW 가치확산 활동        응답 21  Q1 3.10 / Q2 2.90 / Q3 2.95
--     SW중심대학 에세이 공모전 응답 22  Q1 3.00 / Q2 2.86 / Q3 2.95
--   [2] SW·AI 경진대회 Q1·Q2 집계 기준 비교 (완료 응답 기준을 쓰는 이유)
--     Q1  원본 전체 25건 2.76 / 완료 전체 22건 3.00 / 최신 완료 21건 2.90
--     Q2  원본 전체 25건 2.64 / 완료 전체 22건 2.86 / 최신 완료 21건 2.95
--     원본 전체에는 미완료 3건(1점)이, 완료 전체에는 20230001의 이전 응답이 섞여 있음

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
