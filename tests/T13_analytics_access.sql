-- =====================================================================
-- T13_analytics_access.sql : 분석 계정 권한 분리, 분석 뷰 정합성
-- 담당: 서우진
-- 실행: psql -d swknu_db -f tests/T13_analytics_access.sql
--
-- 시나리오 (미션 8장 "DB 권한·뷰 등으로 실제 차단했다면 시연")
--   입력        분석 전용 계정(analytics_reader)으로 분석 뷰와 업무 테이블을 각각 조회
--   예상 결과   분석 뷰는 조회됨 / 연락처·계정·로그 등 업무 테이블은 permission denied (42501)
--               업무 함수 호출도 실패 (public 스키마 사용 권한이 없어 함수가 보이지 않음)
--   참고        reset.sql이 public 스키마를 DROP 후 다시 만들기 때문에, DB 생성 시 기본으로 있던
--               "모든 계정의 public 스키마 사용 권한"이 없다. 분석 계정은 스키마 단계에서 먼저 막힌다.
--               분석 뷰의 값은 원본 테이블에서 직접 계산한 값과 일치
--   구현 방법   - 스키마 분리 + 뷰에만 SELECT 권한 (DB가 자동 강제)
--               - 뷰는 소유자 권한으로 원본을 읽으므로 뷰에 포함된 컬럼만 노출
--
-- 계정 전환(SET ROLE)은 superuser 또는 analytics_reader 멤버만 가능하다.
-- 각 확인은 내부 블록에서 계정을 바꿨다가 되돌리므로, 결과 기록은 원래 계정으로 한다.
-- =====================================================================
\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- analytics_reader로 전환해서 SELECT 실행: 행 수를 세고, 기대 SQLSTATE와 비교
CREATE FUNCTION pg_temp.t_as_reader(p_item text, p_sql text, p_state text)
RETURNS void AS $f$
DECLARE
    v_cnt   bigint;
    v_state text;
    v_msg   text;
BEGIN
    BEGIN
        EXECUTE 'SET LOCAL ROLE analytics_reader';
        EXECUTE 'SELECT count(*) FROM (' || p_sql || ') q' INTO v_cnt;
        EXECUTE 'RESET ROLE';
    EXCEPTION WHEN OTHERS THEN
        -- 블록이 취소되면서 계정 전환도 함께 되돌려진다
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        -- p_state에 '42501|42883'처럼 여러 코드를 | 로 이어 줄 수 있다
        INSERT INTO t_result (item, pass, detail)
        VALUES (p_item, p_state IS NOT NULL AND v_state = ANY (string_to_array(p_state, '|')),
                format('거부 [%s] %s', v_state, v_msg)
                || CASE WHEN p_state IS NULL THEN ' (기대: 조회 성공)' ELSE '' END);
        RETURN;
    END;
    INSERT INTO t_result (item, pass, detail)
    VALUES (p_item, p_state IS NULL,
            format('조회 성공 %s행', v_cnt)
            || CASE WHEN p_state IS NOT NULL THEN format(' (기대: %s 거부)', p_state) ELSE '' END);
END;
$f$ LANGUAGE plpgsql;

DO $t$
DECLARE
    v_ok   boolean;
    v_txt  text;
    v_app  bigint;
BEGIN
    -- 1. 계정 확인 (참·거짓은 글자가 아니라 값으로 비교)
    SELECT count(*) = 1 AND NOT bool_or(rolcanlogin),
           format('존재=%s 로그인=%s', count(*) = 1, bool_or(rolcanlogin))
      INTO v_ok, v_txt
      FROM pg_roles WHERE rolname = 'analytics_reader';
    PERFORM pg_temp.t_check('1. analytics_reader 존재, 직접 로그인 불가(NOLOGIN)',
        v_ok, v_txt);

    -- 2~4. 분석 뷰는 조회 가능
    PERFORM pg_temp.t_as_reader('2. [분석계정] 학생 특성 뷰 조회',
        'SELECT * FROM analytics.v_student_features', NULL);
    PERFORM pg_temp.t_as_reader('3. [분석계정] 만족도 집계 뷰 조회',
        'SELECT * FROM analytics.v_satisfaction_summary', NULL);
    PERFORM pg_temp.t_as_reader('4. [분석계정] 최신 완료 응답 뷰 조회',
        'SELECT * FROM analytics.v_survey_response_final', NULL);

    -- 5~9. 업무 테이블은 차단
    PERFORM pg_temp.t_as_reader('5. [분석계정] 학생 연락처 직접 조회',
        'SELECT phone_number, email FROM public.student', '42501');
    PERFORM pg_temp.t_as_reader('6. [분석계정] 사용자 계정(비밀번호 해시) 조회',
        'SELECT login_id, password_hash FROM public.app_user', '42501');
    PERFORM pg_temp.t_as_reader('7. [분석계정] 변경 로그 조회',
        'SELECT * FROM public.change_log', '42501');
    PERFORM pg_temp.t_as_reader('8. [분석계정] 학생정보 변경 요청 조회',
        'SELECT * FROM public.student_info_change_request', '42501');
    PERFORM pg_temp.t_as_reader('9. [분석계정] 만족도 주관식 원문 조회',
        'SELECT text_answer FROM public.survey_response_detail', '42501');

    -- 10. 업무 함수로 우회 시도
    --     public 스키마 사용 권한이 없으면 함수가 보이지 않아 42883(함수 없음),
    --     스키마는 보이지만 테이블 권한이 없으면 42501(권한 없음). 둘 다 차단으로 본다.
    --     reset.sql이 public 스키마를 다시 만들면 기본 사용 권한이 없어지므로 보통 42883.
    SELECT application_id INTO v_app FROM mileage_application WHERE status = 'PENDING' LIMIT 1;
    IF v_app IS NOT NULL THEN
        PERFORM pg_temp.t_as_reader('10. [분석계정] 업무 함수로 마일리지 승인 시도',
            format('SELECT fn_approve_mileage_application(%s, %L)', v_app, '90000001'), '42501|42883');
    ELSE
        PERFORM pg_temp.t_check('10. [분석계정] 업무 함수 우회 - 대기 신청 없음, 건너뜀', true, 'seed 미적용');
    END IF;

    -- 11. 분석 뷰에 개인정보 컬럼이 없음
    SELECT string_agg(table_name || '.' || column_name, ', ') INTO v_txt
      FROM information_schema.columns
     WHERE table_schema = 'analytics'
       AND column_name IN ('user_name', 'phone_number', 'email', 'sms_opt_in',
                           'password_hash', 'login_id', 'text_answer');
    PERFORM pg_temp.t_check('11. 분석 뷰에 성명·연락처·계정·주관식 원문 컬럼 없음',
        v_txt IS NULL, COALESCE(v_txt, '없음'));

    -- 12. 학생 특성 뷰: 학생 수와 행 수 일치 (영역별 선합산으로 행이 부풀지 않음)
    PERFORM pg_temp.t_check('12. 학생 특성 뷰 행 수 = 학생 수',
        (SELECT count(*) FROM analytics.v_student_features) = (SELECT count(*) FROM student),
        format('뷰 %s / 학생 %s',
               (SELECT count(*) FROM analytics.v_student_features), (SELECT count(*) FROM student)));

    -- 13. 학생 특성 뷰의 마일리지 = 저장된 누적 마일리지 (Q05와 같은 결과)
    PERFORM pg_temp.t_check('13. 뷰 승인 마일리지 = student.cumulative_mileage (전 학생)',
        NOT EXISTS (SELECT 1 FROM analytics.v_student_features f
                      JOIN student s ON s.student_no = f.student_no
                     WHERE f.approved_mileage <> s.cumulative_mileage));

    -- 14. 최신 완료 응답 뷰: 완료 응답이 있는 (조사, 학생) 조합 수와 일치
    PERFORM pg_temp.t_check('14. 최신 완료 응답 수 = 완료 응답이 있는 (조사, 학생) 수',
        (SELECT count(*) FROM analytics.v_survey_response_final)
        = (SELECT count(*) FROM (SELECT DISTINCT survey_id, student_no
                                    FROM survey_response WHERE is_completed) x),
        format('뷰 %s', (SELECT count(*) FROM analytics.v_survey_response_final)));

    -- 15. 만족도 집계 뷰의 전체 평균 = 원본에서 직접 계산한 최신 완료 응답 평균 (Q11 전체 행)
    SELECT round(sum(score_sum)::numeric / NULLIF(sum(score_count), 0), 2) =
           (SELECT round(avg(d.score), 2)
              FROM survey_response_detail d
              JOIN survey_question q ON q.question_id = d.question_id
             WHERE q.question_type = 'SCALE'
               AND d.response_id IN (SELECT response_id FROM analytics.v_survey_response_final)),
           format('뷰 %s / 원본 %s',
                  round(sum(score_sum)::numeric / NULLIF(sum(score_count), 0), 2),
                  (SELECT round(avg(d.score), 2)
                     FROM survey_response_detail d
                     JOIN survey_question q ON q.question_id = d.question_id
                    WHERE q.question_type = 'SCALE'
                      AND d.response_id IN (SELECT response_id FROM analytics.v_survey_response_final)))
      INTO v_ok, v_txt
      FROM analytics.v_satisfaction_summary;
    PERFORM pg_temp.t_check('15. 집계 뷰 전체 평균(합계/개수) = 원본 직접 계산 평균',
        COALESCE(v_ok, true), v_txt);

    -- 16. 원래 계정으로 돌아왔는지 (이후 작업이 분석 계정으로 실행되지 않도록)
    PERFORM pg_temp.t_check('16. 테스트 후 현재 계정이 원래 계정',
        current_user <> 'analytics_reader', 'current_user = ' || current_user);
END;
$t$;

\ir _report.sql
ROLLBACK;
