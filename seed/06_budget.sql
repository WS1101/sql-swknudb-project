-- 두 사업연도, 7개 예산항목별 최초예산, 교수·주체별 지출 업무 흐름.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
SELECT pg_advisory_xact_lock(20261015, 6);

DO $$
DECLARE
    seed_record RECORD;
    v_project_id INT;
    v_expenditure_id BIGINT;
    v_count INT;
BEGIN
    FOR seed_record IN SELECT * FROM (VALUES
        (2025::SMALLINT, 1::SMALLINT, 'SEED 2025 SW중심대학사업', DATE '2025-01-01', DATE '2025-12-31', 'COMPLETED'),
        (2026::SMALLINT, 2::SMALLINT, 'SEED 2026 SW중심대학사업', DATE '2026-01-01', DATE '2026-12-31', 'ACTIVE')
    ) AS expected(project_year, project_phase, project_name, start_date, end_date, status)
    LOOP
        INSERT INTO budget_project (project_year, project_phase, project_name, start_date, end_date, status)
        VALUES (seed_record.project_year, seed_record.project_phase, seed_record.project_name,
                seed_record.start_date, seed_record.end_date, seed_record.status)
        ON CONFLICT (project_year, project_phase) DO NOTHING;
        IF NOT EXISTS (
            SELECT 1 FROM budget_project
             WHERE project_year = seed_record.project_year
               AND project_phase = seed_record.project_phase
               AND project_name = seed_record.project_name
               AND start_date = seed_record.start_date
               AND end_date = seed_record.end_date
               AND status = seed_record.status
        ) THEN
            RAISE EXCEPTION 'Seed 예산사업 충돌: %년 %차',
                seed_record.project_year, seed_record.project_phase;
        END IF;
    END LOOP;

    FOR seed_record IN
        WITH expected(item_code, initial_2025, limit_2025, initial_2026, limit_2026) AS (VALUES
            ('PERSONNEL',          120000000::BIGINT, 110000000::BIGINT, 130000000::BIGINT, 120000000::BIGINT),
            ('STUDENT_PERSONNEL',  100000000::BIGINT,  95000000::BIGINT, 115000000::BIGINT, 108000000::BIGINT),
            ('RESEARCH_EQUIPMENT', 150000000::BIGINT, 140000000::BIGINT, 170000000::BIGINT, 155000000::BIGINT),
            ('RESEARCH_ACTIVITY',   80000000::BIGINT,  75000000::BIGINT,  90000000::BIGINT,  84000000::BIGINT),
            ('RESEARCH_MATERIAL',   70000000::BIGINT,  65000000::BIGINT,  76000000::BIGINT,  70000000::BIGINT),
            ('RESEARCH_ALLOWANCE',  60000000::BIGINT,  55000000::BIGINT,  64000000::BIGINT,  60000000::BIGINT),
            ('INDIRECT',            40000000::BIGINT,  38000000::BIGINT,  45000000::BIGINT,  42000000::BIGINT)
        )
        SELECT bp.project_id, bp.project_year, bi.budget_item_id, e.item_code,
               CASE bp.project_year WHEN 2025 THEN e.initial_2025 ELSE e.initial_2026 END AS initial_amount,
               CASE bp.project_year WHEN 2025 THEN e.limit_2025 ELSE e.limit_2026 END AS expenditure_limit,
               make_timestamptz(bp.project_year, 1, 3, 9, 0, 0, 'Asia/Seoul') AS created_at
          FROM expected e JOIN budget_item bi USING (item_code)
          CROSS JOIN budget_project bp
         WHERE bp.project_name LIKE 'SEED % SW중심대학사업'
         ORDER BY bp.project_year, e.item_code
    LOOP
        INSERT INTO initial_budget (
            project_id, budget_item_id, initial_amount, expenditure_limit,
            status, created_by, created_at
        ) VALUES (
            seed_record.project_id, seed_record.budget_item_id,
            seed_record.initial_amount, seed_record.expenditure_limit,
            'UNCONFIRMED', '90000001', seed_record.created_at
        ) ON CONFLICT (project_id, budget_item_id) DO NOTHING;

        IF NOT EXISTS (
            SELECT 1 FROM initial_budget
             WHERE project_id = seed_record.project_id
               AND budget_item_id = seed_record.budget_item_id
               AND initial_amount = seed_record.initial_amount
               AND expenditure_limit = seed_record.expenditure_limit
               AND created_by = '90000001'
               AND created_at = seed_record.created_at
        ) THEN
            RAISE EXCEPTION 'Seed 최초예산 충돌: 사업 %, 항목 %',
                seed_record.project_id, seed_record.item_code;
        END IF;

        IF EXISTS (
            SELECT 1 FROM initial_budget
             WHERE project_id = seed_record.project_id
               AND budget_item_id = seed_record.budget_item_id
               AND status = 'UNCONFIRMED'
        ) THEN
            PERFORM fn_confirm_initial_budget(
                seed_record.project_id, seed_record.budget_item_id, '90000001',
                'SEED: 사업연도 최초예산 확정', seed_record.created_at + INTERVAL '1 day');
        END IF;
    END LOOP;

    FOR seed_record IN
        WITH budgets AS (
            SELECT bp.project_id, bp.project_year, bp.project_phase,
                   ib.budget_item_id, bi.item_code, ib.expenditure_limit,
                   row_number() OVER (PARTITION BY bp.project_id ORDER BY bi.item_code)::INT AS item_order
              FROM budget_project bp
              JOIN initial_budget ib USING (project_id)
              JOIN budget_item bi USING (budget_item_id)
             WHERE bp.project_name LIKE 'SEED % SW중심대학사업'
        ), scenarios AS (
            SELECT * FROM (VALUES
                ('A', 20, 'APPROVED'),
                ('B', 10, NULL),
                ('C', 20, 'PENDING')
            ) AS s(scenario_code, divisor, fixed_status)
        ), programs AS (
            SELECT program_id, row_number() OVER (ORDER BY program_date)::INT AS program_order
              FROM program WHERE program_name LIKE 'SEED %'
        )
        SELECT b.project_id, b.project_year, b.project_phase, b.budget_item_id, b.item_code,
               (b.expenditure_limit / s.divisor)::BIGINT AS amount,
               ('SEED-' || b.project_year || '-P' || b.project_phase || '-' || b.item_code || '-' || s.scenario_code) AS description,
               CASE WHEN s.scenario_code = 'B'
                    THEN CASE WHEN b.item_order % 2 = 0 THEN 'APPROVED' ELSE 'REJECTED' END
                    ELSE s.fixed_status END AS final_status,
               make_date(b.project_year, 3 + b.item_order, 5 + ascii(s.scenario_code) - ascii('A')) AS expenditure_date,
               (ARRAY['INDUSTRY_ACADEMIC', 'MAJOR', 'CONVERGENCE'])[((b.item_order - 1) % 3) + 1] AS subject_type_code,
               (ARRAY['91000001', '91000002', '91000003', '91000004'])[((b.item_order + ascii(s.scenario_code) - ascii('A') - 1) % 4) + 1] AS professor_id,
               CASE WHEN b.project_year = 2026 THEN p.program_id END AS program_id,
               make_timestamptz(b.project_year, 3 + b.item_order,
                   5 + ascii(s.scenario_code) - ascii('A'), 16, 0, 0, 'Asia/Seoul') AS created_at
          FROM budgets b CROSS JOIN scenarios s
          LEFT JOIN programs p ON p.program_order = b.item_order
         ORDER BY b.project_year, b.item_order, s.scenario_code
    LOOP
        SELECT count(*), min(expenditure_id) INTO v_count, v_expenditure_id
          FROM expenditure WHERE description = seed_record.description;
        IF v_count = 0 THEN
            v_expenditure_id := fn_create_expenditure(
                seed_record.project_id, seed_record.budget_item_id,
                seed_record.expenditure_date, seed_record.subject_type_code,
                seed_record.professor_id, seed_record.amount, seed_record.description,
                '90000001', seed_record.program_id, seed_record.created_at);
            IF seed_record.final_status = 'APPROVED' THEN
                PERFORM fn_approve_expenditure(v_expenditure_id, '90000001',
                    'SEED: 세부 지출 증빙 확인', seed_record.created_at + INTERVAL '1 day');
            ELSIF seed_record.final_status = 'REJECTED' THEN
                PERFORM fn_reject_expenditure(v_expenditure_id, '90000001',
                    'SEED: 거래 증빙 보완 필요', seed_record.created_at + INTERVAL '1 day');
            END IF;
        ELSIF v_count > 1 THEN
            RAISE EXCEPTION 'Seed 지출 업무키 중복: %', seed_record.description;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM expenditure
             WHERE expenditure_id = v_expenditure_id
               AND project_id = seed_record.project_id
               AND budget_item_id = seed_record.budget_item_id
               AND amount = seed_record.amount
               AND status = seed_record.final_status
               AND professor_id = seed_record.professor_id
               AND subject_type_code = seed_record.subject_type_code
               AND program_id IS NOT DISTINCT FROM seed_record.program_id
        ) THEN
            RAISE EXCEPTION 'Seed 지출 충돌: %', seed_record.description;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM initial_budget ib
        LEFT JOIN expenditure e ON e.project_id = ib.project_id
                               AND e.budget_item_id = ib.budget_item_id
                               AND e.status = 'APPROVED'
         GROUP BY ib.project_id, ib.budget_item_id, ib.expenditure_limit
        HAVING COALESCE(sum(e.amount), 0) > ib.expenditure_limit
    ) THEN
        RAISE EXCEPTION 'Seed 승인 지출이 예산 한도를 초과함';
    END IF;
END;
$$;

COMMIT;
