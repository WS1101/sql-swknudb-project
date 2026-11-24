// 만족도 진단: 프로그램별 핵심 지표와 전체 응답 품질·재참여 집계만 표시한다.
(() => {
  'use strict';

  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
  const valid = value => typeof value === 'number' && Number.isFinite(value);
  const format = (value, digits = 0) => valid(value)
    ? value.toLocaleString('ko-KR', {minimumFractionDigits: digits, maximumFractionDigits: digits}) : '자료 없음';
  const percent = value => valid(value) ? `${format(value * 100, 2)}%` : '자료 없음';
  const signed = (value, digits = 3) => {
    if (!valid(value)) return '자료 없음';
    const rounded = Number(value.toFixed(digits));
    return `${rounded > 0 ? '+' : rounded < 0 ? '−' : ''}${format(Math.abs(rounded), digits)}`;
  };
  const valueText = (value, unit, digits) => valid(value) ? `${format(value, digits)}${unit}` : '자료 없음';
  const score = value => valueText(value, '점', 3);
  const change = value => valid(value) ? `${signed(value)}점` : '자료 없음';
  const array = value => Array.isArray(value) ? value : [];
  const saved = {programId: null, search: '', sort: 'responses'};
  const typeNames = {
    normal: '정상 범위 응답', fast_only: '빠른 응답만 탐지',
    straight_only: '동일 점수 반복만 탐지', fast_straight: '빠른 응답 + 동일 점수 반복'
  };

  // 막대는 명시된 0 기준 축을 사용한다. 정확한 값은 숫자와 title로 함께 제공한다.
  function bars(rows, {max, ticks, unit = '', digits = 2, caption}) {
    if (!rows.length || !valid(max) || max <= 0) return '<p class="note">표시할 차트 데이터가 없습니다.</p>';
    return `<figure class="s-chart"><figcaption>${escape(caption)}</figcaption>
      <div class="factors">${rows.map(row => {
        const width = valid(row.value) ? Math.max(0, Math.min(100, row.value / max * 100)) : 0;
        return `<div class="s-bar-row ${row.warning ? 's-warning' : ''}">
          <div class="s-bar-label">${escape(row.label)}${row.note ? `<small>${escape(row.note)}</small>` : ''}</div>
          <div class="s-track" aria-hidden="true"><i style="width:${width}%"></i></div>
          <span class="s-value num" title="${escape(valid(row.value) ? `${row.value}${unit}` : '자료 없음')}">${escape(valueText(row.value, unit, digits))}</span>
        </div>`;
      }).join('')}</div>
      <div class="s-axis" aria-hidden="true"><div>${ticks.map(t => `<span>${escape(t.toLocaleString('ko-KR', {maximumFractionDigits: 3}))}</span>`).join('')}</div></div>
    </figure>`;
  }

  function metric(label, value, unit, note, selected = false) {
    return `<div class="opt ${selected ? 'sel' : ''}"><div class="lbl">${escape(label)}</div>
      <div class="big">${escape(value)}${unit ? `<small>${escape(unit)}</small>` : ''}</div>
      <p class="s-metric-note">${escape(note)}</p></div>`;
  }

  App.register({
    id: 'satisfaction', label: '만족도 진단', order: 1, ready: true,
    desc: '프로그램 만족도를 응답 품질과 실제 후속 참여로 함께 살펴봅니다.',
    data: 'data/satisfaction.json',
    render(root, data) {
      const D = data || {}, meta = D.meta || {};
      const programs = array(D.programs).filter(p => p && p.program_id != null);
      const groups = array(D.behavior?.groups), types = array(D.quality?.types);
      const state = {...saved};
      if (!programs.some(p => p.program_id === state.programId)) {
        state.programId = [...programs].sort((a, b) => (b.response_count ?? -1) - (a.response_count ?? -1))[0]?.program_id ?? null;
      }
      const persist = () => Object.assign(saved, state);
      const scope = '<span class="s-scope">전체 프로그램 통합 분석</span>';
      const source = `${meta.synthetic === true ? '합성 데이터' : '데이터 출처 확인 필요'} · 기준일 ${meta.database_asof || '기록 없음'}`;

      root.innerHTML = `<div class="satisfaction-app">
        <style>
          .satisfaction-app{font-size:16px;line-height:1.65}
          .satisfaction-app .wrap{padding:0;max-width:none;grid-template-columns:270px minmax(0,1fr);gap:20px}
          .satisfaction-app .s-side{padding:16px;max-height:calc(100vh - 28px);overflow-y:auto}
          .satisfaction-app .s-side h2{font-size:17px;margin:0 0 14px}
          .satisfaction-app label{display:flex;flex-direction:column;gap:6px;font-size:14px;font-weight:600;color:var(--ink-2)}
          .satisfaction-app input,.satisfaction-app select{width:100%;min-width:0;min-height:44px;font:inherit;font-weight:400;color:var(--ink);border:1px solid var(--line);border-radius:9px;background:var(--panel);padding:9px 10px}
          .satisfaction-app select{appearance:none;padding-right:30px;background-image:linear-gradient(45deg,transparent 50%,var(--ink-2) 50%),linear-gradient(135deg,var(--ink-2) 50%,transparent 50%);background-position:calc(100% - 16px) 50%,calc(100% - 12px) 50%;background-size:4px 4px;background-repeat:no-repeat}
          .satisfaction-app .s-controls{display:grid;gap:12px;margin-bottom:12px}
          .satisfaction-app .s-list-count{margin:0 0 8px;font-size:14px;color:var(--ink-2)}
          .satisfaction-app .item{display:block;padding:13px 10px;min-height:76px}
          .satisfaction-app .item b{display:block;white-space:normal;line-height:1.6;font-size:14px}
          .satisfaction-app .item span{display:block;font-size:14px;color:var(--ink-2);margin-top:4px}
          .satisfaction-app .item em{font-style:normal;color:var(--warn)}
          .satisfaction-app .head{display:block}
          .satisfaction-app .head h1{margin:8px 0;font-size:23px}
          .satisfaction-app .head .meta{font-size:14px;line-height:1.7}
          .satisfaction-app .s-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}
          .satisfaction-app .s-kpis .big{margin-top:12px;font-size:32px;overflow-wrap:anywhere}
          .satisfaction-app .opt .lbl{font-size:14px;color:var(--ink-2)}
          .satisfaction-app .s-metric-note{margin:10px 0 0;font-size:14px;color:var(--ink-2)}
          .satisfaction-app .sec-h{align-items:center;gap:8px}
          .satisfaction-app .sec-h h2{font-size:18px;line-height:1.5}
          .satisfaction-app .s-scope{display:inline-block;padding:3px 9px;font-size:13px;font-weight:600;border-radius:6px;background:var(--accent-soft);color:var(--pick)}
          .satisfaction-app .note{font-size:14px;color:var(--ink-2);overflow-wrap:anywhere}
          .satisfaction-app .s-two{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}
          .satisfaction-app .s-two>*{min-width:0}
          .satisfaction-app .s-chart{margin:16px 0 20px}
          .satisfaction-app .s-chart figcaption{font-size:14px;font-weight:600;color:var(--ink-2);margin-bottom:14px}
          .satisfaction-app .s-bar-row{display:grid;grid-template-columns:138px minmax(0,1fr) 94px;gap:10px;align-items:center}
          .satisfaction-app .s-bar-label{font-size:14px;line-height:1.5;overflow-wrap:anywhere}
          .satisfaction-app .s-bar-label small{display:block;color:var(--ink-2);font-size:13px;margin-top:3px}
          .satisfaction-app .s-track{height:12px;border-radius:4px;background:var(--line-2);overflow:hidden}
          .satisfaction-app .s-track i{display:block;height:100%;background:var(--accent);border-radius:3px}
          .satisfaction-app .s-warning .s-track i{background:var(--warn)}
          .satisfaction-app .s-value{font-size:14px;text-align:right;white-space:nowrap}
          .satisfaction-app .s-axis{margin:8px 104px 0 148px;font:13px var(--mono);color:var(--ink-2)}
          .satisfaction-app .s-axis>div{display:flex;justify-content:space-between;border-top:1px solid var(--line);padding-top:5px}
          .satisfaction-app .s-two .s-bar-row{grid-template-columns:108px minmax(0,1fr) 83px;gap:8px}
          .satisfaction-app .s-two .s-axis{margin-left:116px;margin-right:91px}
          .satisfaction-app .s-empty{padding:18px;border:1px dashed var(--line);border-radius:12px;color:var(--ink-2)}
          .satisfaction-app .s-sr{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap;border:0}
          @media(max-width:1100px){
            .satisfaction-app .s-two{grid-template-columns:minmax(0,1fr);gap:8px}
          }
          @media(max-width:900px){
            .satisfaction-app .wrap{grid-template-columns:minmax(0,1fr)}
            .satisfaction-app .s-side{position:static;max-height:none}
            .satisfaction-app .s-program-list{max-height:240px;overflow-y:auto;padding:2px}
            .satisfaction-app .s-controls{grid-template-columns:repeat(2,minmax(0,1fr))}
          }
          @media(max-width:560px){
            .satisfaction-app .card{padding:20px 16px;border-radius:16px}
            .satisfaction-app .s-kpis{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
            .satisfaction-app .opt{padding:14px 12px;border-radius:14px}
            .satisfaction-app .s-kpis .big{font-size:25px}
            .satisfaction-app .big small{font-size:13px}
            .satisfaction-app .s-controls{grid-template-columns:minmax(0,1fr)}
            .satisfaction-app .s-bar-row,.satisfaction-app .s-two .s-bar-row{grid-template-columns:94px minmax(0,1fr) 76px;gap:7px}
            .satisfaction-app .s-value{font-size:13px}
            .satisfaction-app .s-bar-label{font-size:14px}
            .satisfaction-app .s-axis,.satisfaction-app .s-two .s-axis{margin-left:101px;margin-right:83px;font-size:12px}
            .satisfaction-app .head h1{font-size:21px}
          }
        </style>
        <div class="wrap">
          <aside class="side s-side" aria-label="분석할 프로그램 선택">
            <h2>프로그램 선택</h2>
            <div class="s-controls">
              <label>프로그램 검색<input type="search" data-s="search" placeholder="프로그램명 또는 연도" autocomplete="off"></label>
              <label>목록 정렬<select data-s="sort"><option value="responses">설문 응답 수 많은 순</option><option value="ratio">의심 응답 비율 높은 순</option><option value="name">프로그램 이름순</option></select></label>
            </div>
            <p class="s-list-count" data-s="list-count" role="status"></p>
            <div class="s-program-list" data-s="list"></div>
          </aside>
          <div class="main">
            <section class="card head" data-s="program-head" aria-label="선택한 프로그램"></section>
            <div class="compare s-kpis" data-s="kpis" aria-label="기본 기준 만족도 핵심 지표"></div>

            <section class="card" aria-labelledby="s-quality-title">
              <div class="sec-h"><h2 id="s-quality-title">응답 품질은 어떻게 판단했을까?</h2>${scope}</div>
              <div data-s="quality"></div>
            </section>

            <section class="card" aria-labelledby="s-behavior-title">
              <div class="sec-h"><h2 id="s-behavior-title">만족도가 높으면 실제로 다시 참여할까?</h2>${scope}</div>
              <div class="s-two" data-s="behavior-charts"></div>
            </section>
          </div>
        </div>
        <p class="s-sr" data-s="selection-status" role="status" aria-live="polite"></p>
      </div>`;

      const el = key => root.querySelector(`[data-s="${key}"]`);
      const selected = () => programs.find(p => p.program_id === state.programId);

      function drawList() {
        const query = state.search.trim().normalize('NFKC').toLocaleLowerCase('ko-KR');
        const rows = programs.filter(p => String(p.program_name ?? '').normalize('NFKC').toLocaleLowerCase('ko-KR').includes(query));
        rows.sort((a, b) => {
          if (state.sort === 'ratio') return (b.suspicious_ratio ?? -1) - (a.suspicious_ratio ?? -1) || String(a.program_name).localeCompare(String(b.program_name), 'ko');
          if (state.sort === 'name') return String(a.program_name).localeCompare(String(b.program_name), 'ko');
          return (b.response_count ?? -1) - (a.response_count ?? -1) || a.program_id - b.program_id;
        });
        el('list-count').textContent = `${format(rows.length)} / ${format(programs.length)}개 프로그램`;
        el('list').replaceChildren();
        if (!rows.length) el('list').innerHTML = '<p class="s-empty">검색 결과가 없습니다. 검색어를 바꿔 주세요.</p>';
        rows.forEach(p => {
          const button = document.createElement('button');
          button.type = 'button'; button.className = 'item'; button.dataset.program = p.program_id;
          button.setAttribute('aria-current', String(p.program_id === state.programId));
          button.innerHTML = `<b>${escape(p.program_name || '이름 없음')}</b><span>${escape(p.year ?? '연도 없음')} · 설문 ${format(p.response_count)}건 · <em>의심 ${percent(p.suspicious_ratio)}</em></span>`;
          button.onclick = () => {
            state.programId = p.program_id;
            el('list').querySelectorAll('button').forEach(b => b.setAttribute('aria-current', String(b === button)));
            drawProgram(); persist();
            el('selection-status').textContent = `${p.program_name} 선택. 원본 ${score(p.original_mean)}, 의심 응답 제외 ${score(p.filtered_mean)}.`;
          };
          el('list').append(button);
        });
      }

      function drawProgram() {
        const p = selected();
        if (!p) {
          el('program-head').innerHTML = `<h1>프로그램 집계가 없습니다</h1><div class="meta">${escape(source)}</div>`;
          el('kpis').innerHTML = '';
        } else {
          el('program-head').innerHTML = `<h1>${escape(p.program_name)}</h1>
            <div class="meta"><span>유효 설문 ${format(p.response_count)}건</span><span>${escape(source)}</span></div>`;
          el('kpis').innerHTML = metric('원본 만족도 평균', format(p.original_mean, 3), valid(p.original_mean) ? '/ 5점' : '', '전체 유효 응답의 점수형 문항 평균')
            + metric('의심 응답 제외 만족도', format(p.filtered_mean, 3), valid(p.filtered_mean) ? '/ 5점' : '', `원본 대비 ${change(p.mean_change)}`, true)
            + metric('품질 가중 만족도', format(p.weighted_mean, 3), valid(p.weighted_mean) ? '/ 5점' : '', '품질 점수 / 100을 가중치로 사용')
            + metric('품질 의심 응답 비율', valid(p.suspicious_ratio) ? format(p.suspicious_ratio * 100, 2) : '자료 없음', valid(p.suspicious_ratio) ? '%' : '', `${format(p.suspicious_count)} / ${format(p.response_count)}건 · 불성실 확정 아님`);
        }
      }

      function drawQuality() {
        el('quality').innerHTML = bars(types.map(t => ({label: typeNames[t.id] || t.source_label, value: t.response_count,
          note: `${format(t.quality_score)}점 · ${t.is_suspicious ? '기본 제외 대상' : '기본 제외 안 함'}`, warning: t.is_suspicious})),
          {max: D.quality?.response_count, ticks: valid(D.quality?.response_count) ? [0, D.quality.response_count / 2, D.quality.response_count] : [], unit: '건', digits: 0, caption: `응답 유형별 건수 · 전체 ${format(D.quality?.response_count)}건 기준`});
      }

      function drawBehavior() {
        const wanted = ['전체', '빠른 응답', '의심 응답 제외', '만족도 4점 이상', '만족도 3점 미만'];
        const rows = wanted.map(name => groups.find(g => g.group === name)).filter(Boolean);
        el('behavior-charts').innerHTML = bars(rows.map(g => ({label: g.group, value: g.mean_satisfaction, note: `유효 ${format(g.response_count)}건`, warning: g.group === '빠른 응답'})),
          {max: 5, ticks: [0, 1, 2, 3, 4, 5], unit: '점', digits: 3, caption: '집단별 평균 만족도 · 0~5점'})
          + bars(rows.map(g => ({label: g.group, value: valid(g.reparticipation_rate) ? g.reparticipation_rate * 100 : null, note: `관찰 완료 ${format(g.observable_count)}건`, warning: g.group === '빠른 응답'})),
            {max: 100, ticks: [0, 25, 50, 75, 100], unit: '%', digits: 2, caption: '관찰 완료 응답의 재참여율 · 0~100%'});
      }

      el('search').value = state.search;
      el('sort').value = state.sort;
      el('search').oninput = () => { state.search = el('search').value; drawList(); persist(); };
      el('sort').onchange = () => { state.sort = el('sort').value; drawList(); persist(); };
      drawList(); drawProgram(); drawQuality(); drawBehavior(); persist();
    }
  });
})();
