-- 선택 확장: 설문 품질 분석과 공통 참여 데이터 사이의 연결만 담당한다.
-- 우진이의 program_session/program_participant 구조는 여기서 가정하지 않는다.
-- 1. 합의 후 아래 두 VIEW의 SELECT를 실제 공통 테이블에 매핑한다.
-- 2. 출석/기회 연결 확인 후 setting의 연결 플래그를 TRUE로 설정한다.
-- 3. participation_coverage에는 실제로 수집이 완료된 범위만 기록한다.
BEGIN;

-- 기본 계약: 실제 출석 이벤트 1건/행. 다회차 출석은 여러 행 허용.
-- 초기 VIEW는 0행이며, 재실행 시 팀원이 교체한 매핑을 덮어쓰지 않는다.
DO $$ BEGIN
    IF to_regclass('analytics.v_attendance_event') IS NULL THEN
        EXECUTE $view$
            CREATE VIEW analytics.v_attendance_event AS
            SELECT NULL::VARCHAR(20) AS student_no,
                   NULL::INT AS program_id,
                   NULL::TIMESTAMPTZ AS attended_at
            WHERE FALSE
        $view$;
    END IF;
    -- 재참여율의 기회 분모를 확인할 수 있을 때 추가 연결한다.
    IF to_regclass('analytics.v_program_opportunity') IS NULL THEN
        EXECUTE $view$
            CREATE VIEW analytics.v_program_opportunity AS
            SELECT NULL::VARCHAR(20) AS student_no,
                   NULL::INT AS program_id,
                   NULL::TIMESTAMPTZ AS offered_at,
                   NULL::TIMESTAMPTZ AS scheduled_at
            WHERE FALSE
        $view$;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS analytics.survey_participation_setting (
    setting_id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (setting_id=1),
    attendance_connected BOOLEAN NOT NULL DEFAULT FALSE,
    opportunity_connected BOOLEAN NOT NULL DEFAULT FALSE
);
INSERT INTO analytics.survey_participation_setting(setting_id) VALUES (1) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS analytics.participation_coverage (
    data_source TEXT PRIMARY KEY CHECK (data_source IN ('existing','synthetic')),
    observed_from TIMESTAMPTZ NOT NULL CHECK (isfinite(observed_from)),
    observed_through TIMESTAMPTZ NOT NULL CHECK (isfinite(observed_through)),
    evidence TEXT NOT NULL CHECK (btrim(evidence)<>''),
    CHECK (observed_from<=observed_through)
);

-- 회차 수가 아닌 학생 수. 미연결 NULL과 연결 후 0건을 구분한다.
CREATE OR REPLACE VIEW analytics.v_program_attendance_count AS
SELECT p.program_id,p.data_source,
    CASE WHEN cfg.attendance_connected THEN
        (SELECT count(DISTINCT a.student_no) FROM analytics.v_attendance_event a
         WHERE a.program_id=p.program_id AND a.attended_at IS NOT NULL AND isfinite(a.attended_at))
    END AS attendance_count
FROM analytics.v_survey_insight_program p
CROSS JOIN analytics.survey_participation_setting cfg;

CREATE OR REPLACE FUNCTION analytics.fn_survey_followup(p_asof TIMESTAMPTZ, p_source TEXT DEFAULT 'existing')
RETURNS TABLE(response_id BIGINT,followup_status TEXT,rejoined BOOLEAN,opportunity_count BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,analytics AS $$
WITH b AS (
    SELECT x.*,x.submitted_at+interval '90 days' AS horizon
    FROM analytics.v_survey_insight_base x
    WHERE x.data_source=p_source AND x.is_latest AND x.is_completed
), attendance AS (
    SELECT a.student_no,a.program_id,a.attended_at
    FROM analytics.v_attendance_event a
    JOIN analytics.v_survey_insight_program p USING(program_id)
    WHERE p.data_source=p_source AND a.attended_at IS NOT NULL AND isfinite(a.attended_at)
), opportunity AS (
    SELECT o.student_no,o.program_id,o.offered_at,o.scheduled_at
    FROM analytics.v_program_opportunity o
    JOIN analytics.v_survey_insight_program p USING(program_id)
    WHERE p.data_source=p_source AND isfinite(o.offered_at) AND isfinite(o.scheduled_at)
      AND o.offered_at<=o.scheduled_at
), facts AS (
    SELECT b.response_id,b.submitted_at,b.horizon,
        EXISTS(SELECT 1 FROM attendance a
            WHERE a.student_no=b.student_no AND a.program_id<>b.program_id
              AND a.attended_at>b.submitted_at AND a.attended_at<=least(b.horizon,p_asof)) AS positive,
        (SELECT count(DISTINCT events.program_id) FROM (
            SELECT o.program_id FROM opportunity o
            WHERE o.student_no=b.student_no AND o.program_id<>b.program_id
              AND o.offered_at<=p_asof AND o.scheduled_at>b.submitted_at
              AND o.scheduled_at<=least(b.horizon,p_asof)
            UNION
            SELECT a.program_id FROM attendance a
            WHERE a.student_no=b.student_no AND a.program_id<>b.program_id
              AND a.attended_at>b.submitted_at AND a.attended_at<=least(b.horizon,p_asof)
        ) events) AS opportunities
    FROM b
), states AS (
    SELECT f.*,CASE
        WHEN NOT cfg.attendance_connected THEN '출석 연계 대기'
        -- 기회 미연결 상태에서 양성 사례만 분모에 남는 편향을 방지한다.
        WHEN NOT cfg.opportunity_connected THEN '참여 기회 연계 대기'
        WHEN p_asof IS NULL OR NOT isfinite(p_asof) OR NOT isfinite(f.submitted_at)
          OR c.data_source IS NULL OR f.submitted_at<c.observed_from THEN '기록 범위 불명'
        WHEN least(c.observed_through,p_asof)<f.horizon THEN '관찰 기간 부족'
        WHEN f.opportunities=0 THEN '후속 기회 없음'
        ELSE '관찰 완료' END AS state
    FROM facts f
    CROSS JOIN analytics.survey_participation_setting cfg
    LEFT JOIN analytics.participation_coverage c ON c.data_source=p_source
)
SELECT s.response_id,s.state,
    CASE WHEN s.state='관찰 완료' THEN s.positive END,
    CASE WHEN s.state NOT IN ('출석 연계 대기','참여 기회 연계 대기') THEN s.opportunities END
FROM states s
$$;

REVOKE ALL ON analytics.survey_participation_setting,analytics.participation_coverage,
    analytics.v_attendance_event,analytics.v_program_opportunity FROM PUBLIC,analytics_reader;
REVOKE ALL ON FUNCTION analytics.fn_survey_followup(TIMESTAMPTZ,TEXT) FROM PUBLIC;
GRANT SELECT ON analytics.v_program_attendance_count TO analytics_reader;
GRANT EXECUTE ON FUNCTION analytics.fn_survey_followup(TIMESTAMPTZ,TEXT) TO analytics_reader;
COMMIT;
