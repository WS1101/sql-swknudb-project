-- =====================================================================
-- T03_topcit_duplicate.sql : 동일 학생·동일 TOPCIT 회차 재등록 거부, 스냅샷, 마일리지 구간
-- 담당: 김건희
-- 실행: psql -d swknu_db -f tests/T03_topcit_duplicate.sql
--
-- 시나리오 (미션 7장)
--   입력        같은 학생이 같은 회차 점수를 다시 등록
--   예상 결과   등록 거부(23505), 기존 점수 유지. 다른 회차는 등록 가능(다회차 이력)
--   구현 방법   - uq_topcit_score_student_round (student_no, round_id) UNIQUE (자동 강제)
--               - uq_topcit_exam_round_name 회차명 UNIQUE (자동 강제)
--               - 응시 시점 학년·학과: BEFORE INSERT 트리거가 student 현재 값으로 채움
--               - 마일리지 구간 [min, max): EXCLUDE 제약으로 겹침 차단 (자동 강제)
-- =====================================================================
\set ON_ERROR_STOP on
\encoding UTF8
BEGIN;
\ir _helpers.sql

-- 준비
INSERT INTO college (college_code, college_name) VALUES ('T03C', '테스트대학');
INSERT INTO campus (campus_code, campus_name) VALUES ('T03P', '테스트캠퍼스');
INSERT INTO department (dept_code, dept_name, college_code, campus_code, track_type)
VALUES ('T03D', '테스트학과', 'T03C', 'T03P', 'ENG');
INSERT INTO app_user (user_id, login_id, password_hash, user_name, user_type) VALUES
    ('99993001', 't03.student', crypt('x', gen_salt('bf')), '테스트학생', 'STUDENT'),
    ('99993901', 't03.admin',   crypt('x', gen_salt('bf')), '테스트관리자', 'ADMIN');
INSERT INTO student (student_no, dept_code, grade, enrollment_status, admission_type, admission_date)
VALUES ('99993001', 'T03D', 2, 'ENROLLED', 'NEW', '2025-03-01');
INSERT INTO admin (staff_no) VALUES ('99993901');
INSERT INTO topcit_exam_round (round_name, exam_date) VALUES
    ('T03_ROUND_1', '2026-05-01'),
    ('T03_ROUND_2', '2026-10-01');

DO $t$
DECLARE
    r1 INT;
    r2 INT;
    v_txt TEXT;
BEGIN
    SELECT round_id INTO r1 FROM topcit_exam_round WHERE round_name = 'T03_ROUND_1';
    SELECT round_id INTO r2 FROM topcit_exam_round WHERE round_name = 'T03_ROUND_2';

    -- 1. 정상 등록 (학년·학과 생략 → 트리거가 채움)
    PERFORM pg_temp.t_expect_ok('1. 1회차 점수 등록 (학년·학과 생략)',
        format($q$INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
                  VALUES ('99993001', %s, 300, '99993901')$q$, r1));
    SELECT grade_at_exam || '/' || dept_code_at_exam INTO v_txt
      FROM topcit_score WHERE student_no = '99993001' AND round_id = r1;
    PERFORM pg_temp.t_check('2. 응시 시점 학년·학과 자동 입력 (2/T03D)', v_txt = '2/T03D', v_txt);

    -- 3. 같은 학생·같은 회차 재등록
    PERFORM pg_temp.t_expect_error('3. 같은 학생·같은 회차 재등록',
        format($q$INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
                  VALUES ('99993001', %s, 450, '99993901')$q$, r1), '23505');

    -- 4. 기존 점수 유지 (450으로 바뀌지 않음)
    PERFORM pg_temp.t_check('4. 기존 점수 300 유지',
        (SELECT total_score = 300 FROM topcit_score WHERE student_no = '99993001' AND round_id = r1),
        (SELECT 'total_score=' || total_score FROM topcit_score WHERE student_no = '99993001' AND round_id = r1));

    -- 5. 진급 후 다른 회차는 등록 가능 → 다회차 이력, 회차별 학년이 다르게 보존
    UPDATE student SET grade = 3 WHERE student_no = '99993001';
    PERFORM pg_temp.t_expect_ok('5. 같은 학생·다른 회차 등록 (다회차 이력)',
        format($q$INSERT INTO topcit_score (student_no, round_id, total_score, created_by)
                  VALUES ('99993001', %s, 380, '99993901')$q$, r2));
    SELECT string_agg(r.round_name || ':' || ts.grade_at_exam, ', ' ORDER BY r.exam_date) INTO v_txt
      FROM topcit_score ts JOIN topcit_exam_round r ON r.round_id = ts.round_id
     WHERE ts.student_no = '99993001';
    PERFORM pg_temp.t_check('6. 진급 후에도 1회차 학년 2 유지, 2회차는 3',
        v_txt = 'T03_ROUND_1:2, T03_ROUND_2:3', v_txt);

    -- 7. 회차명 중복
    PERFORM pg_temp.t_expect_error('7. 같은 회차명 재등록',
        $q$INSERT INTO topcit_exam_round (round_name, exam_date) VALUES ('T03_ROUND_1', '2026-12-01')$q$,
        '23505');

    -- 8~13. 마일리지 구간 [min, max) — seed 기준을 지우고 이 테스트용 구간으로 확인 (ROLLBACK됨)
    DELETE FROM topcit_mileage_criteria;
    PERFORM pg_temp.t_expect_ok('8. 경계가 맞닿은 구간 [0,150), [150,250) 등록',
        $q$INSERT INTO topcit_mileage_criteria (min_score, max_score, mileage_awarded)
           VALUES (0, 150, 30), (150, 250, 50)$q$);
    PERFORM pg_temp.t_expect_error('9. 겹치는 구간 [100,200) 등록',
        $q$INSERT INTO topcit_mileage_criteria (min_score, max_score, mileage_awarded)
           VALUES (100, 200, 40)$q$, '23P01');
    PERFORM pg_temp.t_expect_ok('10. 상한 없는 구간 [250, ∞) 등록',
        $q$INSERT INTO topcit_mileage_criteria (min_score, max_score, mileage_awarded)
           VALUES (250, NULL, 99)$q$);
    PERFORM pg_temp.t_expect_error('11. 최소 ≥ 최대인 구간',
        $q$INSERT INTO topcit_mileage_criteria (min_score, max_score, mileage_awarded)
           VALUES (300, 300, 10)$q$, '23514');
    PERFORM pg_temp.t_check('12. 경계 점수 150 → 두 번째 구간(50)',
        (SELECT mileage_awarded = 50 FROM topcit_mileage_criteria
          WHERE int4range(min_score, max_score, '[)') @> 150),
        (SELECT 'mileage=' || mileage_awarded FROM topcit_mileage_criteria
          WHERE int4range(min_score, max_score, '[)') @> 150));
    PERFORM pg_temp.t_check('13. 만점 1000 → 상한 없는 구간(99)',
        (SELECT mileage_awarded = 99 FROM topcit_mileage_criteria
          WHERE int4range(min_score, max_score, '[)') @> 1000),
        (SELECT 'mileage=' || mileage_awarded FROM topcit_mileage_criteria
          WHERE int4range(min_score, max_score, '[)') @> 1000));

    -- 14. 전체 DB에 학생·회차 중복 점수 없음 (seed 포함)
    PERFORM pg_temp.t_check('14. 전체 TOPCIT 점수 중 학생·회차 중복 0건',
        NOT EXISTS (SELECT 1 FROM topcit_score GROUP BY student_no, round_id HAVING count(*) > 1));
END;
$t$;

\ir _report.sql
ROLLBACK;
