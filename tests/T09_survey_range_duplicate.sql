-- =====================================================================
-- T09_survey_range_duplicate.sql : 만족도 1~5점 범위, 답변 유형, 완료 조건, 중복 응답 정책
-- 담당: 임영효
-- 실행: psql -d swknu_db -f tests/T09_survey_range_duplicate.sql
--
-- 시나리오 (미션 7장)
--   입력        범위 밖 점수(0, 6), 유형이 맞지 않는 답변, 같은 학생의 재응답
--   예상 결과   범위·유형 위반은 거부. 재응답은 허용(팀 정책)하되 집계는 최신 완료 응답만 사용
--   구현 방법   - ck_survey_detail_score CHECK (1~5)                          (자동 강제)
--               - ck_survey_detail_answer: 점수와 의견 중 하나만               (자동 강제)
--               - fn_survey_detail_validate 트리거: 문항 유형·소속 조사 일치,
--                 척도 최대값, 완료된 응답 수정·삭제 금지                      (자동 강제)
--               - fn_survey_response_check_complete 트리거: 전 문항 응답 후에만 완료 (자동 강제)
--               - 중복 응답: UNIQUE를 두지 않음. 집계 쿼리(Q10·Q11)의 DISTINCT ON으로 최신 완료 1건 선택
-- =====================================================================
\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 준비: 학생 2명, 프로그램 1, 조사 2 (조사 A: 척도 2 + 주관식 1 / 조사 B: 척도 1)
INSERT INTO college (college_code, college_name) VALUES ('T09C', '테스트대학');
INSERT INTO campus (campus_code, campus_name) VALUES ('T09P', '테스트캠퍼스');
INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
VALUES ('T09D', '테스트학과', 'T09C', 'T09P', 'NAT');
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
    ('99999101', 't09.s1', crypt('x', gen_salt('bf')), '학생1', 'STUDENT'),
    ('99999102', 't09.s2', crypt('x', gen_salt('bf')), '학생2', 'STUDENT');
INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date) VALUES
    ('99999101', 'T09D', 3, 'ENROLLED', 'NEW', '2024-03-01'),
    ('99999102', 'T09D', 1, 'ENROLLED', 'NEW', '2026-03-01');

INSERT INTO program_type (program_type_code, program_type_name) VALUES ('T09_TYPE', '테스트유형');
INSERT INTO program (program_type_code, program_name, program_date)
VALUES ('T09_TYPE', 'T09 테스트 프로그램', '2026-10-01');
INSERT INTO survey_question_category (category_code, category_name) VALUES ('T09_CAT', '테스트분류');
INSERT INTO survey (program_id, survey_name, start_date, end_date, status)
SELECT program_id, v.name, '2026-10-01', '2026-10-15', 'OPEN'
  FROM program, (VALUES ('T09 조사 A'), ('T09 조사 B')) AS v(name)
 WHERE program_name = 'T09 테스트 프로그램';
INSERT INTO survey_question (survey_id, category_code, display_order, question_text, question_type, scale_max)
SELECT s.survey_id, 'T09_CAT', v.ord, v.txt, v.typ, v.mx
  FROM survey s
  JOIN (VALUES ('T09 조사 A', 1, 'A 척도 1', 'SCALE', 5),
               ('T09 조사 A', 2, 'A 척도 2', 'SCALE', 5),
               ('T09 조사 A', 3, 'A 의견',   'TEXT',  NULL),
               ('T09 조사 B', 1, 'B 척도 1', 'SCALE', 5)) AS v(survey, ord, txt, typ, mx)
    ON v.survey = s.survey_name;

DO $t$
DECLARE
    sa INT; sb INT;
    qa1 INT; qa2 INT; qa3 INT; qb1 INT;
    r1 BIGINT; r2 BIGINT; r3 BIGINT;
    v_txt TEXT;
BEGIN
    SELECT survey_id INTO sa FROM survey WHERE survey_name = 'T09 조사 A';
    SELECT survey_id INTO sb FROM survey WHERE survey_name = 'T09 조사 B';
    SELECT question_id INTO qa1 FROM survey_question WHERE survey_id = sa AND display_order = 1;
    SELECT question_id INTO qa2 FROM survey_question WHERE survey_id = sa AND display_order = 2;
    SELECT question_id INTO qa3 FROM survey_question WHERE survey_id = sa AND display_order = 3;
    SELECT question_id INTO qb1 FROM survey_question WHERE survey_id = sb AND display_order = 1;

    -- 1. 척도 문항 설정: SCALE인데 척도 최대값이 5가 아님
    PERFORM pg_temp.t_expect_error('1. 척도 최대값이 5가 아닌 척도 문항',
        format($q$INSERT INTO survey_question (survey_id, category_code, display_order, question_text, question_type, scale_max)
                  VALUES (%s, 'T09_CAT', 9, '10점 척도', 'SCALE', 10)$q$, sa), '23514');

    -- 응답 헤더 (미완료로 시작) → 스냅샷 자동 입력
    INSERT INTO survey_response (survey_id, student_no, responded_at)
    VALUES (sa, '99999101', TIMESTAMPTZ '2026-10-02 10:00+09') RETURNING response_id INTO r1;
    SELECT grade_at_response || '/' || dept_code_at_response INTO v_txt
      FROM survey_response WHERE response_id = r1;
    PERFORM pg_temp.t_check('2. 응답 시점 학년·학과 자동 입력 (3/T09D)', v_txt = '3/T09D', v_txt);

    -- 3~6. 점수 범위
    PERFORM pg_temp.t_expect_error('3. 점수 0',
        format('INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (%s, %s, 0)', r1, qa1), '23514');
    PERFORM pg_temp.t_expect_error('4. 점수 6',
        format('INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (%s, %s, 6)', r1, qa1), '23514');
    PERFORM pg_temp.t_expect_ok('5. 점수 5 (상한 경계)',
        format('INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (%s, %s, 5)', r1, qa1));

    -- 6~9. 답변 유형·소속
    PERFORM pg_temp.t_expect_error('6. 척도 문항에 의견만 입력',
        format($q$INSERT INTO survey_response_detail (response_id, question_id, text_answer) VALUES (%s, %s, '좋음')$q$, r1, qa2), '23514');
    PERFORM pg_temp.t_expect_error('7. 점수와 의견을 함께 입력',
        format($q$INSERT INTO survey_response_detail (response_id, question_id, score, text_answer) VALUES (%s, %s, 3, '좋음')$q$, r1, qa2), '23514');
    PERFORM pg_temp.t_expect_ok('8. 점수 1 (하한 경계)',
        format('INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (%s, %s, 1)', r1, qa2));
    PERFORM pg_temp.t_expect_error('9. 주관식 문항에 점수 입력',
        format('INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (%s, %s, 3)', r1, qa3), '23514');
    PERFORM pg_temp.t_expect_error('10. 다른 조사의 문항에 답변',
        format('INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (%s, %s, 3)', r1, qb1), '23514');

    -- 11~13. 완료 조건
    PERFORM pg_temp.t_expect_error('11. 주관식을 답하지 않고 완료 처리',
        format('UPDATE survey_response SET is_completed = true WHERE response_id = %s', r1), '23514');
    PERFORM pg_temp.t_expect_ok('12. 주관식 답변 입력',
        format($q$INSERT INTO survey_response_detail (response_id, question_id, text_answer) VALUES (%s, %s, '첫 응답 의견')$q$, r1, qa3));
    PERFORM pg_temp.t_expect_ok('13. 모든 문항 답변 후 완료 처리',
        format('UPDATE survey_response SET is_completed = true WHERE response_id = %s', r1));

    -- 14·15. 완료 후 변경 금지
    PERFORM pg_temp.t_expect_error('14. 완료된 응답의 점수 수정',
        format('UPDATE survey_response_detail SET score = 4 WHERE response_id = %s AND question_id = %s', r1, qa1), 'P0001');
    PERFORM pg_temp.t_expect_error('15. 처음부터 완료 상태로 응답 등록',
        format($q$INSERT INTO survey_response (survey_id, student_no, is_completed) VALUES (%s, '99999102', true)$q$, sa), '23514');

    -- 16. 중복 응답 허용: 같은 학생이 다시 응답 (2점, 2점)
    INSERT INTO survey_response (survey_id, student_no, responded_at)
    VALUES (sa, '99999101', TIMESTAMPTZ '2026-10-05 10:00+09') RETURNING response_id INTO r2;
    INSERT INTO survey_response_detail (response_id, question_id, score, text_answer) VALUES
        (r2, qa1, 2, NULL), (r2, qa2, 2, NULL), (r2, qa3, NULL, '재응답 의견');
    UPDATE survey_response SET is_completed = true WHERE response_id = r2;
    PERFORM pg_temp.t_check('16. 같은 학생의 재응답 허용 (완료 응답 2건)',
        (SELECT count(*) = 2 FROM survey_response
          WHERE survey_id = sa AND student_no = '99999101' AND is_completed));

    -- 17. 다른 학생의 미완료 응답 (1점) → 집계 제외 대상
    INSERT INTO survey_response (survey_id, student_no, responded_at)
    VALUES (sa, '99999102', TIMESTAMPTZ '2026-10-06 10:00+09') RETURNING response_id INTO r3;
    INSERT INTO survey_response_detail (response_id, question_id, score) VALUES (r3, qa1, 1);

    -- 17. Q10과 같은 기준: 학생·조사별 최신 완료 응답만
    SELECT format('최종응답=%s 문항1평균=%s',
                  string_agg(DISTINCT f.response_id::text, ','),
                  round(avg(d.score) FILTER (WHERE d.question_id = qa1), 2))
      INTO v_txt
      FROM (SELECT DISTINCT ON (r.survey_id, r.student_no) r.response_id
              FROM survey_response r
             WHERE r.is_completed AND r.survey_id = sa
             ORDER BY r.survey_id, r.student_no, r.responded_at DESC, r.response_id DESC) f
      JOIN survey_response_detail d ON d.response_id = f.response_id;
    PERFORM pg_temp.t_check('17. 최종 응답은 재응답 1건, 문항1 평균 2.00 (첫 응답 5점·미완료 1점 제외)',
        v_txt = format('최종응답=%s 문항1평균=2.00', r2), v_txt);

    -- 18. 비교: 기준을 바꾸면 결과가 달라짐
    SELECT format('원본평균=%s 완료평균=%s',
                  round(avg(d.score), 2),
                  round(avg(d.score) FILTER (WHERE r.is_completed), 2))
      INTO v_txt
      FROM survey_response_detail d JOIN survey_response r ON r.response_id = d.response_id
     WHERE d.question_id = qa1;
    PERFORM pg_temp.t_check('18. 비교: 원본 평균 2.67 (5,2,1), 완료 평균 3.50 (5,2) → 기준에 따라 달라짐',
        v_txt = '원본평균=2.67 완료평균=3.50', v_txt);
END;
$t$;

\ir _report.sql
ROLLBACK;
