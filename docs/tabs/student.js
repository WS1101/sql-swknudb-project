// 학생 활동 조회 (사업단 자문 요청: "학번을 치면 학기별 활동을 그래프로")
// 데이터: data/students.json  ←  pbl3/export_students_json.sql (pbl3.v_student_term_activity)
// 관리자 전용 화면을 가정. 이름·연락처는 내보내지도, 표시하지도 않는다.
App.register({
  id: 'student',
  label: '학생 활동 조회',
  desc: '학번을 입력하면 학기별 프로그램 참여와 마일리지를 한눈에 보여줍니다.',
  order: 4,
  ready: true,
  data: 'data/students.json',
  render(root, D) {
    const byNo = new Map(D.students.map(s => [s.no, s]));
    // 시연용 표시 학번: 화면에는 팀원 학번을 보여주고, 데이터는 가상 학번으로 찾는다 (가상 데이터)
    const ALIAS = { '202202206': '202406024', '202202189': '202405016', '202202216': '202307007' };
    const SHOWN = Object.fromEntries(Object.entries(ALIAS).map(([a, b]) => [b, a]));
    const resolve = no => ALIAS[no] || no;
    const termLabel = new Map(D.terms.map(t => [t.id, t.label]));
    const examples = [
      ['활동이 많은 학생', '202202206'],
      ['보통 학생', '202202189'],
      ['최근 활동이 끊긴 학생', '202202216'],
    ].filter(([, no]) => byNo.has(resolve(no)));

    root.innerHTML = `
      <div class="stu">
        <section class="card stu-search">
          <form data-el="form" class="stu-form" autocomplete="off">
            <label for="stu-no">학번</label>
            <input id="stu-no" data-el="input" placeholder="예: ${examples[0]?.[1] || '202202206'}" inputmode="text">
            <button type="submit" class="btn">조회</button>
          </form>
          <div class="stu-ex"><span>예시</span>${examples.map(([l, no]) => `<button type="button" class="ex" data-no="${no}">${l}</button>`).join('')}</div>
          <p class="note">관리자 전용 · 이름과 연락처는 표시하지 않습니다</p>
        </section>
        <div data-el="out" class="stu-out"></div>
      </div>`;
    const el = k => root.querySelector(`[data-el="${k}"]`);
    el('form').onsubmit = e => { e.preventDefault(); show(el('input').value.trim().toUpperCase().replace(/^P3/, '')); };
    root.querySelectorAll('.ex').forEach(b => b.onclick = () => { el('input').value = b.dataset.no; show(b.dataset.no); });

    function show(no) {
      const s0 = byNo.get(resolve(no));
      const s = s0 && SHOWN[s0.no] ? { ...s0, dept: '소프트웨어학과', grp: '3학년' } : s0;
      if (!s) {
        el('out').innerHTML = `<div class="alert warn"><span class="ic" aria-hidden="true">!</span><div><p><strong>학번 ${no || '(빈 값)'}을 찾을 수 없습니다.</strong></p><div class="sub">예시 버튼을 눌러보거나 9자리 학번을 입력하세요.</div></div></div>`;
        return;
      }
      const terms = s.terms.map(([id, att, mil]) => ({ id, att, mil, label: termLabel.get(id), avg: +(D.groupAvg[s.grp]?.[id] ?? 0) }));
      const last = terms[terms.length - 1], prev = terms.slice(0, -1);
      const prevAvg = prev.length ? prev.reduce((a, t) => a + t.att, 0) / prev.length : 0;
      const status = { ENROLLED: '재학', ON_LEAVE: '휴학', GRADUATED: '졸업', WITHDRAWN: '자퇴' }[s.st];

      // 최근 학기 신호: 전에는 활발했는데 이번 학기 0회
      let signal = '';
      if (s.st === 'ENROLLED' && last && last.att === 0 && prevAvg >= 1.5) {
        signal = `<div class="alert warn"><span class="ic" aria-hidden="true">!</span><div><p><strong>${last.label}에는 참여가 없습니다.</strong> 이전 학기에는 평균 ${prevAvg.toFixed(1)}회 참여했습니다.</p><div class="sub">활동이 갑자기 끊긴 학생은 상담이나 안내가 필요할 수 있습니다.</div></div></div>`;
      } else if (s.att === 0) {
        signal = `<div class="alert ok" style="background:var(--line-2)"><span class="ic" aria-hidden="true" style="background:var(--ink-3)">i</span><div><p><strong>아직 참여한 프로그램이 없습니다.</strong></p></div></div>`;
      }

      el('out').innerHTML = `
        <section class="card stu-head">
          <div><h1 class="num">${SHOWN[s.no] || s.no}</h1>
            <div class="meta"><span>${s.dept}</span><span>${s.grp}</span>${SHOWN[s.no] ? '' : `<span>${s.adm} 입학${s.tr ? ' (편입)' : ''}</span>`}<span class="badge">${status}</span></div></div>
        </section>
        ${signal}
        <section class="kpis">
          <div class="kpi"><span class="k">총 참여</span><span class="big">${s.att}<small>회</small></span><span class="note">신청 후 불참 ${s.ns}회</span></div>
          <div class="kpi"><span class="k">예상 적립 마일리지</span><span class="big">${s.mil}<small>점</small></span><span class="note">참여한 프로그램 기준</span></div>
          <div class="kpi"><span class="k">같은 ${s.grp === '졸업' ? '졸업생' : '학년'} 중 상위</span><span class="big">${s.att === 0 ? '—' : Math.max(1, s.top) + '<small>%</small>'}</span></div>
        </section>
        <section class="card">
          <div class="sec-h"><h2>학기별 참여</h2>
            <p><span class="key"><i style="background:var(--s5)"></i>이 학생</span> &nbsp; <span class="key"><i style="background:var(--ink-3);height:2px;border-radius:0"></i>같은 ${s.grp === '졸업' ? '졸업생' : '학년'} 평균</span></p></div>
          ${chart(terms)}
        </section>
        <section class="card">
          <div class="sec-h"><h2>참여한 프로그램</h2><p>최근 순 · ×는 참여 횟수</p></div>
          <div class="progs">${(s.progs || []).map(p => `<span class="prog">${p.p}<b class="num">×${p.n}</b></span>`).join('') || '<p class="note">없음</p>'}</div>
        </section>`;
    }

    function chart(terms) {
      const W = 900, H = 260, L = 34, R = 12, T = 18, B = 34;
      const max = Math.max(4, ...terms.map(t => Math.max(t.att, t.avg)));
      const step = max <= 6 ? 1 : max <= 12 ? 2 : 5;
      const top = Math.ceil(max / step) * step;
      const y = v => T + (H - T - B) * (1 - v / top);
      const bw = (W - L - R) / terms.length;
      const ticks = []; for (let v = 0; v <= top; v += step) ticks.push(v);
      const grid = ticks.map(v => `<line x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}" stroke="var(--line)" stroke-width="1"/><text x="${L - 8}" y="${y(v) + 4}" text-anchor="end" font-size="11" fill="var(--ink-3)">${v}</text>`).join('');
      const bars = terms.map((t, i) => {
        const x = L + i * bw + bw * 0.22, w = bw * 0.56, h = y(0) - y(t.att);
        return `<g><title>${t.label}: ${t.att}회 참여, 마일리지 ${t.mil}점 (학년 평균 ${t.avg.toFixed(1)}회)</title>
          ${t.att > 0 ? `<path d="M${x},${y(0)} v${-Math.max(h - 1, 0)} q0,-1 1,-1 h${w - 2} q1,0 1,1 v${Math.max(h - 1, 0)} z" fill="var(--s5)"/>` : ''}
          <text x="${x + w / 2}" y="${Math.min(y(t.att), y(t.avg)) - 8}" text-anchor="middle" font-size="12" font-weight="600" fill="var(--ink)">${t.att}</text>
          <text x="${x + w / 2}" y="${H - 12}" text-anchor="middle" font-size="11.5" fill="var(--ink-2)">${t.label}</text></g>`;
      }).join('');
      const pts = terms.map((t, i) => `${L + i * bw + bw / 2},${y(t.avg)}`).join(' ');
      const avg = `<polyline points="${pts}" fill="none" stroke="var(--ink-3)" stroke-width="2" stroke-dasharray="5 4"/>`
        + terms.map((t, i) => `<circle cx="${L + i * bw + bw / 2}" cy="${y(t.avg)}" r="3" fill="var(--panel)" stroke="var(--ink-3)" stroke-width="2"/>`).join('');
      return `<div class="chart-scroll"><svg viewBox="0 0 ${W} ${H}" class="chart" role="img" aria-label="학기별 참여 회차 막대그래프">${grid}${bars}${avg}</svg></div>`;
    }

    if (examples.length) { el('input').value = examples[0][1]; show(examples[0][1]); }
  }
});
