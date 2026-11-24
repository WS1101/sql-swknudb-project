// 1번 만족도 진단 (담당: ________)
// 할 일
//   1. pbl3/export_satisfaction_json.sql 을 채워서 docs/data/satisfaction.json 을 만든다
//   2. 아래 ready 를 true 로 바꾸고, data 경로를 넣는다
//   3. render(root, data) 안에 화면을 그린다. 참고: tabs/schedule.js
//   색·카드·경고·큰 숫자 등은 style.css 의 공통 클래스를 그대로 쓴다
//     .card  .alert.crit/.warn/.ok  .compare + .opt  .big  .factors + .f  .chip.ok/.warn/.crit  .note
App.register({
  id: 'satisfaction',
  label: '만족도 진단',
  order: 1,
  desc: '성의 없는 응답을 걸러낸 만족도와, 학생을 다시 오게 만드는 문항을 확인합니다.',
  ready: false,
  data: null,                       // 완성 후: 'data/satisfaction.json'
  render(root, data) {
    root.innerHTML = `
      <div class="guide">
        <h1>만족도 진단 <span class="badge">준비 중</span></h1>
        <section class="card">
          <h2>이 탭에서 보여줄 것</h2>
          <ol>
            <li><b>경고</b>: "이 프로그램 응답 중 N%는 성의 없는 응답으로 보입니다" (빠른 응답 + 동일 점수)</li>
            <li><b>비교 카드</b>: 원래 평균 vs 의심 응답을 뺀 보정 평균</li>
            <li><b>재참여를 좌우하는 문항</b>: 문항분류별로 "0.5점 오르면 재참여 몇 %p" 막대 (운영이 아니라 내용)</li>
          </ol>
        </section>
        <section class="card">
          <h2>데이터 (pbl3, 함수 결과 그대로 사용 가능)</h2>
<pre>SELECT * FROM pbl3.fn_survey_summary('{}', 'pbl3');      -- 프로그램별 원래/보정 평균, 의심 비율
SELECT * FROM pbl3.fn_survey_quality('{}', 'pbl3');      -- 응답별 빠른 응답·동일 점수·품질 점수
SELECT * FROM pbl3.fn_survey_followup('2026-11-23 23:59+09', 'pbl3');  -- 재참여 여부
SELECT * FROM pbl3.v_survey_insight_category;            -- 응답×문항분류 점수</pre>
          <p class="note" style="margin-top:8px">JSON 내보내기 예시는 pbl3/p2/export_schedule_json.sql 의 json_build_object / json_agg 구조를 참고.</p>
        </section>
        <div class="ph-grid"><div class="ph">경고 문구</div><div class="ph">원래 평균 vs 보정 평균</div><div class="ph">문항분류별 재참여 영향</div></div>
      </div>`;
  }
});
