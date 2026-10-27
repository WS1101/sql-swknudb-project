-- 기준정보 코드는 가상 Seed 전용이다. 지출주체 3종은 schema/02_master.sql의 값을 재사용한다.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = public, pg_temp;
SELECT pg_advisory_xact_lock(20261015, 2);

DO $$
DECLARE
    seed_record RECORD;
BEGIN
    FOR seed_record IN SELECT * FROM (VALUES
        ('SEED_ENG', '국립공주대학교'), ('SEED_DAI', '국립공주대학교')
    ) AS expected(college_code, college_name)
    LOOP
        INSERT INTO college (college_code, college_name)
        VALUES (seed_record.college_code, seed_record.college_name)
        ON CONFLICT (college_code) DO NOTHING;
        IF NOT EXISTS (SELECT 1 FROM college WHERE to_jsonb(college) @> to_jsonb(seed_record) AND is_active) THEN
            RAISE EXCEPTION 'Seed 대학 코드 충돌: %', seed_record.college_code;
        END IF;
    END LOOP;

    FOR seed_record IN SELECT * FROM (VALUES
        ('SEED_A', '천안캠퍼스'), ('SEED_B', '신관캠퍼스')
    ) AS expected(campus_code, campus_name)
    LOOP
        INSERT INTO campus (campus_code, campus_name)
        VALUES (seed_record.campus_code, seed_record.campus_name)
        ON CONFLICT (campus_code) DO NOTHING;
        IF NOT EXISTS (SELECT 1 FROM campus WHERE to_jsonb(campus) @> to_jsonb(seed_record) AND is_active) THEN
            RAISE EXCEPTION 'Seed 캠퍼스 코드 충돌: %', seed_record.campus_code;
        END IF;
    END LOOP;

    FOR seed_record IN SELECT * FROM (VALUES
        ('SEED_CS', '컴퓨터공학과', 'SEED_ENG', 'SEED_A', 'ENG'),
        ('SEED_SW', '소프트웨어학과', 'SEED_ENG', 'SEED_A', 'ENG'),
        ('SEED_SIT', '스마트정보기술공학과', 'SEED_ENG', 'SEED_A', 'ENG'),
        ('SEED_AI', '인공지능학부', 'SEED_DAI', 'SEED_B', 'DAI')
    ) AS expected(dept_code, dept_name, college_code, campus_code, track_type)
    LOOP
        INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
        VALUES (seed_record.dept_code, seed_record.dept_name, seed_record.college_code,
                seed_record.campus_code, seed_record.track_type)
        ON CONFLICT (dept_code) DO NOTHING;
        IF NOT EXISTS (SELECT 1 FROM department WHERE to_jsonb(department) @> to_jsonb(seed_record) AND is_active) THEN
            RAISE EXCEPTION 'Seed 학과 코드 충돌: %', seed_record.dept_code;
        END IF;
    END LOOP;

    FOR seed_record IN SELECT * FROM (VALUES
        ('91000001', '임영효', '컴퓨터공학과'),
        ('91000002', '나웅수', '소프트웨어학과'),
        ('91000003', '서우진', '스마트정보기술공학과'),
        ('91000004', '김건희', '인공지능학부')
    ) AS expected(professor_id, professor_name, affiliation)
    LOOP
        INSERT INTO professor (professor_id, professor_name, affiliation)
        VALUES (seed_record.professor_id, seed_record.professor_name, seed_record.affiliation)
        ON CONFLICT (professor_id) DO NOTHING;
        IF NOT EXISTS (SELECT 1 FROM professor WHERE to_jsonb(professor) @> to_jsonb(seed_record) AND is_active) THEN
            RAISE EXCEPTION 'Seed 교수 교번 충돌: %', seed_record.professor_id;
        END IF;
    END LOOP;

    -- 미션 1의 고정 7개 항목. 코드 또는 명칭만 같은 다른 행은 자동 병합하지 않는다.
    FOR seed_record IN SELECT * FROM (VALUES
        ('PERSONNEL', '인건비'), ('STUDENT_PERSONNEL', '학생인건비'),
        ('RESEARCH_EQUIPMENT', '연구장비시설비'), ('RESEARCH_ACTIVITY', '연구활동비'),
        ('RESEARCH_MATERIAL', '연구재료비'), ('RESEARCH_ALLOWANCE', '연구수당'),
        ('INDIRECT', '간접비')
    ) AS expected(item_code, item_name)
    LOOP
        IF EXISTS (SELECT 1 FROM budget_item WHERE item_name = seed_record.item_name AND item_code <> seed_record.item_code) THEN
            RAISE EXCEPTION '예산항목 기존 코드와 협의 필요: %', seed_record.item_name;
        END IF;
        INSERT INTO budget_item (item_code, item_name)
        VALUES (seed_record.item_code, seed_record.item_name)
        ON CONFLICT (item_code) DO NOTHING;
        IF NOT EXISTS (SELECT 1 FROM budget_item WHERE to_jsonb(budget_item) @> to_jsonb(seed_record) AND is_active) THEN
            RAISE EXCEPTION 'Seed 예산항목 코드 충돌: %', seed_record.item_code;
        END IF;
    END LOOP;

    IF (SELECT count(*) FROM expenditure_subject_type
        WHERE (subject_type_code, subject_type_name) IN (
            ('INDUSTRY_ACADEMIC', '산학협력'), ('MAJOR', '전공'), ('CONVERGENCE', '융합')
        )) <> 3 THEN
        RAISE EXCEPTION '스키마에서 생성하는 지출주체 3종을 먼저 확인해야 함';
    END IF;

    FOR seed_record IN SELECT * FROM (VALUES
        (2025, '1', DATE '2025-03-01', DATE '2025-06-30'),
        (2025, 'S', DATE '2025-07-01', DATE '2025-08-31'),
        (2025, '2', DATE '2025-09-01', DATE '2025-12-31'),
        (2025, 'W', DATE '2026-01-01', DATE '2026-02-28'),
        (2026, '1', DATE '2026-03-01', DATE '2026-06-30'),
        (2026, 'S', DATE '2026-07-01', DATE '2026-08-31'),
        (2026, '2', DATE '2026-09-01', DATE '2026-12-31'),
        (2026, 'W', DATE '2027-01-01', DATE '2027-02-28')
    ) AS expected(term_year, term_code, start_date, end_date)
    LOOP
        INSERT INTO academic_term (term_year, term_code, start_date, end_date)
        VALUES (seed_record.term_year, seed_record.term_code, seed_record.start_date, seed_record.end_date)
        ON CONFLICT (term_year, term_code) DO NOTHING;
        IF NOT EXISTS (SELECT 1 FROM academic_term WHERE to_jsonb(academic_term) @> to_jsonb(seed_record)) THEN
            RAISE EXCEPTION 'Seed 학기 기간 충돌: % %', seed_record.term_year, seed_record.term_code;
        END IF;
    END LOOP;

    FOR seed_record IN SELECT * FROM (VALUES
        ('SEED_CONTEST', '경진대회·공모전'), ('SEED_TRAINING', '교육·특강'),
        ('SEED_CAMP', '산학협력·캡스톤디자인'), ('SEED_MENTORING', 'SW 가치확산')
    ) AS expected(program_type_code, program_type_name)
    LOOP
        INSERT INTO program_type (program_type_code, program_type_name)
        VALUES (seed_record.program_type_code, seed_record.program_type_name)
        ON CONFLICT (program_type_code) DO NOTHING;
        IF NOT EXISTS (SELECT 1 FROM program_type WHERE to_jsonb(program_type) @> to_jsonb(seed_record) AND is_active) THEN
            RAISE EXCEPTION 'Seed 프로그램유형 코드 충돌: %', seed_record.program_type_code;
        END IF;
    END LOOP;

    FOR seed_record IN SELECT * FROM (VALUES
        ('SEED_CONTENT', '교육 내용', '내용의 유익성과 난이도'),
        ('SEED_OPERATION', '프로그램 운영', '일정·진행·지원에 대한 평가'),
        ('SEED_OVERALL', '종합 만족도', '프로그램 전반의 만족도'),
        ('SEED_OPINION', '개선 의견', '주관식 개선 의견 분류')
    ) AS expected(category_code, category_name, description)
    LOOP
        INSERT INTO survey_question_category (category_code, category_name, description)
        VALUES (seed_record.category_code, seed_record.category_name, seed_record.description)
        ON CONFLICT (category_code) DO NOTHING;
        IF NOT EXISTS (SELECT 1 FROM survey_question_category WHERE to_jsonb(survey_question_category) @> to_jsonb(seed_record) AND is_active) THEN
            RAISE EXCEPTION 'Seed 문항분류 코드 충돌: %', seed_record.category_code;
        END IF;
    END LOOP;
END;
$$;

COMMIT;
