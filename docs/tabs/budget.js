// 3번 예산 효율 (담당: ________)
// 할 일
//   1. pbl3/export_budget_json.sql 을 채워서 docs/data/budget.json 을 만든다
//   2. 아래 ready 를 true 로 바꾸고, data 경로를 넣는다
//   3. render(root, data) 안에 화면을 그린다. 참고: tabs/schedule.js
//   색·카드·경고·큰 숫자 등은 style.css 의 공통 클래스를 그대로 쓴다
//     .card  .alert.crit/.warn/.ok  .compare + .opt  .big  .factors + .f  .chip.ok/.warn/.crit  .note
App.register({
  id: 'budget',
  label: '예산 효율',
  order: 3,
  desc: '같은 예산으로 만족하고 다시 오는 학생을 얼마나 만들었는지 비교합니다.',
  ready: false,
  data: null,                       // 완성 후: 'data/budget.json'
  render(root, data) {
    root.innerHTML = `
      <div class="guide">
        <h1>예산 효율 <span class="badge">준비 중</span></h1>
        <section class="card">
          <h2>이 탭에서 보여줄 것</h2>
          <ol>
            <li><b>큰 숫자</b>: 만족한 학생 1명을 만드는 데 든 비용 (원)</li>
            <li><b>같은 유형끼리 비교</b>: 특강은 특강끼리, 캠프는 캠프끼리 (비용 구조가 달라서)</li>
            <li><b>경고</b>: "같은 유형 평균보다 만족 1명당 비용이 N배 높습니다"</li>
          </ol>
        </section>
        <section class="card">
          <h2>데이터 (pbl3)</h2>
<pre>SELECT program_name, program_type_code, approved_cost, unique_attendees,
       satisfied_attendees, cost_per_unique_attendee, cost_per_satisfied, cost_per_returning
  FROM pbl3.v_program_cost
 WHERE sessions_completed > 0;
-- 만족 출석자 = 일괄 응답을 제외한 내용(CONTENT) 만족도 평균 4점 이상
-- 만족자가 아주 적은 프로그램(예: 3명)은 단가가 튀므로 함께 표시할 것</pre>
        </section>
        <div class="ph-grid"><div class="ph">만족 1명당 비용 (큰 숫자)</div><div class="ph">유형 내 비교 막대</div><div class="ph">경고 문구</div></div>
      </div>`;
  }
});
