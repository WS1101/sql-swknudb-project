\encoding UTF8
\set ON_ERROR_STOP on
\pset pager off
-- 2번 시연: 참여 저조 원인 분해와 시간대 추천 (run_participation.sh 실행 후)

\echo ===== 1. 모델 검증: 2026-09-01 이전으로 학습 → 이후 회차 예측 =====
SELECT test_auc AS "학생 단위 AUC", test_session_mae AS "회차별 신청 인원 평균 오차(명)",
       substring(note FROM '평균 신청률 기준선 오차 [0-9.]+명') AS "비교 기준"
  FROM pbl3.p2_model_run ORDER BY run_id DESC LIMIT 1;

\echo ===== 2. 무엇이 신청을 줄이는가 (승산비 < 1 이면 감소) =====
SELECT label AS "요인", round(coef, 2) AS "계수", round(odds_ratio, 2) AS "승산비"
  FROM pbl3.p2_effect WHERE run_id = (SELECT max(run_id) FROM pbl3.p2_model_run)
   AND feature IN ('class_conflict','cross_campus','near_exam','evening','fatigue','is_online',
                   'prev_attended','prev_own_content_c','prev_avg_content_c')
 ORDER BY coef;

\echo ===== 3. 알고리즘 특강: 회차별 신청과 요인별 손실 =====
\echo   양수 = 그 요인 때문에 잃은 신청 인원, 음수 = 그 요인 덕분에 늘어난 신청 인원(좋은 평가 입소문 등)
SELECT o.session_no AS "회차", to_char(o.session_date,'MM/DD') AS "일자",
       to_char(o.start_time,'HH24:MI') AS "시각", round(o.conflict_rate*100) AS "충돌률%",
       o.registered AS "신청",
       max(f.lost_registrations) FILTER (WHERE f.factor='class_conflict')::INT AS "수업충돌",
       max(f.lost_registrations) FILTER (WHERE f.factor='near_exam')::INT      AS "시험",
       max(f.lost_registrations) FILTER (WHERE f.factor='fatigue')::INT        AS "회차피로",
       max(f.lost_registrations) FILTER (WHERE f.factor='word_of_mouth')::INT  AS "입소문"
  FROM pbl3.v_session_overview o
  JOIN pbl3.p2_session_factor f ON f.session_id = o.session_id
   AND f.run_id = (SELECT max(run_id) FROM pbl3.p2_model_run)
 WHERE o.series_key = 'ALGO_CT'
 GROUP BY o.session_no, o.session_date, o.start_time, o.conflict_rate, o.registered
 ORDER BY 1;

\echo ===== 4. 시간대 추천: 예정 회차와 사후 분석 회차 =====
SELECT program_name AS "프로그램", session_no AS "회차",
       to_char(cur_date,'MM/DD') || ' ' || to_char(cur_time,'HH24:MI') AS "현재",
       round(cur_conflict_rate*100) AS "현재 충돌%", cur_pred_attended AS "현재 예상 출석",
       actual_attended AS "실제 출석",
       to_char(best_date,'MM/DD') || ' ' || to_char(best_time,'HH24:MI') AS "추천",
       best_pred_attended AS "추천 예상 출석", gain_attended AS "증가"
  FROM pbl3.v_p2_recommendation ORDER BY program_name, session_no;
