-- =====================================================================
-- T08_budget_limit.sql : 예산 한도 초과 승인 시도, 무지출 항목, 0 나누기 방지
-- 담당: 임영효
-- 실행: psql -d swknu_db -f tests/T08_budget_limit.sql
--
-- 시나리오 (미션 7장)
--   입력        누적 승인 지출이 지출한도를 넘게 되는 지출의 승인 시도
--   예상 결과   팀 정책: 승인 차단 (한도의 90% 이상이면 승인은 하되 경고 NOTICE — T07에서 확인)
--               한도와 정확히 같아지는 승인은 허용. 대기·반려 지출은 한도 계산에 넣지 않음
--   구현 방법   - fn_approve_expenditure: initial_budget 행 FOR UPDATE 잠금 →
--                 기승인 합계 + 이번 금액 > expenditure_limit 이면 RAISE (함수를 거칠 때 강제)
--                 여러 행의 합계가 필요하므로 단순 CHECK로는 구현할 수 없다 (미션 8장)
--               - ck_initial_budget_limit: 지출한도 ≤ 최초예산 (CHECK, 자동 강제)
--               - 잔액·집행률: 저장하지 않고 Q08과 같은 식으로 조회 시 계산, NULLIF로 0 나누기 방지
--
-- 동시 승인 경쟁(두 세션이 같은 항목을 동시에 승인)은 한 세션 안에서 재현할 수 없어 여기서는
-- 확인하지 않는다. 함수가 initial_budget 행을 잠그므로 두 번째 승인은 첫 승인 커밋 후 합계로 검사된다.
-- =====================================================================
\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 준비: 예산·지출 권한 관리자, 사업 1, 항목 5
--   T08_A : 예산 1,000,000 / 한도 1,000,000  → 경계·초과
--   T08_B : 예산 1,000,000 / 한도   600,000  → 잔액은 남아도 한도로 차단
--   T08_C : 예산 1,000,000 / 한도 1,000,000  → 대기·반려는 한도 계산에서 제외
--   T08_Z : 예산   500,000 / 한도   500,000  → 승인 지출 없는 항목
--   T08_0 : 예산         0 / 한도         0  → 집행률 0 나누기 방지
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type)
VALUES ('99998901', 't08.admin', crypt('x', gen_salt('bf')), '테스트관리자', 'ADMIN');
INSERT INTO admin (staff_no) VALUES ('99998901');
INSERT INTO permission (permission_code, permission_name) VALUES
    ('BUDGET_MANAGE', '예산 관리'), ('EXPENDITURE_MANAGE', '지출 등록·승인·반려')
ON CONFLICT (permission_code) DO NOTHING;
INSERT INTO role (role_name, description) VALUES ('T08_ROLE', '테스트');
INSERT INTO role_permission (role_id, permission_id)
SELECT r.role_id, p.permission_id FROM role r, permission p
 WHERE r.role_name = 'T08_ROLE' AND p.permission_code IN ('BUDGET_MANAGE', 'EXPENDITURE_MANAGE');
INSERT INTO user_role (user_id, role_id)
SELECT '99998901', role_id FROM role WHERE role_name = 'T08_ROLE';

INSERT INTO budget_project (project_year, project_phase, project_name, start_date, end_date)
VALUES (2099, 98, 'T08 테스트 사업', '2099-01-01', '2099-12-31');
INSERT INTO budget_item (item_code, item_name) VALUES
    ('T08_A', '경계 항목'), ('T08_B', '한도 낮은 항목'), ('T08_C', '대기 포함 항목'),
    ('T08_Z', '무지출 항목'), ('T08_0', '예산 0 항목'), ('T08_X', '한도 CHECK 확인용');
INSERT INTO initial_budget (project_id, budget_item_id, initial_amount, expenditure_limit, created_by)
SELECT bp.project_id, bi.budget_item_id, v.init, v.lim, '99998901'
  FROM budget_project bp
  JOIN (VALUES ('T08_A', 1000000, 1000000), ('T08_B', 1000000, 600000), ('T08_C', 1000000, 1000000),
               ('T08_Z', 500000, 500000),   ('T08_0', 0, 0)) AS v(code, init, lim) ON TRUE
  JOIN budget_item bi ON bi.item_code = v.code
 WHERE bp.project_name = 'T08 테스트 사업';
INSERT INTO professor (professor_id, professor_name) VALUES ('T08PROF', '테스트교수');

DO $t$
DECLARE
    v_proj INT;
    i_a INT; i_b INT; i_c INT; i_z INT; i_0 INT;
    e BIGINT;
    v_txt TEXT;
BEGIN
    SELECT project_id INTO v_proj FROM budget_project WHERE project_name = 'T08 테스트 사업';
    SELECT budget_item_id INTO i_a FROM budget_item WHERE item_code = 'T08_A';
    SELECT budget_item_id INTO i_b FROM budget_item WHERE item_code = 'T08_B';
    SELECT budget_item_id INTO i_c FROM budget_item WHERE item_code = 'T08_C';
    SELECT budget_item_id INTO i_z FROM budget_item WHERE item_code = 'T08_Z';
    SELECT budget_item_id INTO i_0 FROM budget_item WHERE item_code = 'T08_0';

    PERFORM fn_confirm_initial_budget(v_proj, i_a, '99998901');
    PERFORM fn_confirm_initial_budget(v_proj, i_b, '99998901');
    PERFORM fn_confirm_initial_budget(v_proj, i_c, '99998901');
    PERFORM fn_confirm_initial_budget(v_proj, i_z, '99998901');
    PERFORM fn_confirm_initial_budget(v_proj, i_0, '99998901');

    -- 1. 지출한도 > 최초예산 은 등록 불가
    PERFORM pg_temp.t_expect_error('1. 지출한도가 최초예산보다 큰 예산 등록',
        format($q$INSERT INTO initial_budget (project_id, budget_item_id, initial_amount, expenditure_limit, created_by)
                  SELECT %s, budget_item_id, 100, 200, '99998901' FROM budget_item WHERE item_code = 'T08_X'$q$,
               v_proj), '23514');

    -- 2·3. A: 600,000 + 400,000 = 한도 1,000,000 정확히 → 허용
    e := fn_create_expenditure(v_proj, i_a, '2099-03-01', 'MAJOR', 'T08PROF', 600000, 'A-1', '99998901');
    PERFORM fn_approve_expenditure(e, '99998901');
    e := fn_create_expenditure(v_proj, i_a, '2099-03-02', 'MAJOR', 'T08PROF', 400000, 'A-2', '99998901');
    PERFORM pg_temp.t_expect_ok('2. 누적이 한도와 정확히 같아지는 승인 (1,000,000 / 1,000,000)',
        format('SELECT fn_approve_expenditure(%s, %L)', e, '99998901'));

    -- 3. A: 1원 초과 → 차단, 상태 PENDING 유지
    e := fn_create_expenditure(v_proj, i_a, '2099-03-03', 'MAJOR', 'T08PROF', 1, 'A-3', '99998901');
    PERFORM pg_temp.t_expect_error('3. 한도를 1원 넘는 승인',
        format('SELECT fn_approve_expenditure(%s, %L)', e, '99998901'), 'P0001');
    PERFORM pg_temp.t_check('4. 차단된 지출은 PENDING 유지',
        (SELECT status = 'PENDING' FROM expenditure WHERE expenditure_id = e));

    -- 5·6. B: 한도 600,000 < 예산 1,000,000. 600,000 승인 후 100,000 → 예산 잔액 400,000이 남아도 차단
    e := fn_create_expenditure(v_proj, i_b, '2099-04-01', 'MAJOR', 'T08PROF', 600000, 'B-1', '99998901');
    PERFORM fn_approve_expenditure(e, '99998901');
    e := fn_create_expenditure(v_proj, i_b, '2099-04-02', 'MAJOR', 'T08PROF', 100000, 'B-2', '99998901');
    PERFORM pg_temp.t_expect_error('5. 예산 잔액은 남았지만 지출한도를 넘는 승인',
        format('SELECT fn_approve_expenditure(%s, %L)', e, '99998901'), 'P0001');
    SELECT format('예산 잔액 %s / 한도 잔여 %s',
                  ib.initial_amount - COALESCE(sum(x.amount), 0),
                  ib.expenditure_limit - COALESCE(sum(x.amount), 0))
      INTO v_txt
      FROM initial_budget ib
      LEFT JOIN expenditure x ON x.project_id = ib.project_id AND x.budget_item_id = ib.budget_item_id
                             AND x.status = 'APPROVED'
     WHERE ib.project_id = v_proj AND ib.budget_item_id = i_b
     GROUP BY ib.initial_amount, ib.expenditure_limit;
    PERFORM pg_temp.t_check('6. B 항목: 예산 잔액 400,000, 한도 잔여 0',
        v_txt = '예산 잔액 400000 / 한도 잔여 0', v_txt);

    -- 7. C: 대기 900,000·반려 200,000은 한도 계산 제외 → 500,000 승인 허용
    e := fn_create_expenditure(v_proj, i_c, '2099-05-01', 'MAJOR', 'T08PROF', 900000, 'C-대기', '99998901');
    e := fn_create_expenditure(v_proj, i_c, '2099-05-02', 'MAJOR', 'T08PROF', 200000, 'C-반려', '99998901');
    PERFORM fn_reject_expenditure(e, '99998901', '테스트 반려');
    e := fn_create_expenditure(v_proj, i_c, '2099-05-03', 'MAJOR', 'T08PROF', 500000, 'C-승인', '99998901');
    PERFORM pg_temp.t_expect_ok('7. 대기·반려 지출은 한도 계산에서 제외 (500,000 승인)',
        format('SELECT fn_approve_expenditure(%s, %L)', e, '99998901'));

    -- 8. 승인 지출 합계가 모든 항목에서 한도 이하
    PERFORM pg_temp.t_check('8. 모든 항목의 승인 합계 ≤ 지출한도',
        NOT EXISTS (
            SELECT 1 FROM initial_budget ib
              LEFT JOIN expenditure x ON x.project_id = ib.project_id
                                     AND x.budget_item_id = ib.budget_item_id
                                     AND x.status = 'APPROVED'
             WHERE ib.project_id = v_proj
             GROUP BY ib.project_id, ib.budget_item_id, ib.expenditure_limit
            HAVING COALESCE(sum(x.amount), 0) > ib.expenditure_limit));

    -- 9~11. Q08과 같은 계산식: 항목별로 먼저 합산 → LEFT JOIN → NULLIF
    SELECT string_agg(format('%s 승인=%s 잔액=%s 집행률=%s',
                             bi.item_code, COALESCE(a.amt, 0),
                             ib.initial_amount - COALESCE(a.amt, 0),
                             COALESCE(round(100.0 * COALESCE(a.amt, 0) / NULLIF(ib.initial_amount, 0), 2)::text, 'NULL')),
                      ' | ' ORDER BY bi.item_code)
      INTO v_txt
      FROM initial_budget ib
      JOIN budget_item bi ON bi.budget_item_id = ib.budget_item_id
      LEFT JOIN (SELECT budget_item_id, sum(amount) AS amt FROM expenditure
                  WHERE project_id = v_proj AND status = 'APPROVED' GROUP BY budget_item_id) a
             ON a.budget_item_id = ib.budget_item_id
     WHERE ib.project_id = v_proj AND bi.item_code IN ('T08_Z', 'T08_0');
    PERFORM pg_temp.t_check('9. 무지출 항목 Z: 승인 0, 잔액 = 예산 500,000, 집행률 0.00',
        v_txt LIKE '%T08_Z 승인=0 잔액=500000 집행률=0.00%', v_txt);
    PERFORM pg_temp.t_check('10. 예산 0 항목: 집행률 NULL (0 나누기 에러 없음)',
        v_txt LIKE '%T08_0 승인=0 잔액=0 집행률=NULL%', v_txt);

    SELECT format('A=%s B=%s C=%s',
                  sum(amount) FILTER (WHERE budget_item_id = i_a),
                  sum(amount) FILTER (WHERE budget_item_id = i_b),
                  sum(amount) FILTER (WHERE budget_item_id = i_c))
      INTO v_txt
      FROM expenditure WHERE project_id = v_proj AND status = 'APPROVED';
    PERFORM pg_temp.t_check('11. 승인 합계 A 1,000,000 / B 600,000 / C 500,000',
        v_txt = 'A=1000000 B=600000 C=500000', v_txt);
END;
$t$;

\ir _report.sql
ROLLBACK;
