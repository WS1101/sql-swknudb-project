// 3번 예산 효율: pbl3.v_program_cost를 프로그램 단위로 내보낸 JSON을 사용한다.
// 다른 탭이나 DB 원본은 수정하지 않는다.
(() => {
  if (!document.querySelector('link[data-budget-css]')) {
    const css = document.createElement('link');
    css.rel = 'stylesheet'; css.href = 'tabs/budget.css'; css.dataset.budgetCss = '1';
    document.head.appendChild(css);
  }
  const number = x => Number.isFinite(Number(x)) && x !== null && x !== '' ? Number(x) : null;
  const comma = x => Number(x).toLocaleString('ko-KR', {maximumFractionDigits: 0});
  const money = x => x == null ? '자료 없음' : `${comma(x)}원`;
  const smallMoney = x => {
    if (x == null) return '—';
    if (x >= 100000000) return `${(x / 100000000).toLocaleString('ko-KR', {maximumFractionDigits: 2})}억원`;
    if (x >= 10000) return `${(x / 10000).toLocaleString('ko-KR', {maximumFractionDigits: 0})}만원`;
    return `${comma(x)}원`;
  };
  const escape = x => String(x ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const median = a => {
    const s = a.filter(Number.isFinite).sort((x, y) => x - y);
    return s.length ? (s[Math.floor((s.length - 1)/2)] + s[Math.floor(s.length/2)]) / 2 : null;
  };
  const share = (n, d) => d > 0 ? Math.round(n / d * 100) : null;
  const shortName = p => p.name.replace(/ 20\d\d$/, '');

  App.register({
    id: 'budget', label: '예산 효율', order: 3, ready: true,
    desc: '같은 유형의 프로그램끼리 비용과 학생 성과를 비교하고, 개선 시나리오를 검토합니다.',
    data: 'data/budget.json',
    render(root, D) {
      const programs = (D.programs || []).map(p => ({
        id: Number(p.id), name: String(p.name), type: String(p.type),
        typeName: String(p.typeName || p.type), sessions: number(p.sessions),
        approved: number(p.approved), attendees: number(p.attendees),
        attendanceRecords: number(p.attendanceRecords), returning: number(p.returning),
        satisfied: number(p.satisfied), meanScore: number(p.meanScore),
        costPerAttendee: number(p.costPerAttendee), costPerSatisfied: number(p.costPerSatisfied),
        costPerReturning: number(p.costPerReturning),
      })).filter(p => p.sessions > 0);
      if (!programs.length) {
        root.innerHTML = '<p class="error">비교할 프로그램 집계 데이터가 없습니다. JSON 내보내기를 확인해 주세요.</p>';
        return;
      }
      const groups = [...new Map(programs.map(p => [p.type, p.typeName])).entries()];
      const state = {type: groups.some(g => g[0] === 'LECTURE') ? 'LECTURE' : groups[0][0], selected: null, delta: 20};
      const sample = D.mode !== 'database';
      const sourceText = sample
        ? '화면 시연용 예시 수치 · 실제 DB 집계값이 아닙니다. pbl3/export_budget_json.sql 실행 시 DB 값으로 교체됩니다.'
        : `가상 DB 조회 결과 · 기준일 ${escape(D.asOf || '미설정')} · pbl3.v_program_cost`;
      root.innerHTML = `
        <div class="budget-app">
          <div class="b-mode ${sample ? 'sample' : ''}"><span class="b-mode-dot"></span>${sourceText}</div>
          <div class="b-filters"><div><b>프로그램 유형별 비교</b><p>비용 구조가 비슷한 프로그램끼리 비교합니다.</p></div>
            <label class="b-typelabel">유형 <select data-b="type" aria-label="프로그램 유형 선택"></select></label>
          </div>
          <div class="b-layout">
            <aside class="side b-side" aria-label="프로그램 목록">
              <h3>분석할 프로그램 <small data-b="count"></small></h3>
              <p class="b-sidehint">만족 출석자 1인당 비용이 높은 순서</p>
              <div data-b="list"></div>
              <p class="note b-sidenote">비용 데이터 또는 만족 출석자가 없는 경우 비교에서 제외되거나 별도로 표시됩니다.</p>
            </aside>
            <div class="main b-main">
              <section class="card b-heading" data-b="heading"></section>
              <div data-b="notice"></div>
              <div class="b-kpis" data-b="kpis"></div>
              <div class="two b-analysis">
                <section class="card"><div class="sec-h"><h2>같은 유형의 비용 효율 비교</h2><p>만족 출석자 1명당 비용 · 낮을수록 효율적</p></div>
                  <div class="b-bars" data-b="bars"></div><p class="note b-chartnote" data-b="chartNote"></p></section>
                <section class="card b-diagnosis"><div class="sec-h"><h2>데이터가 말해주는 점</h2></div>
                  <div data-b="diagnosis"></div></section>
              </div>
              <section class="card b-whatif"><div class="sec-h"><h2>참여 개선 시 비용 시뮬레이션</h2><p>승인 지출액은 그대로라고 가정</p></div>
                <div data-b="whatif"></div></section>
              <section class="card b-detail"><div class="sec-h"><h2>계산 기준과 데이터 한계</h2></div>
                <div class="b-notes"><p><b>승인 지출</b>은 해당 프로그램에 연결된 APPROVED 지출만 합산합니다. 다른 간접비 등은 포함되지 않습니다.</p>
                <p><b>만족 출석자</b>는 실제 출석자 중, 완료 응답·일괄 점수 응답 제외 기준의 교육 내용(CONTENT) 평균이 4점 이상인 학생입니다. 응답하지 않은 출석자는 만족 여부를 알 수 없습니다.</p>
                <p><b>재참여자</b>는 같은 프로그램 시리즈에서 2회 이상 출석한 학생입니다. 다른 프로그램으로의 재참여는 포함하지 않습니다.</p>
                <p><b>비용 단가</b>는 프로그램에 연결된 승인 지출 ÷ 해당 인원수이며, 원인이나 교육 효과를 증명하는 수치는 아닙니다. 예정 회차의 지출이 포함될 수 있어 해석에 주의해야 합니다.</p></div>
              </section>
            </div>
          </div>
        </div>`;
      const el = key => root.querySelector(`[data-b="${key}"]`);
      const typeSel = el('type');
      typeSel.innerHTML = groups.map(([k,v]) => `<option value="${escape(k)}">${escape(v)}</option>`).join('');
      typeSel.value = state.type;
      typeSel.onchange = () => {state.type = typeSel.value; state.selected = null; draw();};
      const sameType = () => programs.filter(p => p.type === state.type);
      const viable = p => p.approved != null && p.satisfied > 0 && p.costPerSatisfied != null;
      const mOf = rows => median(rows.filter(p => viable(p) && p.satisfied >= 5).map(p => p.costPerSatisfied));
      const select = id => { state.selected = id; state.delta = 20; draw(); };
      function draw() {
        const rows = sameType().sort((a,b) => (viable(b) ? b.costPerSatisfied : -1) - (viable(a) ? a.costPerSatisfied : -1));
        if (!rows.some(p => p.id === state.selected)) state.selected = rows[0]?.id ?? null;
        const p = rows.find(x => x.id === state.selected);
        if (!p) return;
        const base = mOf(rows);
        const ratio = base > 0 && viable(p) ? p.costPerSatisfied / base : null;
        el('count').textContent = `${rows.length}개`;
        el('list').innerHTML = rows.map(x => `<button type="button" class="item b-item" data-id="${x.id}" aria-current="${x.id === p.id}">
          <b>${escape(shortName(x))}</b><span>${x.sessions}개 완료 회차 · 출석 ${comma(x.attendees ?? 0)}명</span>
          <em class="chip ${!viable(x) ? 'warn' : (base && x.costPerSatisfied > base*1.5) ? 'crit' : 'ok'}">${viable(x) ? smallMoney(x.costPerSatisfied) : '비교 불가'}</em></button>`).join('');
        el('list').querySelectorAll('button').forEach(btn => { btn.onclick = () => select(Number(btn.dataset.id)); });
        el('heading').innerHTML = `<div><h1>${escape(p.name)}</h1><div class="meta"><span>${escape(p.typeName)} · 완료 회차 ${comma(p.sessions)}개</span>
          <span class="badge">${sample ? '수치 예시' : '가상 DB 집계'}</span></div></div>
          <div class="b-feature"><div class="b-feature-lbl">만족 출석자 1명당 비용</div>
            <div class="b-feature-val num">${viable(p) ? money(p.costPerSatisfied) : '계산 불가'}</div>
            <span class="b-feature-sub">${base == null ? '유형 내 비교 표본 부족' : `동일 유형 중앙값 ${money(base)}${ratio == null ? '' : ` · ${ratio.toFixed(2)}배`}`}</span></div>`;
        const warn = !viable(p) ? {lv:'warn',title:'비용 효율을 계산할 수 없습니다.',sub:'승인 지출 또는 만족 출석자 수가 없어 분모를 확인해야 합니다.'}
          : p.satisfied < 5 ? {lv:'warn',title:'만족 출석자가 적어 단가가 크게 변동할 수 있습니다.',sub:'5명 미만 표본입니다. 다른 자료와 함께 해석하세요.'}
          : ratio != null && ratio >= 1.5 ? {lv:'crit',title:`같은 유형 중앙값보다 만족 출석자당 비용이 ${ratio.toFixed(1)}배 높습니다.`,sub:'바로 축소하기보다 출석 저조·내용 만족도·비용 구성을 먼저 살펴보세요.'}
          : ratio != null && ratio < .8 ? {lv:'ok',title:'같은 유형 중앙값보다 만족 출석자당 비용이 낮습니다.',sub:'만족 학생 규모와 재참여율도 함께 확인해야 합니다.'}
          : {lv:'ok',title:'동일 유형 프로그램과 비슷한 비용 효율을 보입니다.',sub:'출석자 수, 만족도, 재참여를 함께 살펴보세요.'};
        el('notice').innerHTML = `<div class="alert ${warn.lv}"><span class="ic">${warn.lv === 'ok' ? '✓' : '!'}</span><div><p><strong>${warn.title}</strong></p><div class="sub">${warn.sub}</div></div></div>`;
        const kpis = [
          {label:'연결 승인 지출', val: money(p.approved), foot:'프로그램 연결 APPROVED 합계'},
          {label:'실제 출석 학생', val: p.attendees == null ? '—' : comma(p.attendees)+'명', foot: `${comma(p.attendanceRecords ?? 0)}회 출석 기록`},
          {label:'만족 출석 학생', val: p.satisfied == null ? '—' : comma(p.satisfied)+'명', foot:`출석 학생 중 ${share(p.satisfied,p.attendees) ?? '—'}% · 내용 평균 4점 이상`},
          {label:'재참여 학생', val:p.returning == null ? '—' : comma(p.returning)+'명', foot:`같은 프로그램에 2회 이상 출석 · ${share(p.returning,p.attendees) ?? '—'}%`}
        ];
        el('kpis').innerHTML = kpis.map(k => `<div class="b-kpi"><div class="b-kpi-label">${k.label}</div><div class="b-kpi-val num">${k.val}</div><div class="b-kpi-foot">${k.foot}</div></div>`).join('');
        const barRows = rows.filter(x => viable(x)).sort((a,b) => a.costPerSatisfied - b.costPerSatisfied);
        const max = Math.max(1,...barRows.map(x => x.costPerSatisfied));
        el('bars').innerHTML = barRows.map(x => `<button type="button" data-id="${x.id}" class="b-bar-row ${x.id === p.id ? 'active' : ''}">
          <span class="b-bar-name" title="${escape(x.name)}">${escape(shortName(x))}</span>
          <span class="b-bar-track"><i style="width:${Math.max(2,x.costPerSatisfied/max*100).toFixed(1)}%"></i></span>
          <strong class="num">${smallMoney(x.costPerSatisfied)}</strong><span class="b-bar-n">${x.satisfied}명</span></button>`).join('')
          || '<p class="note">비교 가능한 프로그램이 없습니다.</p>';
        el('bars').querySelectorAll('button').forEach(btn => btn.onclick = () => select(Number(btn.dataset.id)));
        el('chartNote').textContent = `유형별 중앙값은 만족 출석자 5명 이상인 프로그램으로 계산합니다. ${barRows.length}개 비교 가능 · 적은 인원일수록 단가가 불안정할 수 있습니다.`;
        let diagnosis;
        if (!viable(p)) diagnosis = '<p>승인 지출과 만족 출석자 수를 확인할 수 없어 효율 비교를 보류합니다.</p>';
        else {
          const text = ratio == null ? '유형 비교에 필요한 유효 표본이 충분하지 않습니다.'
            : ratio > 1.5 ? '비용이 상대적으로 높습니다. 낮은 출석률이 문제인지, 교육 내용 만족도가 낮은지 먼저 분리해서 확인해야 합니다.'
            : ratio < .8 ? '상대적으로 낮은 비용입니다. 다만 비용 단가만으로 교육 성과를 확정할 수는 없습니다.'
            : '동일 유형 중앙값 수준입니다. 추가 개선 가능성은 출석률과 교육 내용 평가에서 찾을 수 있습니다.';
          diagnosis = `<p class="b-insight-head">${text}</p>
            <div class="b-mini-row"><span>출석 학생 1명당 비용</span><b class="num">${money(p.costPerAttendee)}</b></div>
            <div class="b-mini-row"><span>재참여 학생 1명당 비용</span><b class="num">${money(p.costPerReturning)}</b></div>
            <div class="b-mini-row"><span>평균 만족도 (완료·일괄응답 제외)</span><b class="num">${p.meanScore == null ? '—' : p.meanScore.toFixed(2)+' / 5점'}</b></div>
            <p class="note b-diagnostic-note">${p.satisfied < 5 ? '만족 출석자 수가 5명 미만이므로 순위만으로 판단하지 않습니다.' : '높은 단가가 반드시 낮은 교육 품질을 의미하지는 않습니다.'}</p>`;
        }
        el('diagnosis').innerHTML = diagnosis;
        drawWhatIf(p);
      }
      function drawWhatIf(p) {
        const box = el('whatif');
        if (!(p.attendees > 0) || p.approved == null) {box.innerHTML = '<p class="note">현재 출석 인원과 지출 정보가 있어야 계산할 수 있습니다.</p>'; return;}
        const v = state.delta;
        const before = Math.round(p.approved / p.attendees);
        const after = Math.round(p.approved / (p.attendees + v));
        const reduction = before > 0 ? Math.round((1-after/before)*100) : 0;
        box.innerHTML = `<div class="b-scenario">
          <div class="b-slidebox"><label for="b-growth">고유 출석 학생이 추가로 늘어난다면 <strong class="num">+${v}명</strong></label>
            <input id="b-growth" type="range" min="0" max="100" step="5" value="${v}" aria-label="추가 출석 학생 수">
            <p class="note">추가 비용 0원, 기존 승인 지출과 만족 비율은 변하지 않는다고 가정한 단순 계산입니다. 예측 모델 결과가 아닙니다.</p></div>
          <div class="b-scenario-results"><div><small>현재 출석 학생 1인당 비용</small><b class="num">${money(before)}</b></div>
            <span aria-hidden="true">→</span><div><small>참여 증가 가정 후</small><b class="num">${money(after)}</b><em>${reduction}% 감소</em></div></div></div>
          <div data-b="scheduleLink" class="b-schedulelink"></div>`;
        box.querySelector('#b-growth').oninput = e => {state.delta = Number(e.target.value); drawWhatIf(p);};
        drawScheduleLink(p);
      }
      async function drawScheduleLink(p) {
        const slot = el('scheduleLink'); if (!slot) return;
        try {
          let S = App.cache['data/schedule.json'];
          if (!S) { const resp = await fetch('data/schedule.json'); if(!resp.ok) return; S = await resp.json(); App.cache['data/schedule.json'] = S; }
          const s = S.sessions.find(x => x.program === p.name && x.status === 'SCHEDULED');
          if (!s) {slot.textContent = '같은 프로그램의 예정 회차가 없으면 일정 변경 예측은 별도로 제공하지 않습니다.'; return;}
          const now = s.slots.find(x => x.cur);
          const future = s.slots.filter(x => x.date >= S.asOf);
          const best = future.sort((a,b) => b.att - a.att)[0];
          if (!now || !best || !Number.isFinite(now.att) || !Number.isFinite(best.att)) return;
          const rise = Math.round(best.att - now.att);
          slot.innerHTML = `2번 일정 분석 연계 · <b>${escape(s.program)} ${s.no}회차</b> : 현재 예상 출석 ${comma(Math.round(now.att))}명 → 추천 시간 ${escape(best.t)}, ${comma(Math.round(best.att))}명
            ${rise > 0 ? `(<strong>+${rise}명</strong>)` : ''} · <a href="#schedule">시간대 근거 보기</a><p class="note">예상 출석은 회차 단위이며, 위 고유 출석 학생 증가 가정과는 별개의 지표입니다.</p>`;
        } catch (e) { /* 예산 데이터만 있을 때는 일정 연동을 생략한다. */ }
      }
      draw();
    }
  });
})();
