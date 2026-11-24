\encoding UTF8
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- 프로젝트 최상위 폴더에서 실행:
--   psql -U postgres -d swknu_demo -X -Atq -f pbl3/export_budget_json.sql
-- pbl3.v_program_cost 결과를 GitHub Pages용 JSON으로 저장한다. DB 데이터는 변경하지 않는다.
-- 출력 파일: docs/data/budget.json (예시값이 실제 가상 DB 조회값으로 교체됨)
\o docs/data/budget.json
SELECT json_build_object(
  'mode', 'database',
  'source', 'pbl3.v_program_cost',
  'asOf', (SELECT as_of_date FROM pbl3.generation_meta LIMIT 1),
  'programs', COALESCE((SELECT json_agg(row_to_json(r) ORDER BY r.name)
    FROM (
      SELECT v.program_id AS id,
             v.program_name AS name,
             v.program_type_code AS type,
             pt.program_type_name AS "typeName",
             v.sessions_completed AS sessions,
             v.approved_cost AS approved,
             v.unique_attendees AS attendees,
             v.attendance_records AS "attendanceRecords",
             v.returning_attendees AS returning,
             v.satisfied_attendees AS satisfied,
             v.avg_satisfaction AS "meanScore",
             v.cost_per_unique_attendee AS "costPerAttendee",
             v.cost_per_satisfied AS "costPerSatisfied",
             v.cost_per_returning AS "costPerReturning"
        FROM pbl3.v_program_cost v
        JOIN pbl3.program_type pt USING (program_type_code)
       WHERE v.sessions_completed > 0
    ) r), '[]'::json)
);
\o
