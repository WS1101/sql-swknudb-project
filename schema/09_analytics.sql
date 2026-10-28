\encoding UTF8
-- 09_analytics.sql : 분석용 뷰와 조회 권한
-- 담당: 서우진
-- 구성
--   analytics 스키마         업무 테이블(public)과 분리된 분석 공간
--   v_survey_response_final  학생·조사별 최신 완료 응답 (Q10·Q11의 집계 기준을 뷰로 고정)
--   v_satisfaction_summary   학기·프로그램유형·문항분류·학과·학년별 만족도 집계
--   v_student_features       학생별 특성 (학과·학년·마일리지·TOPCIT·만족도). 이름·연락처 없음
--   analytics_reader         분석 전용 DB 계정: analytics 뷰만 조회, public 테이블은 접근 불가
-- 조회 권한
--   뷰는 "뷰를 만든 계정"의 권한으로 원본 테이블을 읽는다. 그래서 analytics_reader에게
--   원본 테이블 권한 없이 뷰 조회 권한만 주면, 뷰에 포함된 컬럼만 볼 수 있다.
--   → 연락처·비밀번호 해시·변경 로그는 DB 차원에서 차단된다 (T13에서 시연).
-- 재실행 참고
--   reset.sql이 analytics 스키마를 먼저 지운 뒤 다시 만든다.
--   DB 계정(ROLE)은 데이터베이스 전체에 걸친 객체라 스키마를 지워도 남으므로, 없을 때만 만든다.
--   계정 생성과 SET ROLE 시연에는 superuser(또는 CREATEROLE) 권한이 필요하다.
-- 예측 모델 결과 테이블(model_run 등)은 데이터 규모·학기 범위 한계로 이번 범위에서 제외했다.

CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA analytics IS '분석용 뷰. 업무 테이블(public)과 분리, analytics_reader 계정만 조회';

-- 학생·조사별 최신 완료 응답
--   미완료 응답 제외, 같은 학생의 재응답은 가장 최근(같으면 response_id 큰 것) 1건
--   학기는 프로그램 일자가 속한 academic_term (학기는 저장하지 않고 날짜로 계산하는 원칙)
CREATE OR REPLACE VIEW analytics.v_survey_response_final AS
SELECT DISTINCT ON (r.survey_id, r.student_no)
       r.response_id,
       r.survey_id,
       s.program_id,
       p.program_type_code,
       t.term_year,
       t.term_code,
       r.student_no,
       r.dept_code_at_response AS dept_code,
       r.grade_at_response     AS grade,
       r.responded_at
  FROM survey_response r
  JOIN survey s              ON s.survey_id = r.survey_id
  JOIN program p             ON p.program_id = s.program_id
  LEFT JOIN academic_term t  ON p.program_date BETWEEN t.start_date AND t.end_date
 WHERE r.is_completed
 ORDER BY r.survey_id, r.student_no, r.responded_at DESC, r.response_id DESC;

COMMENT ON VIEW analytics.v_survey_response_final IS
    '학생·조사별 최신 완료 응답 1건. 학과·학년은 응답 시점 스냅샷';

-- 만족도 집계 (척도 문항만)
--   평균만 두면 상위 단위로 다시 묶을 때 평균의 평균이 되어 틀리므로,
--   점수 합계(score_sum)와 점수 개수(score_count)를 함께 제공한다.
--   상위 집계 평균 = sum(score_sum) / sum(score_count)
CREATE OR REPLACE VIEW analytics.v_satisfaction_summary AS
SELECT f.term_year,
       f.term_code,
       f.program_type_code,
       pt.program_type_name,
       q.category_code,
       c.category_name,
       f.dept_code,
       dp.dept_name,
       f.grade,
       count(DISTINCT f.response_id)               AS respondent_count,
       count(d.score)                              AS score_count,
       sum(d.score)                                AS score_sum,
       round(avg(d.score), 2)                      AS avg_score,
       count(*) FILTER (WHERE d.score >= 4)        AS satisfied_count
  FROM analytics.v_survey_response_final f
  JOIN survey_response_detail d     ON d.response_id = f.response_id
  JOIN survey_question q            ON q.question_id = d.question_id
  JOIN survey_question_category c   ON c.category_code = q.category_code
  JOIN program_type pt              ON pt.program_type_code = f.program_type_code
  JOIN department dp                ON dp.dept_code = f.dept_code
 WHERE q.question_type = 'SCALE'
 GROUP BY f.term_year, f.term_code, f.program_type_code, pt.program_type_name,
          q.category_code, c.category_name, f.dept_code, dp.dept_name, f.grade;

COMMENT ON VIEW analytics.v_satisfaction_summary IS
    '학기·프로그램유형·문항분류·학과·학년별 척도 점수 집계. 상위 집계는 score_sum/score_count 사용';

-- 학생별 특성 (분석·모델 입력용)
--   포함: 학번(연결 키), 학과, 계열, 학년, 학적, 입학구분, 마일리지, TOPCIT, 만족도
--   제외: 성명, 휴대폰, 이메일, SMS 수신여부, 비밀번호
--   마일리지는 캐시값(student.cumulative_mileage)이 아니라 승인 내역에서 다시 계산한다.
--   각 영역을 학생별로 먼저 합산한 뒤 LEFT JOIN → 영역끼리 곱해져 값이 부풀지 않음
CREATE OR REPLACE VIEW analytics.v_student_features AS
WITH mileage_agg AS (
    SELECT student_no,
           sum(requested_mileage)                               AS approved_mileage,
           count(*)                                             AS approved_count,
           count(*) FILTER (WHERE source_type = 'PROGRAM')      AS program_approved_count
      FROM mileage_application
     WHERE status = 'APPROVED'
     GROUP BY student_no
), topcit_agg AS (
    SELECT ts.student_no,
           count(*)                                                                   AS round_count,
           (array_agg(ts.total_score ORDER BY r.exam_date, r.round_id))[1]            AS first_score,
           (array_agg(ts.total_score ORDER BY r.exam_date DESC, r.round_id DESC))[1]  AS latest_score
      FROM topcit_score ts
      JOIN topcit_exam_round r ON r.round_id = ts.round_id
     GROUP BY ts.student_no
), survey_agg AS (
    SELECT f.student_no,
           count(DISTINCT f.response_id)  AS response_count,
           round(avg(d.score), 2)         AS avg_score
      FROM analytics.v_survey_response_final f
      JOIN survey_response_detail d ON d.response_id = f.response_id
      JOIN survey_question q        ON q.question_id = d.question_id
     WHERE q.question_type = 'SCALE'
     GROUP BY f.student_no
)
SELECT s.student_no,
       s.dept_code,
       dp.dept_name,
       dp.track_type,
       s.grade,
       s.enrollment_status,
       s.admission_type,
       COALESCE(m.approved_mileage, 0)         AS approved_mileage,
       COALESCE(m.approved_count, 0)           AS mileage_approved_count,
       COALESCE(m.program_approved_count, 0)   AS program_approved_count,
       COALESCE(t.round_count, 0)              AS topcit_round_count,
       t.first_score                           AS topcit_first_score,
       t.latest_score                          AS topcit_latest_score,
       t.latest_score - t.first_score          AS topcit_change,
       COALESCE(sv.response_count, 0)          AS survey_response_count,
       sv.avg_score                            AS avg_satisfaction
  FROM student s
  JOIN department dp      ON dp.dept_code = s.dept_code
  LEFT JOIN mileage_agg m ON m.student_no = s.student_no
  LEFT JOIN topcit_agg t  ON t.student_no = s.student_no
  LEFT JOIN survey_agg sv ON sv.student_no = s.student_no;

COMMENT ON VIEW analytics.v_student_features IS
    '학생별 특성. 이름·연락처 제외. 마일리지는 승인 내역 기준 재계산';

-- 분석 전용 계정
--   NOLOGIN: 직접 로그인하지 않고, 실제 서비스에서는 분석 사용자 계정에 이 역할을 부여한다.
--   시연은 superuser가 SET ROLE analytics_reader 로 전환해서 확인한다.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analytics_reader') THEN
        CREATE ROLE analytics_reader NOLOGIN;
    END IF;
END;
$$;

-- 업무 테이블 권한은 명시적으로 회수 (기본적으로도 없지만 의도를 분명히 함)
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM analytics_reader;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM analytics_reader;

-- analytics 뷰만 조회 허용
GRANT USAGE ON SCHEMA analytics TO analytics_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO analytics_reader;
