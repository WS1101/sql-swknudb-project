\encoding UTF8
\set ON_ERROR_STOP on
-- 2번 화면 데이터 내보내기: DB(모델 결과 테이블) → docs/data/schedule.json
--   저장소 루트에서 실행:
--     bash pbl3/p2/run_participation.sh                 (모델 결과를 DB에 저장)
--     psql -d swknu_db -XAtq -f pbl3/p2/export_schedule_json.sql
\o docs/data/schedule.json
WITH r AS (SELECT max(run_id) AS run_id FROM pbl3.p2_model_run),
sess AS (
    SELECT s.session_id, p.program_name, pt.program_type_name, s.session_no,
           (SELECT count(*) FROM pbl3.program_session x WHERE x.program_id = s.program_id) AS n_sessions,
           s.session_status, s.session_date, to_char(s.start_time, 'HH24:MI') AS st, to_char(s.end_time, 'HH24:MI') AS et,
           COALESCE(c.campus_name, '온라인') AS campus, s.location_name, p.capacity, t.reason,
           o.registered, o.attended
      FROM pbl3.p2_whatif_target t
      JOIN pbl3.program_session s USING (session_id)
      JOIN pbl3.program p USING (program_id)
      JOIN pbl3.program_type pt USING (program_type_code)
      LEFT JOIN pbl3.campus c ON c.campus_code = s.campus_code
      JOIN pbl3.v_session_overview o USING (session_id)
), slots AS (
    SELECT f.session_id,
           json_agg(json_build_object(
               'wd', f.weekday_iso, 't', to_char(f.start_time, 'HH24:MI'), 'date', f.slot_date,
               'cur', f.is_current, 'elig', f.eligible, 'conf', round(f.conflict_rate, 3), 'exam', f.near_exam,
               'reg', round(f.predicted_registered, 1),
               'att', round(least(f.predicted_registered, p.capacity) * f.predicted_attended / NULLIF(f.predicted_registered, 0), 1),
               'grades', (SELECT json_object_agg(g.grade_at, g.r)
                            FROM (SELECT grade_at, round(avg(class_conflict::INT), 2) AS r
                                    FROM pbl3.mv_p2_whatif w
                                   WHERE w.session_id = f.session_id AND w.weekday_iso = f.weekday_iso
                                     AND w.start_time = f.start_time
                                   GROUP BY 1) g)
           ) ORDER BY f.weekday_iso, f.start_time) AS js
      FROM pbl3.p2_slot_forecast f
      JOIN r USING (run_id)
      JOIN pbl3.program_session s USING (session_id)
      JOIN pbl3.program p USING (program_id)
     GROUP BY 1
), fac AS (
    SELECT f.session_id,
           json_agg(json_build_object('k', f.factor, 'label', f.label, 'lost', round(f.lost_registrations, 1),
                                      'aff', f.affected_students) ORDER BY f.lost_registrations DESC) AS js
      FROM pbl3.p2_session_factor f
      JOIN r USING (run_id)
      JOIN pbl3.p2_whatif_target USING (session_id)
     GROUP BY 1
)
SELECT json_build_object(
    'asOf',  (SELECT as_of_date FROM pbl3.generation_meta),
    'model', (SELECT json_build_object('auc', test_auc, 'mae', test_session_mae, 'trainUntil', train_until)
                FROM pbl3.p2_model_run JOIN r USING (run_id)),
    'sessions', (SELECT json_agg(json_build_object(
        'id', sess.session_id, 'program', program_name, 'type', program_type_name, 'no', session_no, 'n', n_sessions,
        'status', session_status, 'date', session_date, 'start', st, 'end', et, 'campus', campus,
        'loc', location_name, 'cap', capacity, 'reason', reason,
        'actualReg', CASE WHEN session_status = 'COMPLETED' THEN registered END,
        'actualAtt', CASE WHEN session_status = 'COMPLETED' THEN attended END,
        'slots', slots.js, 'factors', fac.js) ORDER BY session_status DESC, session_date)
        FROM sess JOIN slots USING (session_id) JOIN fac USING (session_id)));
\o
