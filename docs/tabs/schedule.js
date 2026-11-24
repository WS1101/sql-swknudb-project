// 2번 회차 일정 점검 (서우진)
// 데이터: data/schedule.json  ←  pbl3/p2/export_schedule_json.sql 로 DB에서 내보냄
//   원본 테이블: pbl3.p2_slot_forecast(시간대별 예상 인원), pbl3.p2_session_factor(요인 분해),
//               pbl3.p2_model_run(검증 성능), pbl3.v_session_overview(실제 신청·출석)
App.register({
  id: 'schedule',
  label: '회차 일정 점검',
  order: 2,
  desc: '수업 시간과 겹치는지 미리 확인하고, 시간대를 바꾸면 참여 인원이 얼마나 달라지는지 비교합니다.',
  ready: true,
  data: 'data/schedule.json',
  render(root, D) {
    const WD = ['', '월', '화', '수', '목', '금', '토', '일'];
    const fmtDate = d => { const x = new Date(d + 'T00:00:00'); return `${x.getMonth() + 1}/${x.getDate()}(${WD[x.getDay() === 0 ? 7 : x.getDay()]})`; };
    const n0 = v => Math.round(v).toLocaleString('ko-KR');
    const level = c => c >= .6 ? 'crit' : c >= .3 ? 'warn' : 'ok';
    const isPast = (s, x) => s.status === 'SCHEDULED' && x.date <= D.asOf;
    // 예상 출석이 가장 많은 시간. 같으면(반올림 기준) 원래 날짜에 가까운 쪽
    const bestOf = s => {
      const gap = x => Math.abs(new Date(x.date) - new Date(s.date));
      return s.slots.filter(x => !isPast(s, x)).sort((a, b) =>
        Math.round(b.att) - Math.round(a.att) || gap(a) - gap(b) || (b.cur - a.cur))[0];
    };
    let cur = null, pick = null;

    root.innerHTML = `
      <div class="wrap">
        <aside class="side" aria-label="회차 목록">
          <h3>예정 회차</h3><div data-list="SCHEDULED"></div>
          <h3>지난 회차 돌아보기</h3><div data-list="COMPLETED"></div>
        </aside>
        <div class="main">
          <section class="card head" data-el="head"></section>
          <div data-el="alert"></div>
          <section class="compare" data-el="compare" aria-label="현재 일정과 선택한 일정 비교"></section>
          <div class="two">
            <section class="card">
              <div class="sec-h"><h2>같은 주 다른 시간이라면</h2><p>칸을 누르면 위에서 현재 일정과 비교합니다</p></div>
              <div class="grid-scroll"><div class="slots" data-el="slots" aria-label="요일·시각별 예상 출석"></div></div>
              <div class="legend">
                <span>예상 출석</span><span class="ramp"><i style="background:var(--s1)"></i><i style="background:var(--s3)"></i><i style="background:var(--s5)"></i><i style="background:var(--s7)"></i></span><span>많음</span>
                <span class="key"><i style="border:2px solid var(--ink)"></i>현재</span>
                <span class="key"><i style="border:2.5px solid var(--pick)"></i>선택</span>
                <span class="key" data-el="pastkey"><i style="background:var(--line)"></i>지난 날짜</span>
              </div>
            </section>
            <section class="card">
              <div class="sec-h"><h2>참여가 줄어드는 이유</h2></div>
              <div class="factors" data-el="factors"></div>
              <p class="note" style="margin-top:12px">그 이유가 없었다면 더 신청했을 것으로 보이는 인원입니다.</p>
            </section>
          </div>
          <p class="note" data-el="model"></p>
        </div>
      </div>`;
    const el = k => root.querySelector(`[data-el="${k}"]`);

    for (const status of ['SCHEDULED', 'COMPLETED']) {
      const box = root.querySelector(`[data-list="${status}"]`);
      D.sessions.filter(s => s.status === status).forEach(s => {
        const c = s.slots.find(x => x.cur);
        const b = document.createElement('button');
        b.className = 'item'; b.dataset.id = s.id;
        b.innerHTML = `<b>${s.program.replace(/ 20\d\d$/, '')}</b><span>${s.no}회차 · ${fmtDate(s.date)} ${s.start}</span>
          <em class="chip ${level(c.conf)}">수업 중 ${Math.round(c.conf * 100)}%</em>`;
        b.onclick = () => select(s.id);
        box.append(b);
      });
    }

    function select(id) {
      cur = D.sessions.find(s => s.id === id);
      root.querySelectorAll('.item').forEach(b => b.setAttribute('aria-current', String(+b.dataset.id === id)));
      pick = bestOf(cur);
      draw();
    }

    function draw() {
      const s = cur, c = s.slots.find(x => x.cur);
      el('head').innerHTML = `<h1>${s.program} · ${s.no}회차</h1>
        <div class="meta"><span>${fmtDate(s.date)} ${s.start}–${s.end}</span><span>${s.loc}</span>
        <span>대상 학생 <b class="num">${n0(c.elig)}</b>명 · 정원 <span class="num">${s.cap}</span>명</span>
        <span class="badge">${s.status === 'SCHEDULED' ? '예정' : '지난 회차'}</span></div>`;

      const lv = level(c.conf);
      const grades = Object.entries(c.grades).sort().filter(([, v]) => v > 0)
        .map(([g, v]) => `<span class="gchip">${g}학년 <b class="num">${Math.round(v * 100)}%</b></span>`).join('');
      const msg = lv === 'ok' ? '<strong>대상 학생 대부분이 이 시간에 수업이 없습니다.</strong>'
                              : `<strong>대상 학생의 ${Math.round(c.conf * 100)}%가 이 시간에 전공 수업 중입니다.</strong>`;
      el('alert').innerHTML = `<div class="alert ${lv}" role="status"><span class="ic" aria-hidden="true">${lv === 'ok' ? '✓' : '!'}</span>
        <div><p>${msg}${c.exam ? ' 시험기간 전후라 참여가 더 줄 수 있습니다.' : ''}</p>${grades ? `<div class="sub">학년별 수업 중 비율 ${grades}</div>` : ''}</div></div>`;

      const d = pick.att - c.att;
      const card = (x, label, sel) => `<div class="opt ${sel ? 'sel' : ''}">
        <div class="lbl"><span>${label}</span>${sel ? `<span class="delta ${Math.round(d) === 0 ? 'zero' : ''}">${d >= 0 ? '+' : ''}${Math.round(d)}명</span>` : ''}</div>
        <div class="when">${fmtDate(x.date)} ${x.t}</div>
        <div class="big">${n0(x.att)}<small>명 예상 출석</small></div>
        <div class="facts"><span>예상 신청 <b class="num">${n0(x.reg)}</b>명</span><span>수업 중인 학생 <b class="num">${Math.round(x.conf * 100)}%</b></span>
        ${!sel && s.actualAtt != null ? `<span>실제 출석 <b class="num">${s.actualAtt}</b>명</span>` : ''}${x.exam ? '<span>시험기간</span>' : ''}</div></div>`;
      el('compare').innerHTML = card(c, '현재 일정', false)
        + card(pick, pick.cur ? '선택: 현재와 같음' : (pick === bestOf(s) ? '추천 일정' : '선택한 일정'), true);

      const times = [...new Set(s.slots.map(x => x.t))].sort();
      const atts = s.slots.map(x => x.att), lo = Math.min(...atts), hi = Math.max(...atts);
      const steps = ['--s1', '--s2', '--s3', '--s4', '--s5', '--s6', '--s7'];
      const g = el('slots');
      g.innerHTML = '<div></div>' + times.map(t => `<div class="hd">${t}</div>`).join('');
      for (let w = 1; w <= 5; w++) {
        g.insertAdjacentHTML('beforeend', `<div class="rh">${WD[w]}</div>`);
        for (const t of times) {
          const x = s.slots.find(y => y.wd === w && y.t === t);
          const k = Math.min(6, Math.floor((x.att - lo) / Math.max(hi - lo, 1e-9) * 6.999));
          const past = isPast(s, x);
          const btn = document.createElement('button');
          btn.className = 'cell' + (x.cur ? ' cur' : '') + (x === pick ? ' sel' : '') + (past ? ' past' : '');
          btn.style.background = `var(${steps[k]})`;
          btn.style.color = k >= 4 ? 'var(--bg)' : 'var(--ink)';
          btn.setAttribute('aria-label', `${WD[w]}요일 ${t}, 예상 출석 ${Math.round(x.att)}명, 수업 중인 학생 ${Math.round(x.conf * 100)}%${past ? ', 지난 날짜' : ''}`);
          btn.innerHTML = `${x.cur ? '<span class="tag">현재</span>' : x === pick ? '<span class="tag">선택</span>' : ''}
            <span class="a">${Math.round(x.att)}</span><span class="c">수업 중 ${Math.round(x.conf * 100)}%</span>`;
          btn.disabled = past;
          btn.onclick = () => { pick = x; draw(); };
          g.append(btn);
        }
      }
      el('pastkey').hidden = !s.slots.some(x => isPast(s, x));

      const loss = s.factors.filter(f => f.lost >= 0.5), gain = s.factors.filter(f => f.lost <= -0.5);
      const mx = Math.max(1, ...s.factors.map(f => Math.abs(f.lost)));
      const PLAIN = { class_conflict: '수업 시간과 겹침', near_exam: '시험기간', cross_campus: '다른 캠퍼스에서 진행',
        time_of_day: '요일·시간대', vacation: '방학', fatigue: '회차가 거듭되며 감소', word_of_mouth: '직전 회차 평가가 낮음' };
      s.factors.forEach(f => { f.label = PLAIN[f.k] || f.label; });
      const row = (f, cls, sign) => `<div class="f ${cls}"><span class="n">${f.label}</span>
        <span class="bar"><i style="width:${Math.abs(f.lost) / mx * 100}%"></i></span><span class="v">${sign}${Math.round(Math.abs(f.lost))}명</span></div>`;
      el('factors').innerHTML = (loss.map(f => row(f, '', '−')).join('') || '<p class="note">눈에 띄게 신청을 줄이는 요인이 없습니다.</p>')
        + gain.map(f => row({ ...f, label: f.k === 'word_of_mouth' ? '직전 회차 좋은 평가' : f.label }, 'gain', '+')).join('');

      el('model').textContent = `예상 인원은 지난 프로그램 참여 기록을 바탕으로 계산했습니다. 가상 데이터 · 기준일 ${D.asOf}`;
    }

    select(D.sessions[0].id);
  }
});
