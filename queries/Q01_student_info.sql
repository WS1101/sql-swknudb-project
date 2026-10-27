-- =====================================================================
-- Q01_student_info.sql : 특정 학생의 기본정보 조회
-- 담당: 서우진
--
-- 목적
--   학생 한 명의 인적사항(소속대학·캠퍼스·학과·학적·입학·연락처·누적 마일리지)을 조회한다.
--
-- 입력 (psql 변수, 생략 시 기본값)
--   q01_student_no : 조회 대상 학번          기본 20230001
--   q01_requester  : 조회를 요청한 사용자 ID  기본 20230001 (본인 조회)
--   예) psql -d swknu_db -v q01_student_no=20230002 -v q01_requester=90000002 -f queries/Q01_student_info.sql
--
-- 조회 범위 규칙 (보고서 6.1, FR-8-02)
--   아래 중 하나일 때만 행이 반환된다.
--   - 요청자 = 대상 본인 이고, 요청자에게 STUDENT_READ_SELF 권한이 있음
--   - 요청자에게 STUDENT_READ_ALL 권한이 있음 (일반·마스터 관리자)
--   비활성 계정은 권한이 있어도 반환하지 않는다.
--
--   이 조건은 "쿼리 수준"의 범위 제한이다. app_user에 계정이 있다는 것만으로
--   접근이 통제되지 않으며, 이 조건 없이 student를 직접 SELECT하면 누구나 조회된다.
--   DB 계정 권한·RLS로 차단하는 것은 구현 범위 밖이다 (README 미구현 범위, T10에서 확인).
--
-- 예상 결과 (기본 입력, reset 직후)
--   [1] 조회 허용: true
--   [2] 1행
--       20230001 가상학생01 / 가상공과대학 / 가상본캠퍼스 / 가상컴퓨터공학과 / 4학년 / ENROLLED
--       학적변동 없음 / NEW 2023-03-01
--       휴대폰 000-0000-9001   ← 9/2 승인 반영. 10/3 반려된 9101은 미반영
--       SMS true
--       이메일 student01@example.invalid   ← 10/13 요청은 대기라 미반영
--       누적 마일리지 210 (SW 가치확산 활동 입상 60 + TOPCIT 2026_2 452점 150)
--   다른 학생(20230002)이 요청하면 [1] false, [2] 0행
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q01_student_no}
\else
\set q01_student_no 20230001
\endif
\if :{?q01_requester}
\else
\set q01_requester 20230001
\endif
\pset null '-'

\echo '=== Q01 학생 기본정보 / 대상:' :q01_student_no '/ 요청자:' :q01_requester

-- [1] 조회 허용 여부 (시연용: 왜 0행인지 확인)
WITH requester_permission AS (
    SELECT p.permission_code
      FROM app_user u
      JOIN user_role ur       ON ur.user_id = u.user_id
      JOIN role_permission rp ON rp.role_id = ur.role_id
      JOIN permission p       ON p.permission_id = rp.permission_id
     WHERE u.user_id = :'q01_requester'
       AND u.is_active
)
SELECT :'q01_requester'  AS 요청자,
       :'q01_student_no' AS 대상,
       (   (:'q01_requester' = :'q01_student_no'
            AND EXISTS (SELECT 1 FROM requester_permission WHERE permission_code = 'STUDENT_READ_SELF'))
        OR EXISTS (SELECT 1 FROM requester_permission WHERE permission_code = 'STUDENT_READ_ALL')
       ) AS 조회허용;

-- [2] 기본정보
WITH requester_permission AS (
    SELECT p.permission_code
      FROM app_user u
      JOIN user_role ur       ON ur.user_id = u.user_id
      JOIN role_permission rp ON rp.role_id = ur.role_id
      JOIN permission p       ON p.permission_id = rp.permission_id
     WHERE u.user_id = :'q01_requester'
       AND u.is_active
)
SELECT s.student_no          AS 학번,
       u.user_name           AS 성명,
       c.college_name        AS 소속대학,
       cp.campus_name        AS 캠퍼스,
       d.dept_name           AS 학과,
       d.track_type          AS 계열,
       s.grade               AS 학년,
       s.enrollment_status   AS 학적상태,
       s.status_change_type  AS 학적변동,
       s.status_change_date  AS 학적변동일자,
       s.admission_type      AS 입학구분,
       s.admission_date      AS 입학일자,
       s.phone_number        AS 휴대폰번호,
       s.sms_opt_in          AS sms수신,
       s.email               AS 이메일,
       s.cumulative_mileage  AS 누적마일리지
  FROM student s
  JOIN app_user u    ON u.user_id = s.student_no
  JOIN department d  ON d.dept_code = s.dept_code
  JOIN college c     ON c.college_code = d.college_code
  JOIN campus cp     ON cp.campus_code = d.campus_code
 WHERE s.student_no = :'q01_student_no'
   AND (   (s.student_no = :'q01_requester'
            AND EXISTS (SELECT 1 FROM requester_permission WHERE permission_code = 'STUDENT_READ_SELF'))
        OR EXISTS (SELECT 1 FROM requester_permission WHERE permission_code = 'STUDENT_READ_ALL'));
