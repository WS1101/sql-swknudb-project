\encoding UTF8
-- =====================================================================
-- Q08_budget_balance.sql : 사업·예산항목별 예산, 승인 지출, 잔액, 집행률
-- 담당: 임영효
--
-- 목적
--   사업 × 예산항목마다 최초예산·지출한도·승인 지출·잔액·집행률을 보여주고 사업별 소계를 붙인다.
--
-- 입력
--   q08_year : 사업연도, 또는 ALL   기본 ALL
--
-- 기준 (보고서 5.6)
--   - 승인지출 = status = 'APPROVED' 지출 금액 합. 대기·반려·취소는 제외 (대기금액은 참고로 따로 표시)
--   - 잔액     = 최초예산 - 승인지출
--   - 한도잔여 = 지출한도 - 승인지출  (추가로 승인 가능한 금액)
--   - 집행률   = 승인지출 / 최초예산 × 100 (소수 둘째 자리). 최초예산이 0이면 NULLIF로 NULL
--   - 승인 지출이 없는 항목도 표시: initial_budget 기준 LEFT JOIN, 없으면 0
--   - 지출을 항목별로 먼저 합산한 뒤 JOIN → 승인·대기 두 합계를 붙여도 금액이 중복되지 않음
--   - 잔액·집행률은 저장하지 않고 조회 시 계산 (보고서 4.3)
--
-- 예상 결과 (기본 입력)
--   2025 소계  최초예산 620,000,000  한도 578,000,000  승인 51,900,000  잔액 568,100,000  집행률 8.37
--   2026 소계  최초예산 690,000,000  한도 639,000,000  승인 54,850,000  잔액 635,150,000  집행률 7.95
--   ★ 2026 간접비: 최초예산 45,000,000  승인 0 (0건)  잔액 45,000,000  한도잔여 42,000,000  집행률 0.00
--     → 승인 지출 없는 항목. 잔액 = 최초예산
--   2026 인건비: 최초예산 130,000,000  승인 18,000,000 (2건)  잔액 112,000,000  집행률 13.85  대기 6,000,000
--   2025 인건비: 최초예산 120,000,000  승인 16,500,000 (2건)  잔액 103,500,000  집행률 13.75
--   전체 승인지출 106,750,000
--
-- 실제 결과
--   (실행 후 기록)
-- =====================================================================

\if :{?q08_year}
\else
\set q08_year ALL
\endif
\pset null '-'

\echo '=== Q08 사업·예산항목별 예산·승인지출·잔액·집행률 / 연도:' :q08_year

WITH approved AS (
    SELECT project_id, budget_item_id,
           sum(amount) AS amount, count(*) AS cnt
      FROM expenditure
     WHERE status = 'APPROVED'
     GROUP BY project_id, budget_item_id
), pending AS (
    SELECT project_id, budget_item_id, sum(amount) AS amount
      FROM expenditure
     WHERE status = 'PENDING'
     GROUP BY project_id, budget_item_id
), base AS (
    SELECT bp.project_id,
           bp.project_year,
           bp.project_phase,
           bp.project_name,
           bi.item_code,
           bi.item_name,
           ib.status                      AS budget_status,
           ib.initial_amount,
           ib.expenditure_limit,
           COALESCE(a.amount, 0)          AS approved_amount,
           COALESCE(a.cnt, 0)             AS approved_count,
           COALESCE(pd.amount, 0)         AS pending_amount
      FROM initial_budget ib
      JOIN budget_project bp ON bp.project_id = ib.project_id
      JOIN budget_item bi    ON bi.budget_item_id = ib.budget_item_id
      LEFT JOIN approved a   ON a.project_id = ib.project_id
                            AND a.budget_item_id = ib.budget_item_id
      LEFT JOIN pending pd   ON pd.project_id = ib.project_id
                            AND pd.budget_item_id = ib.budget_item_id
     WHERE :'q08_year' = 'ALL' OR bp.project_year::text = :'q08_year'
)
SELECT project_year                                                    AS 사업연도,
       project_phase                                                   AS 차수,
       CASE WHEN GROUPING(item_code) = 1 THEN '◆ 사업 소계'
            ELSE item_name END                                         AS 예산항목,
       item_code                                                       AS 항목코드,
       sum(initial_amount)                                             AS 최초예산,
       sum(expenditure_limit)                                          AS 지출한도,
       sum(approved_amount)                                            AS 승인지출,
       sum(approved_count)                                             AS 승인건수,
       sum(initial_amount - approved_amount)                           AS 잔액,
       sum(expenditure_limit - approved_amount)                        AS 한도잔여,
       round(100.0 * sum(approved_amount) / NULLIF(sum(initial_amount), 0), 2) AS 집행률,
       sum(pending_amount)                                             AS 대기금액
  FROM base
 GROUP BY GROUPING SETS (
       (project_id, project_year, project_phase, item_code, item_name),
       (project_id, project_year, project_phase)
 )
 ORDER BY project_year, project_phase, GROUPING(item_code), item_code;
