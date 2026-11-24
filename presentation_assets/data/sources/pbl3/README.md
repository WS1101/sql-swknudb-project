v2 — 2026-11-23 (서우진)

* v1 스키마·시드·확인 쿼리를 대체. pbl3는 public에 의존하지 않는 독립 스키마로 변경
  (미션2 reset.sql이 public을 CASCADE로 지울 때 pbl3 FK가 함께 사라지던 문제 해결).
* 학생 1,596명, 프로그램 35개 시리즈, 회차 184개(예정 5개)로 확대. 2025~2026년 2개 학년도.
* 학과·학년·학기별로 다른 수업 시간표. 일부 회차는 시간 변경 → 시간 효과와 수업 충돌 효과 분리 가능.
* 학생 적극성(정규분포), 회차 단위 만족도, 재참여, 캠퍼스 이동, 이탈·SMS 수신 거부 반영.
* 생성기 정답(효과 계수, 잠재 변수)은 pbl3_truth 스키마로 분리. analytics_reader 접근 불가.
* 공통 분석 뷰 추가: mv_candidate, v_session_overview, v_response_scored, v_program_cost, v_student_activity.
* 영효 파트 비용 쿼리는 pbl3.v_program_cost로 대체.
