\encoding UTF8
-- Q09_expenditure_by_professor.sql | 교수·지출주체별 승인 지출과 교수별·주체별·전체 소계 조회.
-- 담당: 임영효
-- q09_year: 사업연도 또는 ALL(기본 ALL)
-- APPROVED만 집계한다. 활성 교수 중 지출이 없는 조합도 0으로 표시한다.
-- 예상 결과(초기 데이터 기준)
--   교수 소계: 91000001 가상교수영효 5건 28,150,000 / 91000002 교수웅수 4건 18,250,000
--              91000003 가상교수우진 8건 54,600,000 / 91000004 가상교수건희 2건 5,750,000
--   주체 소계: 산학협력 7건 29,300,000 / 전공 6건 49,250,000 / 융합 6건 28,200,000
--   전체: 19건 106,750,000 (Q08 승인지출 합계와 같아야 함)
--   0인 조합: 영효-융합, 웅수-산학협력, 건희-전공, 건희-융합

\if :{?q09_year}
\else
\set q09_year ALL
\endif
\pset null '-'

\echo '=== Q09 교수별·지출주체별 승인 지출 / 연도:' :q09_year

WITH approved AS (
    SELECT e.professor_id,
           e.subject_type_code,
           count(*)      AS cnt,
           sum(e.amount) AS amount
      FROM expenditure e
      JOIN budget_project bp ON bp.project_id = e.project_id
     WHERE e.status = 'APPROVED'
       AND (:'q09_year' = 'ALL' OR bp.project_year::text = :'q09_year')
     GROUP BY e.professor_id, e.subject_type_code
), grid AS (
    SELECT p.professor_id,
           p.professor_name,
           p.affiliation,
           st.subject_type_code,
           st.subject_type_name,
           COALESCE(a.cnt, 0)    AS cnt,
           COALESCE(a.amount, 0) AS amount
      FROM professor p
     CROSS JOIN expenditure_subject_type st
      LEFT JOIN approved a ON a.professor_id = p.professor_id
                          AND a.subject_type_code = st.subject_type_code
     WHERE p.is_active
)
SELECT CASE
           WHEN GROUPING(professor_id) = 0 AND GROUPING(subject_type_code) = 0 THEN '교수×주체'
           WHEN GROUPING(professor_id) = 0                                    THEN '교수 소계'
           WHEN GROUPING(subject_type_code) = 0                               THEN '주체 소계'
           ELSE '전체'
       END                AS 집계단위,
       professor_id       AS 교번,
       professor_name     AS 교수,
       affiliation        AS 소속,
       subject_type_name  AS 지출주체,
       sum(cnt)           AS 승인건수,
       sum(amount)        AS 승인지출
  FROM grid
 GROUP BY GROUPING SETS (
       (professor_id, professor_name, affiliation, subject_type_code, subject_type_name),
       (professor_id, professor_name, affiliation),
       (subject_type_code, subject_type_name),
       ()
 )
 ORDER BY GROUPING(professor_id), professor_id,
          GROUPING(subject_type_code), subject_type_code;
