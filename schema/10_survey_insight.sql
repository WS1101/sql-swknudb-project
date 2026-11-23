-- Survey Insight 기본판: 설문 시간·품질·만족도만 담당한다.
-- 05_survey_insight.sql로 적용. 출석/기회/재참여는 06 → 11번 선택 확장.
-- 이전 버전의 출석 테이블/함수는 이미 적용되어 있어도 삭제하거나 수정하지 않는다.
-- 기존 public 테이블 컬럼, 데이터, 기존 analytics 뷰는 변경하지 않는다.
BEGIN;
-- 1. 화면/SQL에서 조절할 품질 분석 기준
CREATE TABLE IF NOT EXISTS analytics.survey_insight_setting (
    setting_id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (setting_id = 1),
    absolute_seconds DOUBLE PRECISION NOT NULL DEFAULT 2 CHECK (absolute_seconds > 0 AND absolute_seconds < 600),
    relative_fraction DOUBLE PRECISION NOT NULL DEFAULT .25 CHECK (relative_fraction > 0 AND relative_fraction < 1),
    relative_percentile DOUBLE PRECISION NOT NULL DEFAULT .1 CHECK (relative_percentile > 0 AND relative_percentile < 1),
    min_cohort INT NOT NULL DEFAULT 10 CHECK (min_cohort >= 2),
    min_questions INT NOT NULL DEFAULT 4 CHECK (min_questions >= 2),
    speed_mode TEXT NOT NULL DEFAULT 'either' CHECK (speed_mode IN ('absolute','relative','either','both')),
    fast_penalty INT NOT NULL DEFAULT 40 CHECK (fast_penalty BETWEEN 0 AND 100),
    straight_penalty INT NOT NULL DEFAULT 15 CHECK (straight_penalty BETWEEN 0 AND 100),
    interaction_penalty INT NOT NULL DEFAULT 20 CHECK (interaction_penalty BETWEEN 0 AND 100),
    suspicious_below INT NOT NULL DEFAULT 70 CHECK (suspicious_below BETWEEN 0 AND 100)
);
INSERT INTO analytics.survey_insight_setting(setting_id) VALUES (1) ON CONFLICT DO NOTHING;

-- 2. 설문에만 필요한 보조 정보 (기존 응답 시간은 채우지 않음)
CREATE TABLE IF NOT EXISTS analytics.survey_demo_program (
    program_id INT PRIMARY KEY REFERENCES public.program(program_id),
    seed_version TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS analytics.survey_response_observation (
    response_id BIGINT PRIMARY KEY REFERENCES public.survey_response(response_id),
    started_at TIMESTAMPTZ,
    synthetic_scenario TEXT
);
-- responded_at를 제출 시각으로 재사용. 양쪽 UPDATE 경로에서 시간 순서를 검증한다.
CREATE OR REPLACE FUNCTION analytics.fn_check_response_timing() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, analytics AS $$
DECLARE start_time TIMESTAMPTZ; submit_time TIMESTAMPTZ;
BEGIN
    IF TG_TABLE_NAME = 'survey_response_observation' THEN
        SELECT responded_at INTO submit_time FROM public.survey_response
         WHERE response_id = NEW.response_id FOR UPDATE;
        start_time := NEW.started_at;
    ELSE
        SELECT started_at INTO start_time FROM analytics.survey_response_observation
         WHERE response_id = NEW.response_id;
        submit_time := NEW.responded_at;
    END IF;
    IF start_time > submit_time OR NOT isfinite(submit_time)
       OR (start_time IS NOT NULL AND NOT isfinite(start_time)) THEN
        RAISE EXCEPTION '시작 시각은 유한한 제출 시각 이하여야 합니다' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_survey_observation_time ON analytics.survey_response_observation;
CREATE TRIGGER trg_survey_observation_time BEFORE INSERT OR UPDATE ON analytics.survey_response_observation
FOR EACH ROW EXECUTE FUNCTION analytics.fn_check_response_timing();
DROP TRIGGER IF EXISTS trg_survey_insight_submit_time ON public.survey_response;
CREATE TRIGGER trg_survey_insight_submit_time BEFORE UPDATE OF responded_at ON public.survey_response
FOR EACH ROW EXECUTE FUNCTION analytics.fn_check_response_timing();

-- 3. 출석에 의존하지 않는 프로그램/응답 분석 기초
CREATE OR REPLACE VIEW analytics.v_survey_insight_program AS
SELECT p.program_id, p.program_name, p.program_date,
       CASE WHEN dp.program_id IS NULL THEN 'existing' ELSE 'synthetic' END AS data_source,
       -- 이전 버전의 VIEW/함수 반환 형식 유지용. 출석은 11번 확장에서만 계산한다.
       -- 미연결은 실제 출석 0명이 아니므로 NULL로 둔다.
       NULL::BIGINT AS attendance_count
FROM public.program p LEFT JOIN analytics.survey_demo_program dp USING(program_id);

-- 응답 단위로 먼저 집계. 문항/출석 JOIN이 응답 수를 곱하지 않음.
CREATE OR REPLACE VIEW analytics.v_survey_insight_base AS
SELECT r.response_id, r.survey_id, s.program_id, p.program_name, p.data_source,
       r.student_no, r.dept_code_at_response AS dept_code, r.grade_at_response AS grade,
       r.responded_at AS submitted_at, o.started_at,
       extract(epoch FROM r.responded_at-o.started_at)::DOUBLE PRECISION AS duration_seconds,
       r.is_completed,
       EXISTS (SELECT 1 FROM analytics.v_survey_response_final f WHERE f.response_id=r.response_id) AS is_latest,
       (SELECT count(*) FROM public.survey_question q WHERE q.survey_id=r.survey_id AND q.question_type='SCALE') AS expected_questions,
       (SELECT count(*) FROM public.survey_question q WHERE q.survey_id=r.survey_id) AS expected_all,
       count(d.question_id) FILTER (WHERE q.survey_id=r.survey_id AND
           ((q.question_type='SCALE' AND d.score BETWEEN 1 AND 5) OR
            (q.question_type='TEXT' AND btrim(d.text_answer)<>''))) AS answered_all,
       count(d.score) FILTER (WHERE q.question_type='SCALE' AND q.survey_id=r.survey_id AND d.score BETWEEN 1 AND 5) AS score_count,
       sum(d.score) FILTER (WHERE q.question_type='SCALE' AND q.survey_id=r.survey_id) AS score_sum,
       avg(d.score) FILTER (WHERE q.question_type='SCALE' AND q.survey_id=r.survey_id)::DOUBLE PRECISION AS mean_score,
       var_pop(d.score) FILTER (WHERE q.question_type='SCALE' AND q.survey_id=r.survey_id)::DOUBLE PRECISION AS score_variance,
       min(d.score) FILTER (WHERE q.question_type='SCALE') AS min_score,
       max(d.score) FILTER (WHERE q.question_type='SCALE') AS max_score
FROM public.survey_response r JOIN public.survey s USING(survey_id)
JOIN analytics.v_survey_insight_program p USING(program_id)
LEFT JOIN analytics.survey_response_observation o USING(response_id)
LEFT JOIN public.survey_response_detail d USING(response_id)
LEFT JOIN public.survey_question q USING(question_id)
GROUP BY r.response_id,s.program_id,p.program_name,p.data_source,o.started_at;

-- 4. 응답별 속도·반복·품질 지표. 이 함수는 참여 데이터가 없어도 실행된다.
CREATE OR REPLACE FUNCTION analytics.fn_survey_quality(p_config JSONB DEFAULT '{}', p_source TEXT DEFAULT 'existing')
RETURNS TABLE (
    response_id BIGINT, survey_id INT, program_id INT, program_name VARCHAR(100),
    student_no VARCHAR(20), dept_code VARCHAR(10), grade SMALLINT, submitted_at TIMESTAMPTZ,
    is_latest BOOLEAN, is_valid BOOLEAN, score_count BIGINT, score_sum BIGINT, mean_score DOUBLE PRECISION,
    score_variance DOUBLE PRECISION, duration_seconds DOUBLE PRECISION, seconds_per_question DOUBLE PRECISION,
    cohort_count BIGINT, survey_mean_seconds DOUBLE PRECISION, survey_median_seconds DOUBLE PRECISION,
    time_percentile DOUBLE PRECISION, absolute_fast BOOLEAN, relative_fast BOOLEAN, is_fast BOOLEAN,
    is_straight BOOLEAN, quality_score INT, is_suspicious BOOLEAN, response_type TEXT, reasons TEXT
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, analytics AS $$
DECLARE c analytics.survey_insight_setting;
BEGIN
    IF p_source NOT IN ('existing','synthetic') OR p_source IS NULL OR p_config IS NULL
       OR jsonb_typeof(p_config) <> 'object' THEN
        RAISE EXCEPTION 'invalid source/config' USING ERRCODE='22023';
    END IF;
    IF p_config - ARRAY['absolute_seconds','relative_fraction','relative_percentile','min_cohort','min_questions',
        'speed_mode','fast_penalty','straight_penalty','interaction_penalty','suspicious_below'] <> '{}'::JSONB THEN
        RAISE EXCEPTION 'unknown configuration key' USING ERRCODE='22023';
    END IF;
    SELECT * INTO c FROM jsonb_populate_record(NULL::analytics.survey_insight_setting,
        (SELECT to_jsonb(x) FROM analytics.survey_insight_setting x WHERE setting_id=1) || p_config);
    IF c.absolute_seconds IS NULL OR NOT (c.absolute_seconds>0 AND c.absolute_seconds<600)
      OR c.relative_fraction IS NULL OR NOT (c.relative_fraction>0 AND c.relative_fraction<1)
      OR c.relative_percentile IS NULL OR NOT (c.relative_percentile>0 AND c.relative_percentile<1)
      OR c.min_cohort IS NULL OR c.min_cohort<2 OR c.min_questions IS NULL OR c.min_questions<2
      OR c.speed_mode IS NULL OR c.speed_mode NOT IN ('absolute','relative','either','both')
      OR c.fast_penalty IS NULL OR c.fast_penalty NOT BETWEEN 0 AND 100
      OR c.straight_penalty IS NULL OR c.straight_penalty NOT BETWEEN 0 AND 100
      OR c.interaction_penalty IS NULL OR c.interaction_penalty NOT BETWEEN 0 AND 100
      OR c.suspicious_below IS NULL OR c.suspicious_below NOT BETWEEN 0 AND 100 THEN
        RAISE EXCEPTION 'invalid quality thresholds' USING ERRCODE='22023';
    END IF;
    RETURN QUERY
    WITH b AS (
        SELECT x.*, (x.is_completed AND isfinite(x.submitted_at) AND x.expected_questions>0 AND x.expected_questions=x.score_count
               AND x.expected_all=x.answered_all) AS valid
        FROM analytics.v_survey_insight_base x WHERE x.data_source=p_source
    ), timed AS (
        SELECT x.response_id,x.survey_id,x.duration_seconds,
          percent_rank() OVER (PARTITION BY x.survey_id ORDER BY x.duration_seconds) AS pct
        FROM b x WHERE x.valid AND x.is_latest AND x.duration_seconds IS NOT NULL AND x.duration_seconds>=0
    ), stats AS (
        SELECT t.survey_id,count(*) AS n,avg(t.duration_seconds) AS mean_t,
          percentile_cont(.5) WITHIN GROUP(ORDER BY t.duration_seconds) AS median_t
        FROM timed t GROUP BY t.survey_id
    ), signals AS (
        SELECT x.*, coalesce(st.n,0) AS n,st.mean_t,st.median_t,t.pct,
          x.duration_seconds/nullif(x.score_count,0) AS per_question,
          coalesce(x.duration_seconds/nullif(x.score_count,0)<c.absolute_seconds,false) AS abs_fast,
          coalesce(st.n>=c.min_cohort AND t.pct<=c.relative_percentile
                   AND x.duration_seconds<st.median_t*c.relative_fraction,false) AS rel_fast,
          coalesce(x.score_count>=c.min_questions AND x.min_score=x.max_score,false) AS straight
        FROM b x LEFT JOIN timed t ON t.response_id=x.response_id LEFT JOIN stats st ON st.survey_id=x.survey_id
    ), classified AS (
        SELECT x.*, CASE c.speed_mode WHEN 'absolute' THEN x.abs_fast WHEN 'relative' THEN x.rel_fast
          WHEN 'both' THEN x.abs_fast AND x.rel_fast ELSE x.abs_fast OR x.rel_fast END AS fast,
          (x.valid AND x.duration_seconds IS NOT NULL AND x.duration_seconds>=0
           AND x.score_count>=c.min_questions
           AND (c.speed_mode IN ('absolute','either') OR x.n>=c.min_cohort)) AS sufficient
        FROM signals x
    ), scored AS (
        SELECT x.*,CASE WHEN x.sufficient THEN greatest(0,100
          -CASE WHEN x.fast THEN c.fast_penalty ELSE 0 END
          -CASE WHEN x.straight THEN c.straight_penalty ELSE 0 END
          -CASE WHEN x.fast AND x.straight THEN c.interaction_penalty ELSE 0 END) END AS quality
        FROM classified x
    )
    SELECT x.response_id,x.survey_id,x.program_id,x.program_name,x.student_no,x.dept_code,x.grade,x.submitted_at,
      x.is_latest,x.valid,x.score_count,x.score_sum,x.mean_score,x.score_variance,x.duration_seconds,x.per_question,
      x.n,x.mean_t,x.median_t,x.pct,x.abs_fast,x.rel_fast,x.fast,x.straight,x.quality,
      coalesce(x.quality<c.suspicious_below,false),
      CASE WHEN NOT x.valid THEN '미완료 또는 유효하지 않은 응답'
           WHEN NOT x.sufficient THEN '분석 정보 부족'
           WHEN x.fast AND x.straight THEN '빠른 응답 + 동일 점수 반복'
           WHEN x.fast THEN '빠른 응답 의심'
           WHEN x.straight THEN '동일 점수 반복 의심' ELSE '정상 범위 응답' END,
      concat_ws('; ',
        CASE WHEN NOT x.is_latest AND x.is_completed THEN '이전 완료 응답: 집계 제외' END,
        CASE WHEN NOT x.valid THEN '미완료/점수 문항 누락/점수 없음: 집계 제외' END,
        CASE WHEN x.duration_seconds IS NULL THEN '시간 정보 없음: 품질 점수 미산출' END,
        CASE WHEN x.score_count<c.min_questions THEN '점수 문항 부족: 패턴 판단 보류' END,
        CASE WHEN x.n<c.min_cohort THEN '시간 표본 부족: 상대 기준 사용 불가' END,
        CASE WHEN x.fast THEN '빠른 응답 신호 (산출 가능 시 -'||c.fast_penalty||')' END,
        CASE WHEN x.straight THEN '동일 점수 반복: 실제 만족일 수 있음 (산출 가능 시 -'||c.straight_penalty||')' END,
        CASE WHEN x.fast AND x.straight THEN '두 신호 동시 발생 (산출 가능 시 -'||c.interaction_penalty||')' END,
        CASE WHEN x.duration_seconds>3600 THEN '장시간 열림: 실제 집중 시간과 다를 수 있음' END)
    FROM scored x;
END $$;

-- 5. 프로그램별 원본/제외/보조 가중 평균
CREATE OR REPLACE FUNCTION analytics.fn_survey_summary(p_config JSONB DEFAULT '{}', p_source TEXT DEFAULT 'existing')
RETURNS TABLE(program_id INT,program_name VARCHAR(100),attendance_count BIGINT,response_count BIGINT,
    suspicious_count BIGINT,unknown_count BIGINT,original_mean DOUBLE PRECISION,
    filtered_mean DOUBLE PRECISION,weighted_mean DOUBLE PRECISION,suspicious_ratio DOUBLE PRECISION,
    mean_change DOUBLE PRECISION)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, analytics AS $$
WITH q AS (SELECT * FROM analytics.fn_survey_quality(p_config,p_source) WHERE is_latest AND is_valid),
agg AS (
 SELECT q.program_id,count(*) AS n,count(*) FILTER(WHERE is_suspicious) AS ns,
 count(*) FILTER(WHERE quality_score IS NULL) AS nu,
 sum(score_sum)::DOUBLE PRECISION/nullif(sum(score_count),0) AS original,
 sum(score_sum) FILTER(WHERE NOT is_suspicious)::DOUBLE PRECISION/
    nullif(sum(score_count) FILTER(WHERE NOT is_suspicious),0) AS filtered,
 sum(score_sum*coalesce(quality_score/100.0,1))/nullif(sum(score_count*coalesce(quality_score/100.0,1)),0) AS weighted
 FROM q GROUP BY q.program_id
)
SELECT p.program_id,p.program_name,p.attendance_count,coalesce(a.n,0),coalesce(a.ns,0),coalesce(a.nu,0),
 a.original,a.filtered,a.weighted::DOUBLE PRECISION,a.ns::DOUBLE PRECISION/nullif(a.n,0),a.filtered-a.original
FROM analytics.v_survey_insight_program p LEFT JOIN agg a USING(program_id) WHERE p.data_source=p_source
$$;

-- 문항분류는 기존 category_code 그대로. 내용/운영/전체를 임의로 강사/시간에 매핑하지 않음.
CREATE OR REPLACE VIEW analytics.v_survey_insight_category AS
SELECT b.response_id,b.program_id,b.data_source,q.category_code,c.category_name,
       sum(d.score) AS score_sum,count(d.score) AS score_count
FROM analytics.v_survey_insight_base b
JOIN public.survey_response_detail d USING(response_id)
JOIN public.survey_question q ON q.question_id=d.question_id AND q.survey_id=b.survey_id
JOIN public.survey_question_category c USING(category_code)
WHERE b.is_latest AND b.is_completed AND q.question_type='SCALE'
GROUP BY b.response_id,b.program_id,b.data_source,q.category_code,c.category_name;

COMMENT ON TABLE analytics.survey_response_observation IS '시작 시각 확장. 기존 과거 응답을 임의로 보충하지 않음';
COMMENT ON FUNCTION analytics.fn_survey_quality(JSONB,TEXT) IS '설명 가능한 규칙 지표. 성실할 확률 또는 검증된 정확도가 아님';
REVOKE ALL ON FUNCTION analytics.fn_survey_quality(JSONB,TEXT),analytics.fn_survey_summary(JSONB,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION analytics.fn_check_response_timing() FROM PUBLIC;
REVOKE ALL ON analytics.survey_response_observation,analytics.survey_demo_program,
 analytics.survey_insight_setting,analytics.v_survey_insight_base,
 analytics.v_survey_insight_category,analytics.v_survey_insight_program FROM PUBLIC,analytics_reader;
GRANT SELECT ON analytics.v_survey_insight_category,analytics.v_survey_insight_program TO analytics_reader;
GRANT EXECUTE ON FUNCTION analytics.fn_survey_quality(JSONB,TEXT),analytics.fn_survey_summary(JSONB,TEXT) TO analytics_reader;
COMMIT;
