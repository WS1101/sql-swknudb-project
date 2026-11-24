// 만족도 진단: 저장된 집계만 표시하며 DB 조회나 모델 재학습을 수행하지 않는다.
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
  const ratio = (a, b) => valid(a) && valid(b) && b > 0 ? a / b : null;
  const valueText = (value, unit, digits) => valid(value) ? `${format(value, digits)}${unit}` : '자료 없음';
  const score = value => valueText(value, '점', 3);
  const change = value => valid(value) ? `${signed(value)}점` : '자료 없음';
  const array = value => Array.isArray(value) ? value : [];
  const saved = {programId: null, search: '', sort: 'responses', seconds: null, mode: null, policy: null};
  const typeNames = {
    normal: '정상 범위 응답', fast_only: '빠른 응답만 탐지',
    straight_only: '동일 점수 반복만 탐지', fast_straight: '빠른 응답 + 동일 점수 반복'
  };
  const modeNames = {absolute: '절대 기준만', relative: '상대 기준만', either: '둘 중 하나', both: '두 기준 모두'};

  // 막대는 명시된 0 기준 축을 사용한다. 정확한 값은 숫자와 title로 함께 제공한다.
  function bars(rows, {max, ticks, unit = '', digits = 2, caption}) {
    if (!rows.length || !valid(max) || max <= 0) return '<p class="note">표시할 차트 데이터가 없습니다.</p>';
    return `<figure class="s-chart"><figcaption>${escape(caption)}</figcaption>
      <div class="factors">${rows.map(row => {
        const width = valid(row.value) ? Math.max(0, Math.min(100, row.value / max * 100)) : 0;
        return `<div class="s-bar-row ${row.muted ? 's-muted' : ''} ${row.warning ? 's-warning' : ''}">
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
      const D = data || {}, meta = D.meta || {}, config = meta.config || {};
      const programs = array(D.programs).filter(p => p && p.program_id != null);
      const sensitivity = array(D.sensitivity), groups = array(D.behavior?.groups), types = array(D.quality?.types);
      const model = D.model || {}, metrics = array(model.metrics), importance = array(model.importance);
      const state = {...saved};
      if (!programs.some(p => p.program_id === state.programId)) {
        state.programId = [...programs].sort((a, b) => (b.response_count ?? -1) - (a.response_count ?? -1))[0]?.program_id ?? null;
      }
      state.seconds ??= config.absolute_seconds;
      state.mode ??= config.speed_mode;
      const policies = [...new Set(array(D.satisfactionBehavior).map(r => r.policy))];
      if (!policies.includes(state.policy)) state.policy = policies[0] ?? null;
      const persist = () => Object.assign(saved, state);
      const scope = '<span class="s-scope">전체 프로그램 통합 분석</span>';
      const baseRule = `문항당 ${format(config.absolute_seconds)}초 미만 · ${config.speed_mode || '기준 없음'} · 품질 ${format(config.suspicious_below)}점 미만 제외`;

      root.innerHTML = `<div class="satisfaction-app">
        <style>
          .satisfaction-app{font-size:16px;line-height:1.65}
          .satisfaction-app .wrap{padding:0;max-width:none;grid-template-columns:270px minmax(0,1fr);gap:20px}
          .satisfaction-app .s-banner{padding:16px 20px;border:1px solid var(--line);border-radius:16px;background:var(--band);margin-bottom:20px}
          .satisfaction-app .s-banner b{color:var(--pick)}
          .satisfaction-app .s-banner p{margin:4px 0 0;font-size:14px;color:var(--ink-2)}
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
          .satisfaction-app .s-side .note{margin-top:12px}
          .satisfaction-app .head{display:block}
          .satisfaction-app .head h1{margin:8px 0;font-size:23px}
          .satisfaction-app .head .meta{font-size:14px;line-height:1.7}
          .satisfaction-app .s-eyebrow{font-size:14px;font-weight:600;color:var(--accent);margin:0}
          .satisfaction-app .s-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}
          .satisfaction-app .s-kpis .big{margin-top:12px;font-size:32px;overflow-wrap:anywhere}
          .satisfaction-app .opt .lbl{font-size:14px;color:var(--ink-2)}
          .satisfaction-app .s-metric-note{margin:10px 0 0;font-size:14px;color:var(--ink-2)}
          .satisfaction-app .sec-h{align-items:center;gap:8px}
          .satisfaction-app .sec-h h2{font-size:18px;line-height:1.5}
          .satisfaction-app .sec-h p{font-size:14px;color:var(--ink-2)}
          .satisfaction-app .s-scope,.satisfaction-app .s-tag{display:inline-block;padding:3px 9px;font-size:13px;font-weight:600;border-radius:6px;background:var(--accent-soft);color:var(--pick)}
          .satisfaction-app .s-tag{background:var(--line-2);color:var(--ink-2)}
          .satisfaction-app .chip{font-size:13px;grid-row:auto;grid-column:auto;font-family:var(--font);white-space:normal}
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
          .satisfaction-app .s-muted .s-track i{background:var(--ink-3)}
          .satisfaction-app .s-warning .s-track i{background:var(--warn)}
          .satisfaction-app .s-value{font-size:14px;text-align:right;white-space:nowrap}
          .satisfaction-app .s-axis{margin:8px 104px 0 148px;font:13px var(--mono);color:var(--ink-2)}
          .satisfaction-app .s-axis>div{display:flex;justify-content:space-between;border-top:1px solid var(--line);padding-top:5px}
          .satisfaction-app .s-two .s-bar-row{grid-template-columns:108px minmax(0,1fr) 83px;gap:8px}
          .satisfaction-app .s-two .s-axis{margin-left:116px;margin-right:91px}
          .satisfaction-app .s-delta{display:flex;align-items:center;justify-content:space-between;gap:12px;background:var(--accent-soft);border-radius:12px;padding:14px 16px;margin-bottom:12px}
          .satisfaction-app .s-delta b{font:600 23px var(--mono);color:var(--pick);white-space:nowrap}
          .satisfaction-app .s-rules{display:grid;gap:10px;padding-left:20px;margin:14px 0}
          .satisfaction-app .s-rules li{padding-left:2px}
          .satisfaction-app details{border-top:1px solid var(--line);padding-top:14px;margin-top:18px}
          .satisfaction-app summary{font-size:15px;font-weight:600;cursor:pointer;min-height:40px;line-height:1.6;color:var(--pick)}
          .satisfaction-app details p{margin:10px 0}
          .satisfaction-app .s-table-scroll{max-width:100%;overflow:auto;margin:12px 0}
          .satisfaction-app table{width:100%;border-collapse:collapse;font-size:14px;text-align:left}
          .satisfaction-app caption{text-align:left;font-weight:600;color:var(--ink-2);margin-bottom:10px}
          .satisfaction-app th,.satisfaction-app td{border-bottom:1px solid var(--line);padding:11px 10px;vertical-align:top}
          .satisfaction-app thead{background:var(--line-2)}
          .satisfaction-app th{font-weight:600}
          .satisfaction-app .s-numeric{font-family:var(--mono);white-space:nowrap;text-align:right;font-variant-numeric:tabular-nums}
          .satisfaction-app .s-example{background:var(--line-2);border-radius:12px;padding:14px}
          .satisfaction-app .s-example table{min-width:490px}
          .satisfaction-app .s-experiment-controls{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin:18px 0}
          .satisfaction-app .s-experiment-results{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:16px 0}
          .satisfaction-app .s-stat{border:1px solid var(--line);background:var(--band);padding:14px 12px;border-radius:12px}
          .satisfaction-app .s-stat span{display:block;color:var(--ink-2);font-size:14px}
          .satisfaction-app .s-stat b{display:block;font-size:20px;margin-top:5px;overflow-wrap:anywhere}
          .satisfaction-app .s-experiment-title{font-size:15px;font-weight:600;color:var(--pick);margin:10px 0}
          .satisfaction-app .s-training{display:flex;flex-wrap:wrap;gap:8px 18px;padding:12px 0;font-size:14px;color:var(--ink-2)}
          .satisfaction-app .s-model-table{min-width:570px}
          .satisfaction-app .s-scenario-table{min-width:390px}
          .satisfaction-app .s-source-list{padding-left:20px;font-size:14px;overflow-wrap:anywhere}
          .satisfaction-app a{color:var(--accent);text-underline-offset:3px}
          .satisfaction-app .s-limitations{padding-left:20px;display:grid;gap:10px;margin:14px 0}
          .satisfaction-app .s-empty{padding:18px;border:1px dashed var(--line);border-radius:12px;color:var(--ink-2)}
          .satisfaction-app [hidden]{display:none!important}
          .satisfaction-app .s-sr{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap;border:0}
          @media(max-width:1100px){
            .satisfaction-app .s-two{grid-template-columns:minmax(0,1fr);gap:8px}
            .satisfaction-app .s-experiment-results{grid-template-columns:repeat(2,minmax(0,1fr))}
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
            .satisfaction-app .s-controls,.satisfaction-app .s-experiment-controls{grid-template-columns:minmax(0,1fr)}
            .satisfaction-app .s-bar-row,.satisfaction-app .s-two .s-bar-row{grid-template-columns:94px minmax(0,1fr) 76px;gap:7px}
            .satisfaction-app .s-value{font-size:13px}
            .satisfaction-app .s-bar-label{font-size:14px}
            .satisfaction-app .s-axis,.satisfaction-app .s-two .s-axis{margin-left:101px;margin-right:83px;font-size:12px}
            .satisfaction-app .s-delta{align-items:flex-start;flex-direction:column}
            .satisfaction-app .s-stat b{font-size:18px}
            .satisfaction-app .head h1{font-size:21px}
          }
        </style>
        <div class="s-banner">
          <b>${meta.synthetic === true ? '합성 데이터 기반 실험' : '데이터 출처 확인 필요'} · 저장된 분석 결과</b>
          <p>DB 기준 ${escape(meta.database_asof || '기록 없음')} · 모델 평가 기준 ${escape(model.asof || meta.model_asof || '기록 없음')}</p>
          <p>유효 응답 <span class="num">${format(meta.valid_responses)}</span>건 · 기본 의심 응답 <span class="num">${format(meta.suspicious_responses)}</span>건 (${percent(ratio(meta.suspicious_responses, meta.valid_responses))}) · 관찰 완료 <span class="num">${format(meta.observable)}</span>건</p>
        </div>
        <div class="wrap">
          <aside class="side s-side" aria-label="분석할 프로그램 선택">
            <h2>프로그램 선택</h2>
            <div class="s-controls">
              <label>프로그램 검색<input type="search" data-s="search" placeholder="프로그램명 또는 연도" autocomplete="off"></label>
              <label>목록 정렬<select data-s="sort"><option value="responses">설문 응답 수 많은 순</option><option value="ratio">의심 응답 비율 높은 순</option><option value="name">프로그램 이름순</option></select></label>
            </div>
            <p class="s-list-count" data-s="list-count" role="status"></p>
            <div class="s-program-list" data-s="list"></div>
            <p class="note">목록의 비율은 기본 기준의 의심 응답 비율입니다. 검색은 목록만 좁히며 현재 선택은 유지합니다.</p>
          </aside>
          <div class="main">
            <section class="card head" data-s="program-head" aria-label="선택한 프로그램"></section>
            <div class="compare s-kpis" data-s="kpis" aria-label="기본 기준 만족도 핵심 지표"></div>
            <section class="card" data-s="comparison" aria-label="프로그램 만족도 비교"></section>

            <section class="card" aria-labelledby="s-quality-title">
              <div class="sec-h"><h2 id="s-quality-title">응답 품질은 어떻게 판단했을까?</h2>${scope}</div>
              <p class="note">${escape(baseRule)}. 품질 점수는 규칙 기반 지표이며 검증된 성실 확률이 아닙니다.</p>
              <div data-s="quality"></div>
              <details><summary>판단 규칙과 예시 살펴보기</summary>
                <ul class="s-rules">
                  <li>절대 기준: 점수형 문항당 응답 시간이 <b>${format(config.absolute_seconds)}초 미만</b>이면 빠른 응답 신호입니다.</li>
                  <li>상대 기준: 같은 설문의 시간 표본이 <b>${format(config.min_cohort)}건 이상</b>이고, 응답 시간이 하위 <b>${percent(config.relative_percentile)}</b> 이내이면서 중앙값의 <b>${percent(config.relative_fraction)} 미만</b>이면 빠른 응답 신호입니다.</li>
                  <li>점수형 문항 <b>${format(config.min_questions)}개 이상</b>에서 모든 점수가 같으면 동일 점수 반복 신호입니다.</li>
                  <li>빠른 응답 −${format(config.fast_penalty)}점, 반복 −${format(config.straight_penalty)}점, 동시 발생 시 추가 −${format(config.interaction_penalty)}점. 품질 <b>${format(config.suspicious_below)}점 미만</b>만 기본 제외 대상입니다.</li>
                </ul>
                <div class="s-example"><span class="s-tag">규칙 설명용 예시 · 실제 집계와 별개</span>
                  <p class="note">${escape(D.quality?.examples_note)}</p>
                  <div class="s-table-scroll" tabindex="0" role="region" aria-label="품질 판단 예시 표"><table>
                    <thead><tr><th scope="col">사례</th><th scope="col">가정한 응답</th><th scope="col">품질 점수</th><th scope="col">기본 처리</th></tr></thead>
                    <tbody>${array(D.quality?.examples).map(e => `<tr><th scope="row">${escape(e.id)}</th><td>${escape(e.description)}</td><td>${format(e.quality_score)}점</td><td>${e.is_suspicious ? '의심으로 분류' : '제외하지 않음'}</td></tr>`).join('')}</tbody>
                  </table></div>
                </div>
              </details>
            </section>

            <section class="card" aria-labelledby="s-sensitivity-title">
              <div class="sec-h"><h2 id="s-sensitivity-title">기준을 바꾸면 결과도 달라질까?</h2><span class="s-tag">선택한 프로그램 · 사전 계산 실험</span></div>
              <p class="note">저장된 민감도 분석에서 조건에 맞는 결과를 선택합니다. SQL을 새로 실행하지 않으며 위의 기본 지표와 통합 분석은 바뀌지 않습니다.</p>
              <div class="s-experiment-controls">
                <label>문항당 응답 시간 기준<select data-s="seconds"></select></label>
                <label>빠른 응답 판단 방식<select data-s="mode"></select></label>
              </div>
              <div data-s="experiment" aria-live="polite" aria-atomic="true"></div>
              <details><summary>판단 방식의 차이와 저장된 모든 설정</summary>
                <p class="note">absolute: 절대 시간 기준만 · relative: 같은 설문 안의 상대 기준만 · either: 둘 중 하나 충족 · both: 두 기준 모두 충족. relative와 both에서는 표본이 부족하면 품질 판단을 보류합니다. 판단 보류 응답을 의심으로 단정하지 않습니다.</p>
                <div data-s="sensitivity-table"></div>
              </details>
            </section>

            <section class="card" aria-labelledby="s-behavior-title">
              <div class="sec-h"><h2 id="s-behavior-title">만족도가 높으면 실제로 다시 참여할까?</h2>${scope}</div>
              <p class="note">프로그램 선택과 무관한 통합 결과입니다. 집단은 서로 겹치므로 응답 수를 합산하지 않습니다.</p>
              <div class="s-two" data-s="behavior-charts"></div>
              <div class="alert warn"><p data-s="behavior-insight"></p></div>
              <details><summary>재참여 정의·관찰 분모와 만족도 구간별 결과</summary>
                <p>${escape(meta.followup_definition)}</p>
                <p class="note">90일의 관찰 기간과 후속 참여 기회가 확인된 응답만 재참여율 분모에 포함합니다. 유효 응답 ${format(meta.valid_responses)}건 중 관찰 완료는 ${format(meta.observable)}건입니다. 기록 범위 불명·관찰 기간 부족·후속 기회 없음은 미참여로 계산하지 않습니다. 집계 단위는 응답이며 고유 학생 수가 아닙니다.</p>
                <div data-s="behavior-table"></div>
                <label>만족도 구간 집계 기준<select data-s="policy"></select></label>
                <div data-s="band-results" aria-live="polite"></div>
              </details>
            </section>

            <section class="card" aria-labelledby="s-model-title">
              <div class="sec-h"><h2 id="s-model-title">재참여 예측 모델은 무엇을 배웠을까?</h2>${scope}</div>
              <p class="note">저장된 모델 평가 결과 · ${escape(model.asof || '기준일 기록 없음')} · 동일 평가 데이터에서 비교</p>
              <div data-s="model-performance"></div>
              <details><summary>시간 분리와 학생 분리 조건</summary>
                <p class="note">${escape(meta.model_method?.split)}</p>
                <p class="note">분리 시점: ${escape(model.cutoff || '자료 없음')}<br>학습 결과 확정 최종 시각: ${escape(model.latest_training_label_time || '자료 없음')}<br>평가 설문 최초 시각: ${escape(model.earliest_test_time || '자료 없음')}</p>
                <p class="note">학습 재참여 비율 ${percent(model.train_positive_rate)} · 평가 재참여 비율 ${percent(model.test_positive_rate)}. 기준 모델은 학습의 다수 클래스를 항상 예측합니다.</p>
              </details>
            </section>

            <section class="card" aria-labelledby="s-importance-title">
              <div class="sec-h"><h2 id="s-importance-title">어떤 문항분류가 예측과 연결될까?</h2><span class="s-tag">${escape(meta.model_method?.importance_model || '모델 기록 없음')}</span></div>
              <div data-s="importance"></div>
              <p class="note">표준화 계수의 절댓값이 클수록 모델의 예측 연관성이 큽니다. 인과효과나 개선 우선순위를 증명하지 않습니다. 의심 응답 제외 학습 모델의 계수가 아닙니다.</p>
              <details><summary>문항분류 점수가 0.5점 바뀌는 시나리오</summary>
                <p class="note">${escape(meta.model_method?.scenario)} 브라우저에서는 모델을 새로 실행하지 않습니다.</p>
                <div data-s="scenario"></div>
              </details>
            </section>

            <section class="card" aria-labelledby="s-limits-title">
              <div class="sec-h"><h2 id="s-limits-title">해석과 데이터 출처</h2></div>
              <ul class="s-limitations">
                <li>응답 품질은 검토 신호입니다. 반복 점수만으로 불성실을 확정하거나 무조건 제외하지 않습니다. 보정 평균도 실제 만족도의 정답은 아닙니다.</li>
                <li>응답 시간은 페이지를 열어 둔 시간일 수 있습니다. 기준 변경에 따른 평균의 상승·하락만으로 분석의 우수성을 판단할 수 없습니다.</li>
                <li>만족도·재참여율·계수는 합성 데이터 생성 가정과 반복 응답의 영향을 받습니다. 실제 학생이나 운영 개선의 인과효과로 일반화할 수 없습니다.</li>
                <li>${escape(model.limitation || '모델 평가 한계가 기록되어 있지 않습니다.')}</li>
              </ul>
              <details><summary>원본 파일·집계 방식·분석 시점 확인</summary>
                <p class="note">DB/분석 기준일 ${escape(meta.analysis_asof || '자료 없음')} · 모델 평가 기준일 ${escape(model.asof || '자료 없음')}. ${escape(meta.analysis_timestamp_note)}</p>
                <p class="note">${escape(meta.aggregation_note)}</p><p class="note">${escape(meta.quality_weight_note)}</p>
                <p class="note">${escape(meta.interpretation_note)}</p>
                <p class="note">${escape(meta.program_year_note)} 학생 이름·학번 등 개인식별정보는 포함하지 않습니다.</p>
                <p class="note">참조 브랜치 ${escape(meta.source_branch)} · 커밋 ${escape(meta.source_commit)}<br>정적 JSON 변환 시각 ${escape(meta.exported_at || '기록 없음')}</p>
                <ul class="s-source-list">${array(meta.sources).map(source => `<li><a href="https://github.com/WS1101/sql-swknudb-project/blob/${encodeURIComponent(source.git_ref)}/${String(source.path).split('/').map(encodeURIComponent).join('/')}">${escape(source.path)}</a></li>`).join('')}</ul>
                <p class="note">수치는 원본 CSV/JSON 정밀도로 저장하고 화면에서 반올림합니다. 만족도는 1~5점 척도이며 비교 막대는 0~5점 축입니다. 모델 시나리오는 확률 차이에 100을 곱한 %p 단위입니다.</p>
              </details>
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
          el('program-head').innerHTML = '<h1>프로그램 집계가 없습니다</h1><p class="note">통합 분석은 제공된 데이터 범위에서 표시합니다.</p>';
          el('kpis').innerHTML = '';
          el('comparison').innerHTML = '<p class="s-empty">만족도를 비교할 프로그램이 없습니다.</p>';
        } else {
          el('program-head').innerHTML = `<p class="s-eyebrow">프로그램별 만족도 진단 · 기본 기준</p><h1>${escape(p.program_name)}</h1>
            <div class="meta"><span>${escape(p.year ?? '연도 없음')}</span><span>유효 설문 ${format(p.response_count)}건</span><span>의심 ${format(p.suspicious_count)}건 · 판단 보류 ${format(p.unknown_count)}건</span></div>
            <p class="note">${escape(baseRule)}</p>`;
          el('kpis').innerHTML = metric('원본 만족도 평균', format(p.original_mean, 3), valid(p.original_mean) ? '/ 5점' : '', '전체 유효 응답의 점수형 문항 평균')
            + metric('의심 응답 제외 만족도', format(p.filtered_mean, 3), valid(p.filtered_mean) ? '/ 5점' : '', `원본 대비 ${change(p.mean_change)}`, true)
            + metric('품질 가중 만족도', format(p.weighted_mean, 3), valid(p.weighted_mean) ? '/ 5점' : '', '품질 점수 / 100을 가중치로 사용')
            + metric('품질 의심 응답 비율', valid(p.suspicious_ratio) ? format(p.suspicious_ratio * 100, 2) : '자료 없음', valid(p.suspicious_ratio) ? '%' : '', `${format(p.suspicious_count)} / ${format(p.response_count)}건 · 불성실 확정 아님`);
          el('comparison').innerHTML = `<div class="sec-h"><h2>원본과 보정 평균, 차이는 얼마나 될까?</h2><span class="s-tag">선택한 프로그램</span></div>
            ${bars([{label: '원본 만족도', value: p.original_mean, muted: true}, {label: '의심 응답 제외', value: p.filtered_mean}], {max: 5, ticks: [0, 1, 2, 3, 4, 5], unit: '점', digits: 3, caption: '평균 만족도 · 공통 축 0~5점'})}
            <div class="s-delta"><span>제외 평균 − 원본 평균</span><b title="${escape(p.mean_change)}">${change(p.mean_change)}</b></div>
            <p class="note">두 막대는 같은 전체 축으로 비교합니다. 평균이 내려가거나 올라갔다는 사실만으로 보정의 타당성이 증명되지는 않습니다.</p>`;
        }
        updateExperimentControls(); drawExperiment();
      }

      function updateExperimentControls() {
        const rows = sensitivity.filter(r => r.program_id === state.programId);
        const seconds = [...new Set(rows.map(r => r.absolute_seconds).filter(valid))].sort((a, b) => a - b);
        if (!seconds.includes(state.seconds)) state.seconds = seconds[0] ?? null;
        el('seconds').innerHTML = seconds.map(s => `<option value="${s}">${format(s)}초 미만</option>`).join('') || '<option value="">저장된 시간 기준 없음</option>';
        if (state.seconds != null) el('seconds').value = String(state.seconds);
        el('seconds').disabled = !seconds.length;
        const modes = [...new Set(rows.map(r => r.speed_mode).filter(Boolean))];
        if (!modes.includes(state.mode)) state.mode = modes[0] ?? null;
        el('mode').innerHTML = modes.map(m => `<option value="${escape(m)}" ${rows.some(r => r.absolute_seconds === state.seconds && r.speed_mode === m) ? '' : 'disabled'}>${escape(m)} · ${escape(modeNames[m] || m)}</option>`).join('') || '<option value="">저장된 판단 방식 없음</option>';
        if (state.mode != null) el('mode').value = state.mode;
        el('mode').disabled = !modes.length;
      }

      function drawExperiment() {
        const p = selected(), rows = sensitivity.filter(r => r.program_id === state.programId);
        const row = rows.find(r => r.absolute_seconds === state.seconds && r.speed_mode === state.mode);
        if (!p || !row) {
          el('experiment').innerHTML = '<p class="s-empty">이 프로그램과 설정에 해당하는 사전 계산 결과가 없습니다.</p>';
        } else {
          const isBase = state.seconds === config.absolute_seconds && state.mode === config.speed_mode;
          const stat = (label, text) => `<div class="s-stat"><span>${label}</span><b class="num">${escape(text)}</b></div>`;
          el('experiment').innerHTML = `<p class="s-experiment-title">${escape(p.program_name)} · ${format(row.absolute_seconds)}초 / ${escape(row.speed_mode)} ${isBase ? '(기본 설정)' : ''}</p>
            <div class="s-experiment-results">${stat('품질 의심 응답', valueText(row.suspicious_count, '건', 0))}${stat('의심 응답 비율', percent(row.suspicious_ratio))}${stat('의심 제외 평균', score(row.filtered_mean))}${stat('원본 대비 변화', change(row.mean_change))}</div>
            <p class="note">유효 응답 ${format(row.response_count)}건 · 판단 보류 ${format(row.unknown_count)}건 · 원본 ${score(row.original_mean)} · 품질 가중 ${score(row.weighted_mean)}. 기본 설정과 실험 설정의 판단 결과는 다를 수 있습니다.</p>`;
        }
        el('sensitivity-table').innerHTML = rows.length ? `<div class="s-table-scroll" tabindex="0" role="region" aria-label="선택한 프로그램의 민감도 결과 표"><table><caption>${escape(p?.program_name)} · 저장된 설정별 결과</caption>
          <thead><tr><th scope="col">기준</th><th scope="col">방식</th><th scope="col">의심 수</th><th scope="col">보류 수</th><th scope="col">제외 평균</th><th scope="col">변화</th></tr></thead>
          <tbody>${rows.map(r => `<tr><td>${format(r.absolute_seconds)}초</td><td>${escape(r.speed_mode)}</td><td class="s-numeric">${format(r.suspicious_count)}</td><td class="s-numeric">${format(r.unknown_count)}</td><td class="s-numeric">${score(r.filtered_mean)}</td><td class="s-numeric">${change(r.mean_change)}</td></tr>`).join('')}</tbody></table></div>` : '<p class="note">저장된 민감도 결과가 없습니다.</p>';
      }

      function drawQuality() {
        const repeat = types.find(t => t.id === 'straight_only');
        el('quality').innerHTML = bars(types.map(t => ({label: typeNames[t.id] || t.source_label, value: t.response_count,
          note: `${format(t.quality_score)}점 · ${t.is_suspicious ? '기본 제외 대상' : '기본 제외 안 함'}`, warning: t.is_suspicious})),
          {max: D.quality?.response_count, ticks: valid(D.quality?.response_count) ? [0, D.quality.response_count / 2, D.quality.response_count] : [], unit: '건', digits: 0, caption: `응답 유형별 건수 · 전체 ${format(D.quality?.response_count)}건 기준`})
          + (repeat ? `<div class="alert warn"><p><b>동일 점수 반복만 탐지된 ${format(repeat.response_count)}건은 기본 제외 대상이 아닙니다.</b> 충분히 읽고 모든 문항을 높게 평가했을 가능성도 있습니다. 정상 범위 역시 성실성을 확정하는 분류는 아닙니다.</p></div>` : '');
      }

      function drawBehavior() {
        const wanted = ['전체', '빠른 응답', '의심 응답 제외', '만족도 4점 이상', '만족도 3점 미만'];
        const rows = wanted.map(name => groups.find(g => g.group === name)).filter(Boolean);
        el('behavior-charts').innerHTML = bars(rows.map(g => ({label: g.group, value: g.mean_satisfaction, note: `유효 ${format(g.response_count)}건`, warning: g.group === '빠른 응답'})),
          {max: 5, ticks: [0, 1, 2, 3, 4, 5], unit: '점', digits: 3, caption: '집단별 평균 만족도 · 0~5점'})
          + bars(rows.map(g => ({label: g.group, value: valid(g.reparticipation_rate) ? g.reparticipation_rate * 100 : null, note: `관찰 완료 ${format(g.observable_count)}건`, warning: g.group === '빠른 응답'})),
            {max: 100, ticks: [0, 25, 50, 75, 100], unit: '%', digits: 2, caption: '관찰 완료 응답의 재참여율 · 0~100%'});
        const all = groups.find(g => g.group === '전체'), fast = groups.find(g => g.group === '빠른 응답');
        el('behavior-insight').textContent = all && fast
          ? `빠른 응답 집단은 만족도 ${score(fast.mean_satisfaction)}로 전체 ${score(all.mean_satisfaction)}보다 높지만, 관찰 완료 재참여율은 ${percent(fast.reparticipation_rate)}로 전체 ${percent(all.reparticipation_rate)}보다 낮았습니다. 설문 평균과 실제 참여 행동을 함께 확인할 필요가 있습니다.`
          : '전체와 빠른 응답 집단을 비교할 데이터가 충분하지 않습니다.';
        el('behavior-table').innerHTML = `<div class="s-table-scroll" tabindex="0" role="region" aria-label="전체 집단별 관찰 분모 표"><table><caption>집단별 분모 · 집단 간 중복 가능</caption>
          <thead><tr><th scope="col">집단</th><th scope="col">유효 응답</th><th scope="col">관찰 완료</th><th scope="col">재참여율</th></tr></thead><tbody>${groups.map(g => `<tr><th scope="row">${escape(g.group)}</th><td class="s-numeric">${format(g.response_count)}건</td><td class="s-numeric">${format(g.observable_count)}건</td><td class="s-numeric">${percent(g.reparticipation_rate)}</td></tr>`).join('')}</tbody></table></div>`;
        el('policy').innerHTML = policies.map(p => `<option>${escape(p)}</option>`).join('') || '<option>집계 없음</option>';
        el('policy').disabled = !policies.length;
        if (state.policy) el('policy').value = state.policy;
        drawBands();
      }

      function drawBands() {
        const rows = array(D.satisfactionBehavior).filter(r => r.policy === state.policy);
        el('band-results').innerHTML = rows.length ? `<div class="s-table-scroll" tabindex="0" role="region" aria-label="만족도 구간별 재참여 표"><table><caption>${escape(state.policy)} · 전체 프로그램의 만족도 구간별 재참여</caption>
          <thead><tr><th scope="col">만족도 구간</th><th scope="col">유효 응답</th><th scope="col">관찰 완료</th><th scope="col">재참여율</th></tr></thead><tbody>${rows.map(r => `<tr><th scope="row">${escape(r.band)}</th><td class="s-numeric">${format(r.response_count)}건</td><td class="s-numeric">${format(r.observable_count)}건</td><td class="s-numeric">${percent(r.reparticipation_rate)}</td></tr>`).join('')}</tbody></table></div>` : '<p class="note">만족도 구간별 데이터가 없습니다.</p>';
      }

      function drawModel() {
        el('model-performance').innerHTML = metrics.length ? `<div class="s-training"><span>학습 <b class="num">${format(model.train_n)}</b>건</span><span>평가 <b class="num">${format(model.test_n)}</b>건</span><span>학습·평가 학생 중복 <b class="num">${format(model.student_overlap)}</b>명</span></div>
          ${bars(metrics.map((m, i) => ({label: m.model, value: m.roc_auc, muted: i === 0})), {max: 1, ticks: [0, 0.25, 0.5, 0.75, 1], digits: 4, caption: '모델별 ROC-AUC · 공통 축 0~1 (클수록 분류 순위 성능이 높음)'})}
          <div class="s-table-scroll" tabindex="0" role="region" aria-label="모델 성능 비교 표"><table class="s-model-table"><caption>모델별 학습 수와 동일 평가 세트 성능</caption>
            <thead><tr><th scope="col">모델</th><th scope="col">학습</th><th scope="col">평가</th><th scope="col">ROC-AUC</th><th scope="col">Accuracy</th><th scope="col">F1-score</th></tr></thead>
            <tbody>${metrics.map(m => `<tr><th scope="row">${escape(m.model)}</th><td class="s-numeric">${format(m.train_n)}</td><td class="s-numeric">${format(m.test_n)}</td><td class="s-numeric">${format(m.roc_auc, 4)}</td><td class="s-numeric">${format(m.accuracy, 4)}</td><td class="s-numeric">${format(m.f1, 4)}</td></tr>`).join('')}</tbody>
          </table></div><p class="note">Accuracy는 맞힌 비율, F1은 정밀도와 재현율의 조화평균입니다. 모두 0~1 단위입니다. ${escape(meta.model_method?.evaluation)} 작은 성능 차이만으로 의심 응답 제외 학습의 우월성을 확정할 수 없습니다.</p>`
          : `<p class="s-empty">${escape(model.reason || '저장된 모델 평가 결과가 없습니다.')}</p>`;
        const rows = [...importance].sort((a, b) => (b.absolute_coefficient ?? -1) - (a.absolute_coefficient ?? -1));
        const values = rows.map(r => r.absolute_coefficient).filter(valid);
        const max = values.length ? Math.max(0.1, Math.ceil(Math.max(...values) * 10) / 10) : 0;
        el('importance').innerHTML = bars(rows.map(r => ({label: r.category_name, value: r.absolute_coefficient, note: `표준화 계수 ${signed(r.standardized_coefficient)}`})),
          {max, ticks: [0, max / 2, max], digits: 4, caption: '문항분류 중요도 · 표준화 계수 절댓값 (단위 없음)'});
        el('scenario').innerHTML = rows.length ? `<div class="s-table-scroll" tabindex="0" role="region" aria-label="0.5점 변화 예측 시나리오 표"><table class="s-scenario-table"><caption>일반 Logistic Regression · 평균 예측 확률 변화 (%p)</caption>
          <thead><tr><th scope="col">문항분류</th><th scope="col">점수 −0.5점</th><th scope="col">점수 +0.5점</th></tr></thead><tbody>${rows.map(r => `<tr><th scope="row">${escape(r.category_name)}</th><td class="s-numeric">${valid(r['delta_minus_0.5']) ? `${signed(r['delta_minus_0.5'] * 100, 2)} %p` : '자료 없음'}</td><td class="s-numeric">${valid(r['delta_plus_0.5']) ? `${signed(r['delta_plus_0.5'] * 100, 2)} %p` : '자료 없음'}</td></tr>`).join('')}</tbody></table></div><p class="note">각 행은 한 분류만 바꾼 개별 시나리오입니다. 행을 합산하거나 실제 재참여율의 변화로 해석하지 않습니다.</p>` : '<p class="note">저장된 시나리오 결과가 없습니다.</p>';
      }

      el('search').value = state.search;
      el('sort').value = state.sort;
      el('search').oninput = () => { state.search = el('search').value; drawList(); persist(); };
      el('sort').onchange = () => { state.sort = el('sort').value; drawList(); persist(); };
      el('seconds').onchange = () => { state.seconds = Number(el('seconds').value); updateExperimentControls(); drawExperiment(); persist(); };
      el('mode').onchange = () => { state.mode = el('mode').value; drawExperiment(); persist(); };
      el('policy').onchange = () => { state.policy = el('policy').value; drawBands(); persist(); };
      drawList(); drawProgram(); drawQuality(); drawBehavior(); drawModel(); persist();
    }
  });
})();
