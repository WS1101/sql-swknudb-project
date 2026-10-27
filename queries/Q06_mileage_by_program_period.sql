-- =====================================================================
-- Q06_mileage_by_program_period.sql : 프로그램별·기간별 마일리지 승인 내역 및 합계
-- 담당: 김건희
--
-- 목적
--   지정한 기간에 승인된 마일리지 내역과 프로그램(및 TOPCIT 회차)별 합계를 보여준다.
--
-- 입력
--   q06_from : 시작일 (포함)   기본 2026-09-01
--   q06_to   : 종료일 (포함)   기본 2026-12-31   ← 2026학년도 2학기 (academic_term 2026-2)
--   학기 단위로 보려면 academic_term의 start_date, end_date를 그대로 넣는다.
--
-- 기준
--   - 기간 기준 날짜: 승인일 (approved_at을 한국 시간으로 바꾼 날짜). 신청일·프로그램 일자가 아님
--   - 집계 대상 상태: APPROVED 만. 회수된 건은 REVOKED라 제외되며,
--     회수 시 approved_at이 회수 시각으로 바뀌므로 상태 조건 없이 기간만 보면 안 된다
--   - 관리자 직권등록은 등록 시각 = 승인 시각
--   - [2]는 마일리지 기준이 있는 프로그램 전체를 보여주고, 기간 내 승인이 없으면 0
--
-- 예상 결과 (기본 입력)
--   [1] 승인 내역 13건
--     9/9   TOPCIT 대비 특강 입상 75 × 3 (20230003, 20240013, 20250023)
--     10/6  20260029 산학캡스톤디자인 캠프 참여 30
--     10/15 TOPCIT 2026_2: 20230001 150, 20230005 150, 20240009 150, 20240013 150, 20250017 100
--     10/19 20260030 지역사회 SW 가치확산 활동 참여 40 (관리자 직권등록)
--     10/20 20240010 지역사회 SW 가치확산 활동 참여 40
--     10/21 지역사회 SW 가치확산 활동 입상 90 × 2 (20230006, 20240016)
--   [2] TOPCIT 대비 특강 3건(입상 3) 225 / 산학캡스톤디자인 캠프 1건 30 /
--       지역사회 SW 가치확산 활동 4건(참여 2, 입상 2) 260 / TOPCIT SEED_TOPCIT_2026_2 5건 700
--       나머지 프로그램 0, 합계 13건 1,215
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q06_from}
\else
\set q06_from 2026-09-01
\endif
\if :{?q06_to}
\else
\set q06_to 2026-12-31
\endif
\pset null '-'

\echo '=== Q06 기간별 마일리지 승인 / 승인일 기준:' :q06_from '~' :q06_to

-- [1] 승인 내역
SELECT (ma.approved_at AT TIME ZONE 'Asia/Seoul')         AS 승인일시,
       ma.application_id                                  AS 신청id,
       ma.student_no                                      AS 학번,
       u.user_name                                        AS 성명,
       ma.source_type                                     AS 근거유형,
       COALESCE(p.program_name, r.round_name)             AS 프로그램_회차,
       ma.participation_type                              AS 참여구분,
       ts.total_score                                     AS topcit점수,
       ma.registration_path                               AS 등록경로,
       ma.requested_mileage                               AS 마일리지,
       ma.approved_by                                     AS 승인자
  FROM mileage_application ma
  JOIN app_user u                  ON u.user_id = ma.student_no
  LEFT JOIN program p              ON p.program_id = ma.program_id
  LEFT JOIN topcit_score ts        ON ts.score_id = ma.topcit_score_id
  LEFT JOIN topcit_exam_round r    ON r.round_id = ts.round_id
 WHERE ma.status = 'APPROVED'
   AND (ma.approved_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN :'q06_from'::date AND :'q06_to'::date
 ORDER BY ma.approved_at, ma.application_id;

-- [2] 프로그램·회차별 합계
WITH approved_in_period AS (
    SELECT ma.*
      FROM mileage_application ma
     WHERE ma.status = 'APPROVED'
       AND (ma.approved_at AT TIME ZONE 'Asia/Seoul')::date BETWEEN :'q06_from'::date AND :'q06_to'::date
), by_basis AS (
    -- 마일리지 기준이 있는 프로그램 (승인 0건도 표시)
    SELECT 'PROGRAM'::text                                             AS source_type,
           p.program_name                                              AS basis,
           p.program_date                                              AS basis_date,
           count(a.application_id)                                     AS approved_count,
           count(a.application_id) FILTER (WHERE a.participation_type = 'PARTICIPATION') AS participation_count,
           count(a.application_id) FILTER (WHERE a.participation_type = 'AWARD')         AS award_count,
           COALESCE(sum(a.requested_mileage), 0)                       AS mileage
      FROM program p
      JOIN mileage_criteria mc      ON mc.program_id = p.program_id
      LEFT JOIN approved_in_period a ON a.program_id = p.program_id
     GROUP BY p.program_id, p.program_name, p.program_date
    UNION ALL
    -- TOPCIT 회차 (기간 내 승인 있는 회차만)
    SELECT 'TOPCIT', r.round_name, r.exam_date,
           count(*), 0, 0, sum(a.requested_mileage)
      FROM approved_in_period a
      JOIN topcit_score ts       ON ts.score_id = a.topcit_score_id
      JOIN topcit_exam_round r   ON r.round_id = ts.round_id
     GROUP BY r.round_id, r.round_name, r.exam_date
)
SELECT 근거유형, 프로그램_회차, 일자, 승인건수, 참여, 입상, 합계
  FROM (
        SELECT 0                    AS sort_key,
               source_type          AS 근거유형,
               basis                AS 프로그램_회차,
               basis_date           AS 일자,
               approved_count       AS 승인건수,
               participation_count  AS 참여,
               award_count          AS 입상,
               mileage              AS 합계
          FROM by_basis
        UNION ALL
        SELECT 1, '합계', NULL, NULL,
               sum(approved_count), sum(participation_count), sum(award_count), sum(mileage)
          FROM by_basis
       ) t
 ORDER BY sort_key, 근거유형, 일자, 프로그램_회차;
