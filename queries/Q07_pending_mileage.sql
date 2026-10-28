\encoding UTF8
-- Q07_pending_mileage.sql | 관리자가 확인할 승인대기 마일리지 신청 목록.
-- 담당: 김건희
-- q07_requester: 조회 관리자 ID(기본 90000001)
-- PENDING만 신청일 순으로 조회한다. 증빙이 여러 개여도 신청은 한 행으로 표시한다.
-- 경과일은 실행 날짜에 따라 달라진다.
-- 예상 결과(초기 데이터 기준)
--   15행, 모두 학생 신청(STUDENT_REQUEST), 증빙 각 1건
--     프로그램 참여 4: 20230001 SW·AI 경진대회 40 / 20260025 SW 가치확산 활동 25 /
--                      20250017 TOPCIT 대비 특강 35 / 20240009 산학캡스톤디자인 캠프 30
--     프로그램 입상 6: 산학캡스톤디자인 120 × 3 (20240010, 20250020, 20260030),
--                      산학캡스톤디자인 캠프 65 × 3 (20230005, 20240015, 20260025)
--     TOPCIT 5 (10/14 신청): 20230004 250, 20230008 250, 20240012 150, 20240016 150, 20250020 150
--   첫 행 20230001 (2026-03-30 신청), 마지막 행 20250020 TOPCIT
--   q07_requester=20230001 (학생)이면 0행

\if :{?q07_requester}
\else
\set q07_requester 90000001
\endif
\pset null '-'

\echo '=== Q07 승인대기 마일리지 신청 / 요청자:' :q07_requester

WITH requester_permission AS (
    SELECT p.permission_code
      FROM app_user u
      JOIN user_role ur       ON ur.user_id = u.user_id
      JOIN role_permission rp ON rp.role_id = ur.role_id
      JOIN permission p       ON p.permission_id = rp.permission_id
     WHERE u.user_id = :'q07_requester'
       AND u.is_active
)
SELECT ma.application_id                                          AS 신청id,
       (ma.applied_at AT TIME ZONE 'Asia/Seoul')                  AS 신청일시,
       current_date - (ma.applied_at AT TIME ZONE 'Asia/Seoul')::date AS 경과일,
       ma.student_no                                              AS 학번,
       u.user_name                                                AS 성명,
       d.dept_name                                                AS 학과,
       s.grade                                                    AS 학년,
       ma.source_type                                             AS 근거유형,
       COALESCE(p.program_name, r.round_name)                     AS 프로그램_회차,
       ma.participation_type                                      AS 참여구분,
       ts.total_score                                             AS topcit점수,
       ma.requested_mileage                                       AS 신청마일리지,
       ma.registration_path                                       AS 등록경로,
       ma.memo                                                    AS 메모,
       ev.file_count                                              AS 증빙수,
       ev.files                                                   AS 증빙파일
  FROM mileage_application ma
  JOIN student s                ON s.student_no = ma.student_no
  JOIN app_user u               ON u.user_id = ma.student_no
  JOIN department d             ON d.dept_code = s.dept_code
  LEFT JOIN program p           ON p.program_id = ma.program_id
  LEFT JOIN topcit_score ts     ON ts.score_id = ma.topcit_score_id
  LEFT JOIN topcit_exam_round r ON r.round_id = ts.round_id
  LEFT JOIN LATERAL (
        SELECT count(*)                                                     AS file_count,
               string_agg(a.file_name || ' (' || a.file_path || ')', ', '
                          ORDER BY a.attachment_id)                         AS files
          FROM attachment a
         WHERE a.application_id = ma.application_id
       ) ev ON TRUE
 WHERE ma.status = 'PENDING'
   AND EXISTS (SELECT 1 FROM requester_permission
                WHERE permission_code IN ('MILEAGE_MANAGE', 'MILEAGE_READ_ALL'))
 ORDER BY ma.applied_at, ma.application_id;
