\encoding UTF8
-- 05_survey_insight.sql 적용 후 실행. p_config로 민감도 비교 가능.
SELECT * FROM analytics.fn_survey_summary('{}','existing') ORDER BY program_id;
SELECT response_type,count(*) FROM analytics.fn_survey_quality('{}','existing')
 WHERE is_latest AND is_valid GROUP BY response_type;
SELECT * FROM analytics.fn_survey_summary('{"absolute_seconds":1,"speed_mode":"absolute"}','existing');
