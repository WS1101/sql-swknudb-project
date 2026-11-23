\encoding UTF8
-- 선택 확장: 06 적용 후 실행. 연결 전에는 연계 대기/NULL이 정상이다.
SELECT * FROM analytics.v_program_attendance_count;
SELECT q.response_type,count(*) AS responses,count(f.rejoined) AS observable,
       avg(f.rejoined::INT) AS rejoin_rate
FROM analytics.fn_survey_quality('{}','existing') q
LEFT JOIN analytics.fn_survey_followup(now(),'existing') f USING(response_id)
WHERE q.is_latest AND q.is_valid
GROUP BY q.response_type;
