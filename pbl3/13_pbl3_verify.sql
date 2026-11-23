\encoding UTF8
\set ON_ERROR_STOP on
\pset pager off
-- 13_pbl3_verify.sql : PBL3 데이터 무결성 검사 + 분포 요약
-- 무결성 위반이 하나라도 있으면 에러로 멈춘다.

DO $$
DECLARE v BIGINT;
BEGIN
    -- 생성 단계가 실행되지 않은 빈 데이터는 실패로 처리
    IF (SELECT count(*) FROM pbl3.student) = 0
       OR (SELECT count(*) FROM pbl3.program_participant) = 0
       OR (SELECT count(*) FROM pbl3.survey_response) = 0
       OR (SELECT count(*) FROM pbl3.mv_candidate) = 0 THEN
        RAISE EXCEPTION 'PBL3 데이터가 비어 있습니다. 11_pbl3_generate.sql 실행 여부를 확인하세요';
    END IF;

    -- 예정 회차에는 신청·출석·조사가 없어야 함
    SELECT count(*) INTO v FROM pbl3.program_participant pp
      JOIN pbl3.program_session s USING (session_id) WHERE s.session_status = 'SCHEDULED';
    IF v > 0 THEN RAISE EXCEPTION '예정 회차에 참여 기록 %건', v; END IF;

    -- 정원 초과 없음
    SELECT count(*) INTO v FROM (
        SELECT pp.session_id FROM pbl3.program_participant pp
          JOIN pbl3.program_session s USING (session_id) JOIN pbl3.program p USING (program_id)
         GROUP BY pp.session_id, p.capacity HAVING count(*) > p.capacity) x;
    IF v > 0 THEN RAISE EXCEPTION '정원 초과 회차 %건', v; END IF;

    -- 만족도 응답자는 모두 해당 회차 출석자
    SELECT count(*) INTO v FROM pbl3.survey_response rs
      JOIN pbl3.survey sv USING (survey_id)
      LEFT JOIN pbl3.program_participant pp
             ON pp.session_id = sv.session_id AND pp.student_no = rs.student_no AND pp.attendance_status = 'ATTENDED'
     WHERE pp.student_no IS NULL;
    IF v > 0 THEN RAISE EXCEPTION '출석하지 않은 학생의 응답 %건', v; END IF;

    -- 완료 응답은 척도 5문항을 모두 가짐
    SELECT count(*) INTO v FROM pbl3.survey_response rs
     WHERE rs.is_completed
       AND (SELECT count(*) FROM pbl3.survey_response_detail d
              JOIN pbl3.survey_question q USING (question_id)
             WHERE d.response_id = rs.response_id AND q.question_type = 'SCALE') <> 5;
    IF v > 0 THEN RAISE EXCEPTION '척도 문항이 빠진 완료 응답 %건', v; END IF;

    -- 참여 학생은 회차 일자에 재학 중이어야 함
    SELECT count(*) INTO v FROM pbl3.program_participant pp
      JOIN pbl3.program_session s USING (session_id)
      JOIN pbl3.student st USING (student_no)
     WHERE pbl3.fn_grade_at(st.admission_date, st.admission_type, s.session_date) IS NULL
        OR (st.enrollment_status IN ('WITHDRAWN', 'ON_LEAVE') AND st.status_change_date <= s.session_date);
    IF v > 0 THEN RAISE EXCEPTION '재학 기간 밖 참여 %건', v; END IF;

    -- 신청은 회차 이전, 출석 시각은 회차 당일
    SELECT count(*) INTO v FROM pbl3.program_participant pp
      JOIN pbl3.program_session s USING (session_id)
     WHERE pp.registered_at >= (s.session_date + s.start_time) AT TIME ZONE 'Asia/Seoul'
        OR (pp.attended_at IS NOT NULL AND (pp.attended_at AT TIME ZONE 'Asia/Seoul')::DATE <> s.session_date);
    IF v > 0 THEN RAISE EXCEPTION '신청·출석 시각 오류 %건', v; END IF;

    -- 후보 뷰와 실제 참여 기록이 일치
    SELECT count(*) INTO v FROM pbl3.program_participant pp
      LEFT JOIN pbl3.mv_candidate c USING (session_id, student_no)
     WHERE c.student_no IS NULL;
    IF v > 0 THEN RAISE EXCEPTION '후보 뷰에 없는 참여 기록 %건', v; END IF;

    RAISE NOTICE 'PBL3 verification passed.';
END $$;

\echo ===== 건수 =====
SELECT '학생' AS item, count(*) AS rows FROM pbl3.student
UNION ALL SELECT '  재학 중', count(*) FROM pbl3.student WHERE enrollment_status = 'ENROLLED'
UNION ALL SELECT '프로그램(시리즈)', count(*) FROM pbl3.program
UNION ALL SELECT '회차', count(*) FROM pbl3.program_session
UNION ALL SELECT '  예정 회차', count(*) FROM pbl3.program_session WHERE session_status = 'SCHEDULED'
UNION ALL SELECT '회차×대상학생', count(*) FROM pbl3.mv_candidate
UNION ALL SELECT '신청', count(*) FROM pbl3.program_participant
UNION ALL SELECT '  출석', count(*) FROM pbl3.program_participant WHERE attendance_status = 'ATTENDED'
UNION ALL SELECT '만족도 응답', count(*) FROM pbl3.survey_response
UNION ALL SELECT '  응답 상세', count(*) FROM pbl3.survey_response_detail
UNION ALL SELECT '지출', count(*) FROM pbl3.expenditure
UNION ALL SELECT '수업 시간표', count(*) FROM pbl3.course_timetable
UNION ALL SELECT 'SMS 수신 거부', count(*) FROM pbl3.student_info_change_request;

\echo ===== 학생별 출석 횟수 분포 (긴 꼬리) =====
SELECT CASE WHEN attended = 0 THEN '0회' WHEN attended <= 2 THEN '1~2회' WHEN attended <= 5 THEN '3~5회'
            WHEN attended <= 10 THEN '6~10회' ELSE '11회 이상' END AS bucket,
       count(*) AS students
  FROM pbl3.v_student_activity
 GROUP BY 1 ORDER BY min(attended);

\echo ===== 만족도 점수 분포 =====
SELECT q.category_code, round(avg(d.score), 2) AS avg,
       count(*) FILTER (WHERE d.score = 1) AS s1, count(*) FILTER (WHERE d.score = 2) AS s2,
       count(*) FILTER (WHERE d.score = 3) AS s3, count(*) FILTER (WHERE d.score = 4) AS s4,
       count(*) FILTER (WHERE d.score = 5) AS s5
  FROM pbl3.survey_response_detail d JOIN pbl3.survey_question q USING (question_id)
 WHERE q.question_type = 'SCALE' GROUP BY 1 ORDER BY 1;

\echo ===== 단순 비교: 수업 충돌 여부별 신청률·출석률 (원인 분해 전 참고값) =====
SELECT class_conflict, count(*) AS candidates,
       round(100.0 * avg(registered::INT), 2) AS register_pct,
       round(100.0 * avg(attended::INT) FILTER (WHERE registered), 1) AS show_pct
  FROM pbl3.mv_candidate WHERE session_status = 'COMPLETED'
 GROUP BY 1 ORDER BY 1;
