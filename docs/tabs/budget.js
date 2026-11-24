// PBL3 3번 탭: 교육별 점수 변화와 예산 효율 (발표용 가상 데이터)
// 데이터는 이 파일 안에만 생성하며 기존 DB, JSON, 다른 탭은 변경하지 않는다.
(() => {
  const style = "\n:host{--bg:#0d1117;--pane:#171c24;--pane2:#1b2330;--line:#303846;--fg:#f4f6fb;--muted:#a2b2c8;--blue:#81b4ff;--blue2:#477ce3;--mint:#56d1b2;--warn:#ffc17a}\n*{box-sizing:border-box}:host{font-family:Pretendard,'Noto Sans KR','Malgun Gothic',sans-serif;background:var(--bg);color:var(--fg)}body{margin:0}button,select{font:inherit}button{cursor:pointer}.topline{height:29px;background:#0a0e13;border-bottom:1px solid #28303b;color:#b7c5d6;font-size:11px;display:flex;gap:13px;justify-content:flex-end;align-items:center;padding:0 32px}.topnav{height:75px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid var(--line);padding:0 45px;background:#171c24}.logo small{display:block;color:#b7c5dc;font-size:12px;font-weight:700}.logo strong{display:block;font-size:20px;letter-spacing:-.6px}.navs{display:flex;gap:34px;align-items:center;color:#94a7c2;font-size:15px;font-weight:700}.navs span.active{color:var(--blue);border-bottom:2px solid var(--blue);padding:26px 0}.wrap{max-width:1500px;margin:0 auto;padding:32px 42px 90px}.headline{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;margin-bottom:21px}.headline h1{margin:2px 0 7px;font-size:29px;letter-spacing:-1px}.headline p{margin:0;color:#b3c2d5;font-size:14px}.tag{background:#21334d;color:#9fc4ff;border:1px solid #37527a;border-radius:8px;padding:7px 10px;font-size:12px;white-space:nowrap}.layout{display:grid;grid-template-columns:305px minmax(0,1fr);gap:22px}.pane{background:var(--pane);border:1px solid var(--line);border-radius:22px}.sidebar{padding:22px 15px}.sidebar h3{font-size:17px;margin:0 10px 8px}.sidebar .sub{border-top:1px solid #657080;padding-top:11px;margin:0 10px 15px;color:var(--muted);font-size:12px;line-height:1.6}.program{border:1px solid transparent;background:transparent;border-bottom-color:#2a313e;border-radius:8px;width:100%;text-align:left;color:var(--fg);padding:15px 12px;display:flex;flex-direction:column;gap:5px;transition:background .2s}.program b{font-size:14px}.program small{font-size:11px;color:#91abc9}.program em{font-size:11px;color:#8fe4cf;font-style:normal}.program.sel{background:#213047;border-color:#3d5780}.program.negative em{color:#ffa8a1}.noteleft{padding:15px 13px;color:#92a1b6;font-size:12px;line-height:1.75}.bodycol{display:flex;flex-direction:column;gap:17px}.programinfo{padding:20px 22px;display:flex;align-items:center;justify-content:space-between;gap:15px}.programinfo strong{display:block;font-size:21px;margin-bottom:7px;letter-spacing:-.4px}.programinfo p{margin:0;color:#b4c4d9;font-size:12px}.status{font-size:12px;padding:7px 10px;border:1px solid #37634f;border-radius:50px;color:#8be2bb;background:#173628;white-space:nowrap}.kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px}.kpi{padding:17px 18px;min-height:108px}.kpi .lbl{color:#a4b5cc;font-size:12px;font-weight:700}.kpi .val{font-size:27px;letter-spacing:-1.2px;margin:9px 0 5px;font-weight:800}.kpi .note{font-size:11px;color:#94a7c2}.pos{color:#9dd9a1}.accent{color:#89b7ff}.split{display:grid;grid-template-columns:minmax(0,1.45fr) minmax(320px,1fr);gap:16px}.section{padding:22px 22px 19px}.section h2{font-size:19px;margin:0 0 6px}.section .desc{font-size:12px;color:var(--muted);margin:0 0 18px;line-height:1.65}.chartwrap{height:230px;position:relative}.chartwrap svg{width:100%;height:100%;display:block}.legend{display:flex;gap:18px;color:#abbad0;font-size:12px;align-items:center;margin-top:7px}.legend span:before{content:'';display:inline-block;width:19px;height:3px;background:var(--blue);vertical-align:middle;margin-right:6px;border-radius:2px}.legend span.student:before{background:var(--mint)}.personselect{width:100%;padding:11px 13px;margin:8px 0 16px;border-radius:10px;border:1px solid #3d4a5c;background:#131923;color:#e2ebf7}.studentcard{display:grid;grid-template-columns:repeat(3,1fr);gap:7px}.studentcard .box{background:#111821;border:1px solid #303b4b;border-radius:10px;padding:11px 6px;text-align:center}.studentcard .box small{color:#a0b1c8;font-size:11px}.studentcard .box strong{display:block;font-size:23px;padding-top:4px}.studentgain{border:1px solid #2d5748;background:#172b25;color:#b2edcf;border-radius:12px;margin-top:14px;padding:13px;text-align:center;font-size:13px;line-height:1.5}.studentgain b{font-size:18px}.bottom{display:grid;grid-template-columns:1fr 1fr;gap:16px}.costrow{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid #2f3744;font-size:13px}.costrow:last-child{border-bottom:0}.costrow em{font-style:normal;color:#d9e6f7;font-weight:700}.medalt{background:#17263d;border:1px solid #2e4f7a;border-radius:12px;padding:12px 14px;margin-top:14px;font-size:12px;line-height:1.6;color:#c3d8f7}.compitem{margin:13px 0}.compitem .head{display:flex;justify-content:space-between;font-size:12px;gap:10px;color:#c6d4e8}.barouter{background:#283241;border-radius:6px;height:12px;overflow:hidden;margin-top:8px}.barinner{height:100%;background:linear-gradient(90deg,#3c78e5,#80b0f4);border-radius:6px}.barouter.diverge{position:relative;overflow:hidden;height:16px;background:linear-gradient(90deg,#3e2529,#293441 50%,#203951)}.diverge .zero-mark{position:absolute;left:50%;top:0;bottom:0;width:2px;background:#c1cbd8;opacity:.75;z-index:2}.diverge .barinner{position:absolute;top:0;height:100%;}.diverge .barinner.pos{left:50%;background:linear-gradient(90deg,#2a87c4,#81beff);border-radius:0 5px 5px 0}.diverge .barinner.neg{right:50%;background:linear-gradient(270deg,#b94d50,#ec9386);border-radius:5px 0 0 5px}.footnote{border:1px dashed #4d5969;background:#131923;padding:15px 18px;border-radius:12px;color:#b4c2d4;font-size:12px;line-height:1.7}.stamp{color:#8da6c7;font-size:12px;margin-bottom:10px}.pill{border-radius:50px;background:#223b34;color:#86deb7;padding:4px 7px;font-size:11px}.disclaimer{font-size:12px;color:#a5b3c5;line-height:1.7;margin:10px 0 0}.full{display:block}.flexline{display:flex;gap:12px;justify-content:space-between;align-items:center}.mini{font-size:11px;color:#90a8c8}.spark{text-align:center}.simple{color:#a8b4c9;font-size:12px}.hide{display:none!important}@media(max-width:1080px){.layout{grid-template-columns:235px minmax(0,1fr)}.split,.bottom{grid-template-columns:1fr}.kpis{grid-template-columns:repeat(2,1fr)}.topnav{padding:0 20px}.navs{gap:10px;font-size:12px}}@media(max-width:690px){.wrap{padding:20px 12px 60px}.layout{grid-template-columns:1fr}.sidebar{display:flex;flex-wrap:wrap;gap:8px}.sidebar h3,.sidebar .sub,.sidebar .noteleft{width:100%}.program{width:calc(50% - 5px)}.programinfo{flex-wrap:wrap}.topnav{height:auto;min-height:70px;flex-wrap:wrap;padding:12px}.navs{margin-top:8px}.navs span.active{padding:8px 0}.kpi .val{font-size:22px}.tag{display:none}.headline h1{font-size:24px}}\n\n/* 시연용 교육 성과 분석 */\n.kpis{grid-template-columns:repeat(5,minmax(0,1fr))}\n.kpi .val{font-size:24px}\n.statstable{margin-top:13px;border:1px solid #303846;border-radius:11px;overflow:hidden;width:100%;border-collapse:separate;border-spacing:0;font-size:12px;color:#d4e0ef}\n.statstable th,.statstable td{padding:9px 12px;border-bottom:1px solid #2a3444;text-align:right}\n.statstable tr:last-child th,.statstable tr:last-child td{border-bottom:none}\n.statstable th:first-child,.statstable td:first-child{text-align:left}\n.statstable th{background:#202938;color:#a9bed9;font-weight:600}\n.statstable td.final{color:#a9dcfb;font-weight:700}\n.statsp{font-size:11px;color:#a1aec2;margin-top:8px;line-height:1.55}\n.outcome{margin:14px 0 4px}\n.outrow{display:flex;height:18px;border-radius:8px;overflow:hidden;background:#202a38}\n.outrow>span{height:100%;display:block}\n.outlabels{display:flex;flex-wrap:wrap;gap:8px 16px;margin-top:10px;font-size:11px;color:#b9c8df}\n.outlabels b{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:4px}\n.decline{color:#ff9c94!important}\n.studentgain.down{background:#351f22;border-color:#764148;color:#ffbbb5}\n.studentgain.flat{background:#262b35;border-color:#515867;color:#c1d0df}\n.verdict{display:flex;align-items:center;gap:10px;justify-content:space-between;border:1px solid #355273;background:#1b2a3f;border-radius:13px;padding:13px 15px;margin-top:15px;font-size:12px;line-height:1.65}\n.verdict strong{font-size:13px}\n.verdict.warn{border-color:#70543b;background:#34291f}\n.verdict.better{border-color:#366d5a;background:#163b2e}\n.verdict.neutral{border-color:#465569;background:#242c37}.verdict.stop{border-color:#8b4247;background:#371f28}.status.review{border-color:#994f53;background:#3e2328;color:#ffb0a8}.cmp-negative{color:#f6aaa2!important}.summarypanel{display:flex;gap:10px;flex-wrap:wrap;padding:12px 14px;border:1px solid #39485c;border-radius:13px;background:#1b2431;margin-bottom:15px;font-size:12px;color:#b9cbe1}.summarypanel strong{color:#e4ecf8}\n.verdict p{margin:4px 0 0;color:#c7d5e7}\n.cmp-value{margin-top:11px;font-size:12px;color:#93a9c6}\n.legend .band:before{width:15px;height:9px;background:#88b9ff44;border:1px solid #88b9ff55}\n@media(max-width:1250px){.kpis{grid-template-columns:repeat(3,minmax(0,1fr))}}\n@media(max-width:860px){.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}}\n@media(max-width:690px){.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.statstable th,.statstable td{padding:7px 5px;font-size:10px}}\n\n:host { display:block; background:#0d1117; color:#f4f6fb; }\n.wrap {max-width:none;padding:0 0 50px;margin:0;}\n";
  const markup = "<div class=\"wrap\"><div class=\"headline\"><div><div class=\"stamp\">03 / 교육 성과 기반 운영 의사결정</div><h1>교육 성과·예산 효율 분석</h1><p>교육별 상승·하락을 비교하고 재운영 검토가 필요한 교육을 구분합니다.</p></div><span class=\"tag\">가상 데이터 · 실제 DB 미연결</span></div><div class=\"layout\">\n<aside class=\"pane sidebar\"><h3>분석할 교육 프로그램 <span style=\"font-size:12px;color:#8497b3\">4개</span></h3><p class=\"sub\">3단계 모의고사 점수가 있고, 동일 학생의 평가 결과를 연결할 수 있는 교육만 표시합니다.</p><div class=\"summarypanel\" id=\"programSummary\">—</div><div id=\"programList\"></div><div class=\"noteleft\">※ 특강·설명회처럼 비교 가능한 모의고사 점수가 없는 프로그램은 분석 대상에서 제외합니다.</div></aside>\n<div class=\"bodycol\">\n<div class=\"pane programinfo\"><div><strong id=\"programTitle\">코딩테스트 실전 교육 · A반</strong><p id=\"programMeta\"></p></div><span class=\"status\" id=\"programStatus\">● 3회 평가 완료</span></div>\n<div class=\"kpis\">\n<div class=\"pane kpi\"><div class=\"lbl\">3회 평가 완료 학생</div><div class=\"val\" id=\"sampleN\">—</div><div class=\"note\">세 번 모두 응시한 학생 기준</div></div>\n<div class=\"pane kpi\"><div class=\"lbl\">전체 평균 점수 변화</div><div class=\"val accent\" id=\"avgGain\">—</div><div class=\"note\">사전 대비 최종 평균</div></div>\n<div class=\"pane kpi\"><div class=\"lbl\">최종 점수 표준편차</div><div class=\"val\" id=\"finalStd\">—</div><div class=\"note\" id=\"stdChange\">사전 대비 점수 분산 변화</div></div>\n<div class=\"pane kpi\"><div class=\"lbl\">점수 상승 / 하락</div><div class=\"val\" id=\"directionCount\">—</div><div class=\"note\" id=\"directionDesc\">동일 점수 학생 별도 집계</div></div>\n<div class=\"pane kpi\"><div class=\"lbl\">10점 이상 향상 1인당 비용</div><div class=\"val\" id=\"costImproved\">—</div><div class=\"note\">가상 승인 지출 ÷ 향상 학생 수</div></div>\n</div>\n<div class=\"split\">\n<section class=\"pane section\"><div class=\"flexline\"><h2>전체 학생 평균과 표준편차</h2><span class=\"pill\">0~100점</span></div><p class=\"desc\">같은 학생의 사전·중간·최종 점수로 평균을 구하고, 음영은 평균 ±1 표준편차를 나타냅니다.</p><div class=\"chartwrap\" id=\"averageChart\"></div><div class=\"legend\"><span>전체 학생 평균</span><span class=\"band\">±1 표준편차</span><span class=\"student\">선택 학생</span></div><div id=\"statsTable\"></div><p class=\"disclaimer\">표준편차가 작으면 점수들이 평균 주변에 모여 있다는 뜻입니다. 평균이 올라도 하락한 학생이 있을 수 있어 인원 분포도 함께 확인합니다.</p></section>\n<section class=\"pane section\"><h2>학생별 학습 성장</h2><p class=\"desc\">가명 학생을 선택해 사전·1차 종료·최종 점수와 변화량을 확인합니다.</p><label class=\"mini\" for=\"studentSelect\">학생 선택</label><select class=\"personselect\" id=\"studentSelect\"></select><div class=\"studentcard\"><div class=\"box\"><small>사전 모의고사</small><strong id=\"preScore\">—</strong></div><div class=\"box\"><small>1차 교육 후</small><strong id=\"midScore\">—</strong></div><div class=\"box\"><small>2차 교육 후</small><strong id=\"postScore\">—</strong></div></div><div class=\"studentgain\" id=\"studentGain\">—</div><div style=\"margin-top:17px\" class=\"mini\">학생별 원점수는 관리자 권한에서만 조회하고, 공개 화면에서는 익명 식별자를 사용합니다.</div></section>\n</div>\n<div class=\"bottom\">\n<section class=\"pane section\"><h2>점수 상승·하락과 예산 효율</h2><p class=\"desc\">상승뿐 아니라 하락한 학생의 점수도 합산해 순성과를 계산합니다.</p><div class=\"costrow\"><span>프로그램 연결 승인 지출</span><em id=\"approvedCost\">—</em></div><div class=\"costrow\"><span>3회 평가 완료 학생 수</span><em id=\"matchedN\">—</em></div><div class=\"costrow\"><span>10점 이상 향상 학생 수</span><em id=\"improvedN\">—</em></div><div class=\"costrow\"><span>최종 점수 상승 / 유지 / 하락</span><em id=\"allChanges\">—</em></div><div class=\"costrow\"><span>전체 순점수 변화 합계</span><em id=\"netPoints\">—</em></div><div class=\"costrow\"><span>평가 완료 학생 1명당 비용</span><em id=\"costMatched\">—</em></div><div class=\"costrow\"><span>향상 학생 1명당 비용</span><em id=\"costImproved2\">—</em></div><div class=\"costrow\"><span>100만 원당 순점수 변화</span><em id=\"efficiencyPoints\">—</em></div><div class=\"outcome\"><div class=\"outrow\" id=\"outcomeBar\"></div><div class=\"outlabels\" id=\"outcomeLabels\"></div></div><div class=\"verdict\" id=\"efficiencyVerdict\">—</div><div class=\"medalt\" id=\"insight\">—</div></section>\n<section class=\"pane section\"><h2>동일 시험 기준 교육과의 비교</h2><p class=\"desc\">동일 평가 기준 교육의 100만 원당 순점수 변화를 비교합니다. 양수는 학습 순향상, 음수는 학습 순하락을 나타냅니다. 같은 시험군 내에서만 비교합니다.</p><div id=\"comparisonBars\"></div><div class=\"medalt\" id=\"compareInsight\">—</div></section>\n</div>\n<div class=\"footnote\"><b style=\"color:#dbe8f7\">시연 데이터 해석 주의</b> — 모든 학생의 점수와 프로그램 비용은 HTML 내부에서 만든 시연용 가상값입니다(DB·JSON·추가 테이블 없음). 비교는 세 번 모두 평가한 동일 학생과 같은 시험 기준 과정만 사용합니다. 표준편차는 모집단 표준편차이며, 100만 원당 순점수 변화는 학생별 (최종−사전) 점수의 합을 가상 승인 지출(백만 원 단위)로 나눈 참고 지표입니다. 평균 점수가 하락한 교육은 재운영 보류 또는 개선·재평가 검토 대상으로 분류할 수 있으나, 점수 하락만으로 폐지를 확정하지 않습니다. 상승·하락의 원인을 교육 자체로 단정할 수 없고, 시험 난이도 차이·학습자 구성·표본 규모·미응시자는 실제 도입 시 별도로 검토해야 합니다.</div>\n</div>\n</div></div>";
  App.register({
    id: 'budget', label: '교육 성과·예산 효율', order: 3, ready: true,
    desc: '모의고사 평균·표준편차·학생별 상승·하락과 교육비를 종합해 성과를 확인합니다.',
    render(root) {
      const doc = root.attachShadow({mode:'open'});
      doc.innerHTML = '<style>' + style + '</style>' + markup;

      // 모든 데이터는 발표용 가상 데이터. PostgreSQL이나 외부 JSON을 사용하지 않는다.
      const programDefs = [
        {id:'a',name:'코딩테스트 실전 교육 · A반',track:'코딩테스트 공통 모의고사',n:40,cost:5100000,prebase:29,prerange:30,gainbase:25,gainrange:15,shift:2},
        {id:'b',name:'코딩테스트 실전 교육 · B반',track:'코딩테스트 공통 모의고사',n:36,cost:4350000,prebase:34,prerange:29,gainbase:15,gainrange:13,shift:5,trend:'decline'},
        {id:'c',name:'파이썬 데이터 분석 교육 · A반',track:'데이터 분석 기초 공통시험',n:32,cost:3600000,prebase:30,prerange:28,gainbase:22,gainrange:14,shift:1},
        {id:'d',name:'파이썬 데이터 분석 교육 · B반',track:'데이터 분석 기초 공통시험',n:28,cost:3100000,prebase:33,prerange:27,gainbase:10,gainrange:12,shift:8,trend:'decline'}
      ];
      const fmtNumber=n=>Math.round(n).toLocaleString('ko-KR');
      const koMoney=n=>Number.isFinite(n)?fmtNumber(n)+'원':'계산 불가';
      const clamp=(x,a=0,b=100)=>Math.min(b,Math.max(a,x));
      const mean=a=>a.reduce((s,x)=>s+x,0)/a.length;
      const std=a=>Math.sqrt(mean(a.map(v=>(v-mean(a))**2)));
      const signed=n=>(n>0?'+':'')+n.toFixed(1);
      for(const p of programDefs){
       p.students=Array.from({length:p.n},(_,j)=>{
         const i=j+1, pre=p.prebase+(i*11+5+p.shift)%p.prerange;
         const group=(i*7+p.shift)%17;
         let delta;
         if(p.trend==='decline'){
           // 가상 시나리오: 일부 학생만 상승하고, 대부분은 교육 종료 후 점수가 하락
           if(group<=2)delta=6+(i*3+p.shift)%10;
           else if(group===3)delta=0;
           else if(group<=10)delta=-(6+(i*3+p.shift)%10);
           else delta=-(11+(i*5+p.shift)%13);
         }else{
           if(group<=2)delta=-(3+(i*3+p.shift)%10);
           else if(group===3)delta=0;
           else if(group<=7)delta=2+(i*5+p.shift)%8;
           else delta=p.gainbase+(i*7+p.shift)%p.gainrange;
         }
         const post=clamp(pre+delta), mid=clamp(pre+Math.round(delta*.52)+((i%5)-2)*2);
         return{id:`학생 ${String(i).padStart(2,'0')}`,pre,mid,post,gain:post-pre};
       });
       p.avgs=['pre','mid','post'].map(k=>mean(p.students.map(s=>s[k])));
       p.stds=['pre','mid','post'].map(k=>std(p.students.map(s=>s[k])));
       p.netPoints=p.students.reduce((s,x)=>s+x.gain,0);
       p.improved=p.students.filter(s=>s.gain>=10).length;
       p.rise=p.students.filter(s=>s.gain>0).length;
       p.flat=p.students.filter(s=>s.gain===0).length;
       p.fall=p.students.filter(s=>s.gain<0).length;
       p.costImproved=p.improved?p.cost/p.improved:null;
       p.efficiencyPoints=p.netPoints/(p.cost/1000000);
      }
      let current=programDefs[0],studentIndex=0;
      function chartHTML(){
       const w=630,h=270,l=51,r=20,t=25,b=45,ys=v=>t+(100-v)*(h-t-b)/100,xs=i=>l+i*(w-l-r)/2;
       const s=current.students[studentIndex],avg=current.avgs,sd=current.stds,ind=[s.pre,s.mid,s.post];
       let a=`<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="전체 평균과 표준편차 및 선택 학생 점수 그래프">`;
       for(let score=0;score<=100;score+=25){const y=ys(score);a+=`<line x1="${l}" y1="${y}" x2="${w-r}" y2="${y}" stroke="#303d51" stroke-dasharray="3 7"/><text x="${l-13}" y="${y+4}" text-anchor="end" font-size="12" fill="#8fa4bf">${score}</text>`;}
       const bandHigh=avg.map((v,i)=>[xs(i),ys(clamp(v+sd[i]))]);
       const bandLow=avg.map((v,i)=>[xs(i),ys(clamp(v-sd[i]))]).reverse();
       a+=`<polygon points="${bandHigh.concat(bandLow).map(p=>p.join(',')).join(' ')}" fill="#7faeff" fill-opacity=".16" stroke="none"/>`;
       const path=vals=>vals.map((v,i)=>`${i?'L':'M'}${xs(i)},${ys(v)}`).join(' ');
       a+=`<path d="${path(avg)}" stroke="#86b9ff" stroke-width="4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`;
       a+=`<path d="${path(ind)}" stroke="#5cd7b8" stroke-width="2.5" stroke-dasharray="6 5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`;
       for(let i=0;i<3;i++){
         a+=`<circle cx="${xs(i)}" cy="${ys(avg[i])}" r="6" fill="#8cbcff" stroke="#142236" stroke-width="3"/><text x="${xs(i)}" y="${ys(avg[i])-15}" font-size="14" font-weight="700" fill="#cae1ff" text-anchor="middle">${avg[i].toFixed(1)}</text><circle cx="${xs(i)}" cy="${ys(ind[i])}" r="4" fill="#56d1b2" stroke="#172b29" stroke-width="2"/>`;
       }
       ['사전 모의고사','1차 교육 후','2차 교육 후'].forEach((v,i)=>a+=`<text x="${xs(i)}" y="${h-13}" font-size="12" text-anchor="middle" fill="#a5b7ce">${v}</text>`);
       return a+'</svg>';
      }
      function verdict(p){
       const avgGain=p.avgs[2]-p.avgs[0];
       if(avgGain<0){
         return{cls:'stop',title:'재운영 보류·개선 검토',details:`가상 모의고사 평균이 ${Math.abs(avgGain).toFixed(1)}점 하락했고, ${p.fall}명이 최종 점수에서 하락했습니다. 현 방식 그대로 재개설하기보다 시험 난이도·수업 내용·학습자 특성을 점검한 뒤 재운영 여부를 판단하는 것이 합리적입니다.`};
       }
       const peers=programDefs.filter(q=>q.track===p.track);
       const better=peers.filter(x=>x.efficiencyPoints>0);
       if(better.length===0)return{cls:'neutral',title:'비교자료 부족',details:'같은 시험 기준의 순향상 교육 데이터가 없어 상대 비교를 보류합니다.'};
       const best=mean(better.map(x=>x.efficiencyPoints));
       if(p.efficiencyPoints>=best*.90)return{cls:'better',title:'운영 유지·확대 검토',details:`최종 평균이 ${avgGain.toFixed(1)}점 상승했습니다. 개선 가능성과 비용을 함께 살펴본 뒤 재운영을 긍정적으로 검토할 수 있습니다.`};
       return{cls:'neutral',title:'비용 구조 개선 검토',details:'평균 점수는 상승했지만 동일 시험군의 학습 향상 대비 비용을 추가로 비교할 필요가 있습니다.'};
      }
      function render(){
       doc.getElementById('programSummary').innerHTML=`<strong>평균 상승 ${programDefs.filter(p=>p.avgs[2]>p.avgs[0]).length}개</strong> · <strong style="color:#ffa8a1">평균 하락 ${programDefs.filter(p=>p.avgs[2]<p.avgs[0]).length}개</strong><span>전체 시연용 가상 평가 데이터</span>`;
       doc.getElementById('programList').innerHTML=programDefs.map(p=>`<button type="button" class="program ${p.id===current.id?'sel':''} ${p.avgs[2]<p.avgs[0]?'negative':''}" data-prog="${p.id}"><b>${p.name}</b><small>3회 평가 완료 ${p.n}명 · ${p.track}</small><em>평균 ${signed(p.avgs[2]-p.avgs[0])}점 · 상승 ${p.rise}명 / 하락 ${p.fall}명 ${p.avgs[2]<p.avgs[0]?'· 재운영 검토':''}</em></button>`).join('');
       doc.querySelectorAll('[data-prog]').forEach(el=>el.onclick=()=>{current=programDefs.find(p=>p.id===el.dataset.prog);studentIndex=0;render();});
       doc.getElementById('programTitle').textContent=current.name;
       doc.getElementById('programMeta').textContent=`평가 기준: ${current.track} · 세 번 모두 평가한 동일 학생 · 100점 만점`;
       const avgGain=current.avgs[2]-current.avgs[0],stdDelta=current.stds[2]-current.stds[0];
       const state=doc.getElementById('programStatus');
       state.className='status'+(avgGain<0?' review':'');
       state.textContent=avgGain<0?'● 평균 하락 · 재운영 검토':'● 평균 상승 · 유지 검토';
       doc.getElementById('sampleN').textContent=current.n+'명';
       const avgEl=doc.getElementById('avgGain');avgEl.textContent=signed(avgGain)+'점';avgEl.classList.toggle('decline',avgGain<0);
       doc.getElementById('finalStd').textContent=current.stds[2].toFixed(1)+'점';
       doc.getElementById('stdChange').textContent=`사전 대비 ${signed(stdDelta)}점 ${stdDelta<0?'(격차 축소)':stdDelta>0?'(격차 확대)':'(변화 없음)'}`;
       doc.getElementById('directionCount').textContent=`${current.rise}명 / ${current.fall}명`;
       doc.getElementById('directionDesc').textContent=`변화 없음 ${current.flat}명 · 10점 이상 향상 ${current.improved}명`;
       doc.getElementById('costImproved').textContent=current.costImproved?Math.round(current.costImproved/10000).toLocaleString('ko-KR')+'만원':'—';
       const sel=doc.getElementById('studentSelect');sel.innerHTML=current.students.map((s,i)=>`<option value="${i}">${s.id} · 사전 ${s.pre}점 → 최종 ${s.post}점 (${s.gain>=0?'+':''}${s.gain})</option>`).join('');sel.value=studentIndex;
       sel.onchange=()=>{studentIndex=Number(sel.value);drawStudent();};
       drawStudent();
       doc.getElementById('statsTable').innerHTML=`<table class="statstable" aria-label="평가별 평균과 표준편차"><thead><tr><th>지표</th><th>사전</th><th>1차 교육 후</th><th>2차 교육 후</th></tr></thead><tbody><tr><td>전체 학생 평균</td>${current.avgs.map((v,i)=>`<td class="${i===2?'final':''}">${v.toFixed(1)}점</td>`).join('')}</tr><tr><td>표준편차 (σ)</td>${current.stds.map((v,i)=>`<td class="${i===2?'final':''}">${v.toFixed(1)}점</td>`).join('')}</tr></tbody></table><p class="statsp">※ 음영은 평균 ± 표준편차이며 학생 점수가 68% 들어간다는 뜻으로 해석하면 안 됩니다(정규분포 여부 미확인).</p>`;
       doc.getElementById('approvedCost').textContent=koMoney(current.cost);
       doc.getElementById('matchedN').textContent=current.n+'명';
       doc.getElementById('improvedN').textContent=current.improved+'명';
       doc.getElementById('allChanges').textContent=`${current.rise}명 / ${current.flat}명 / ${current.fall}명`;
       doc.getElementById('netPoints').textContent=`${current.netPoints>=0?'+':''}${current.netPoints}점`;
       doc.getElementById('costMatched').textContent=koMoney(current.cost/current.n);
       doc.getElementById('costImproved2').textContent=koMoney(current.costImproved);
       doc.getElementById('efficiencyPoints').textContent=`${signed(current.efficiencyPoints)}점 / 100만원`;
       const cols=[['rise','#56d1b2',current.rise,'상승'],['flat','#8d9db5',current.flat,'유지'],['fall','#ef8b86',current.fall,'하락']];
       doc.getElementById('outcomeBar').innerHTML=cols.map(x=>`<span style="width:${(x[2]/current.n*100).toFixed(2)}%;background:${x[1]}" title="${x[3]} ${x[2]}명"></span>`).join('');
       doc.getElementById('outcomeLabels').innerHTML=cols.map(x=>`<span><b style="background:${x[1]}"></b>${x[3]} ${x[2]}명 (${(x[2]/current.n*100).toFixed(0)}%)</span>`).join('');
       const v=verdict(current),ver=doc.getElementById('efficiencyVerdict');ver.className='verdict '+v.cls;ver.innerHTML=`<div><strong>${v.title}</strong><p>${v.details}</p></div>`;
       doc.getElementById('insight').innerHTML=`평균은 <b style="color:${avgGain<0?'#ffaaa4':'#a8d9ff'}">${signed(avgGain)}점</b> 변했고, 최종 점수가 하락한 학생은 <b>${current.fall}명</b>입니다. 상승·하락을 모두 반영한 순점수 변화 합계는 <b>${current.netPoints>=0?'+':''}${current.netPoints}점</b>입니다.${avgGain<0?' 학습 성과가 하락한 가상 사례이므로 같은 방식의 재운영을 보류하고 개선안을 검토할 필요가 있습니다.':''}`;
       const peers=programDefs.filter(p=>p.track===current.track),max=Math.max(1,...peers.map(p=>Math.abs(p.efficiencyPoints)));
       doc.getElementById('comparisonBars').innerHTML=peers.map(p=>`<div class="compitem"><div class="head"><span>${p.name}</span><strong class="${p.efficiencyPoints<0?'cmp-negative':''}">${signed(p.efficiencyPoints)}점</strong></div><div class="barouter diverge"><div class="zero-mark"></div><div class="barinner ${p.efficiencyPoints<0?'neg':'pos'}" style="width:${Math.abs(p.efficiencyPoints)/max*48}%"></div></div><div class="cmp-value">평균 변화 ${signed(p.avgs[2]-p.avgs[0])}점 · 순점수 변화 ${p.netPoints>=0?'+':''}${p.netPoints}점 / 가상 예산 ${koMoney(p.cost)}</div></div>`).join('');
       doc.getElementById('compareInsight').textContent='중앙선(0)을 기준으로 오른쪽 파란색은 순점수 상승, 왼쪽 붉은색은 순점수 하락입니다. 동일한 시험 기준의 가상 교육끼리만 비교합니다. 점수 하락은 재운영 검토 신호이지 폐지를 확정할 근거는 아닙니다.';
      }
      function drawStudent(){
       const s=current.students[studentIndex];
       doc.getElementById('averageChart').innerHTML=chartHTML();
       doc.getElementById('preScore').textContent=s.pre+'점';
       doc.getElementById('midScore').textContent=s.mid+'점';
       doc.getElementById('postScore').textContent=s.post+'점';
       const el=doc.getElementById('studentGain');el.className='studentgain '+(s.gain<0?'down':s.gain===0?'flat':'');
       el.innerHTML=`${s.id}: 사전 대비 최종 <b>${s.gain>=0?'+':''}${s.gain}점</b> ${s.gain<0?'하락':s.gain===0?'유지':s.gain>=10?'향상 · 10점 이상 기준 충족':'소폭 향상'}`;
      }
      render();
      
    }
  });
})();
