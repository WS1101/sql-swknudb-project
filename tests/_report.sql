-- =====================================================================
-- _report.sql : 테스트 결과 출력 (각 테스트 파일이 ROLLBACK 직전에 \ir 로 불러온다)
-- =====================================================================
\pset null '-'
SELECT no                                       AS 번호,
       CASE WHEN pass THEN 'PASS' ELSE 'FAIL' END AS 결과,
       item                                     AS 항목,
       detail                                   AS 상세
  FROM t_result
 ORDER BY no;

SELECT count(*)                          AS 전체,
       count(*) FILTER (WHERE pass)      AS 통과,
       count(*) FILTER (WHERE NOT pass)  AS 실패
  FROM t_result;
