"""Launch: python -m streamlit run analysis/app.py"""
from pathlib import Path
import hashlib
import hmac
import secrets
import sys
from dataclasses import asdict, replace
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pandas as pd
import plotly.express as px
import streamlit as st

from analysis.db import DATA_SOURCES, QualityConfig, load_analysis, sensitivity

st.set_page_config(page_title='Survey Insight', page_icon='🔎', layout='wide')
st.markdown('''<style>
.stApp {background:#f5f7fb} [data-testid="stMetric"] {background:white;border:1px solid #dce4ef;
padding:18px;border-radius:12px} h1,h2,h3 {color:#182a43} .block-container {padding-top:2.2rem}
</style>''', unsafe_allow_html=True)
st.caption('SW중심대학사업 · 관리자 분석 프로토타입')
st.title('Survey Insight')
st.write('응답 시간과 점수 패턴을 확인하고, 원본과 의심 응답 제외 만족도를 비교합니다.')

with st.sidebar:
    st.header('분석 기준')
    source_label=st.selectbox('데이터 구분',list(DATA_SOURCES))
    source=DATA_SOURCES[source_label]
    st.caption('팀 공통 데이터는 pbl3 SQL로 만든 합성 데이터입니다. 기존 미션 2 시드도 가상 데이터입니다.')
    seconds=st.slider('절대 기준: 문항당 미만(초)',.1,10.0,2.0,.1)
    mode=st.selectbox('빠른 응답 기준',['either','absolute','relative','both'],
        format_func=lambda x:{'either':'절대 또는 상대','absolute':'절대만','relative':'상대만','both':'절대와 상대 모두'}[x])
    min_questions=st.number_input('패턴 분석 최소 문항 수',2,30,4)
    cutoff=st.slider('이 점수 미만을 의심 응답으로 제외',0,100,70)
    with st.expander('상대 기준 · 감점 조정'):
        fraction=st.slider('중앙 시간 대비 비율 미만',.05,.95,.25,.05)
        percentile=st.slider('하위 시간 백분위 이하',.01,.50,.10,.01)
        cohort=st.number_input('상대 기준 최소 시간 표본',2,200,10)
        fast_penalty=st.slider('빠른 응답 감점',0,100,40)
        straight_penalty=st.slider('동일 점수 감점',0,100,15)
        interaction_penalty=st.slider('동시 발생 추가 감점',0,100,20)
    st.button('DB 새로고침')

config=QualityConfig(seconds,fraction,percentile,cohort,min_questions,mode,
                     fast_penalty,straight_penalty,interaction_penalty,cutoff)
asof=datetime.now(timezone.utc)
try:
    summary,all_responses,categories=load_analysis(config,source,asof)
except Exception:
    required_sql='pbl3/14_pbl3_survey_insight.sql' if source=='pbl3' else '05_survey_insight.sql'
    st.error(f'DB 연결 또는 확장 SQL 조회에 실패했습니다. SURVEY_DATABASE_URL과 {required_sql} 적용 여부를 확인하세요.')
    st.info('실행 방법: README의 Survey Insight 절을 확인하세요. 비밀번호와 접속 문자열은 화면에 출력하지 않습니다.')
    st.stop()

st.info(f'{source_label} · SQL 실시간 집계 · 의심 신호는 불성실함의 증거가 아닙니다. 보정 평균도 정답 평균은 아닙니다.')
if summary.empty:
    st.warning('이 데이터 구분에 프로그램이 없습니다. 팀 공통 데이터의 준비 상태는 pbl3/README.md를 확인하세요.')
    st.stop()
names={row.program_id:f'{row.program_name} (#{row.program_id})' for row in summary.itertuples()}
pid=st.selectbox('프로그램',list(names),format_func=names.get)
row=summary[summary.program_id==pid].iloc[0]
raw=all_responses[all_responses.program_id==pid].copy()
df=raw[raw.is_latest & raw.is_valid].copy()
def fmt(value): return '자료 없음' if pd.isna(value) else f'{value:.2f}'

tabs=st.tabs(['만족도 현황','응답 품질','응답 시간'])
with tabs[0]:
    cols=st.columns(4)
    cols[0].metric('유효 설문 응답',int(row.response_count))
    cols[1].metric('품질 의심 응답',int(row.suspicious_count))
    cols[2].metric('원본 만족도',fmt(row.original_mean))
    cols[3].metric('의심 응답 제외 평균',fmt(row.filtered_mean),
                   None if pd.isna(row.mean_change) else f'{row.mean_change:+.2f}점')
    st.caption('응답 수는 학생·조사별 최신 완료 응답 단위입니다. pbl3의 조사는 회차별이며, 출석·재참여는 확장 화면에서 확인합니다.')
    st.write(f'품질 의심 {int(row.suspicious_count)}건 · 품질 정보 부족 {int(row.unknown_count)}건 · '
             f'의심 비율 {fmt(row.suspicious_ratio*100)}%')
    chart=pd.DataFrame({'집계':['원본','의심 응답 제외'],'만족도':[row.original_mean,row.filtered_mean]})
    fig=px.bar(chart,x='집계',y='만족도',color='집계',color_discrete_sequence=['#2864b4','#00a192'],range_y=[0,5],text_auto='.2f')
    st.plotly_chart(fig,width='stretch')
    with st.expander('보조 분석: 품질 가중 평균과 산식',expanded=False):
        st.metric('품질 가중 만족도',fmt(row.weighted_mean))
        st.write('원본 = 점수 합계 / 점수 개수. 제외 평균은 동일 산식에서 의심 응답만 집계 제외합니다.')
        st.write('가중 평균 = Σ(응답별 점수 합계 × w) / Σ(응답별 문항 수 × w), w = 품질점수 / 100.')
        st.write('정보 부족 응답은 가중치 1로 유지합니다. 이는 품질이 좋다는 추정이 아닌 임의 제외 방지 정책이며, 결과에 영향을 줄 수 있습니다.')
        st.caption('모든 문항 1~5점. 프로그램 간 문항 수가 달라도 기존 집계와 같이 점수형 답변 단위로 집계합니다.')
    st.dataframe(summary.drop(columns=['program_id','attendance_count']),hide_index=True,width='stretch')
    st.download_button('프로그램 집계 CSV',summary.drop(columns=['program_id','attendance_count']).to_csv(index=False).encode('utf-8-sig'),
                       'survey_summary.csv','text/csv')

with tabs[1]:
    st.subheader('점수보다 판단 근거를 먼저 확인하세요')
    st.write(f'품질지표 = max(0, 100 − 빠른 응답×{fast_penalty} − 동일 점수×{straight_penalty} '
             f'− 동시 발생×{interaction_penalty}). 성실할 확률이 아닌 규칙 기반 지표입니다.')
    st.caption('시간/문항이 부족하면 품질 점수는 미산출합니다. 동일 점수는 실제 만족일 수 있으며, 단독 신호는 기본 설정에서 제외하지 않습니다.')
    if not df.empty:
        counts=df.response_type.value_counts().rename_axis('응답 유형').reset_index(name='응답수')
        st.plotly_chart(px.pie(counts,names='응답 유형',values='응답수',hole=.55),width='stretch')
        kind=st.selectbox('근거를 확인할 응답 유형',['전체',*sorted(df.response_type.unique())])
        detail=df if kind=='전체' else df[df.response_type==kind]
        if 'alias_salt' not in st.session_state: st.session_state.alias_salt=secrets.token_bytes(32)
        detail=detail.copy()
        detail['가명']=detail.student_no.map(lambda x: 'S-'+hmac.new(st.session_state.alias_salt,str(x).encode(),hashlib.sha256).hexdigest()[:10])
        st.dataframe(detail[['가명','mean_score','duration_seconds','score_variance','absolute_fast','relative_fast',
            'is_straight','quality_score','is_suspicious','response_type','reasons']],hide_index=True,width='stretch')
    st.write(f'미완료/유효하지 않음 {len(raw[~raw.is_valid])}건 · 이전 완료 응답 {len(raw[raw.is_valid & ~raw.is_latest])}건 (집계 제외)')

with tabs[2]:
    timed=df[df.duration_seconds.notna()].copy()
    st.caption('상대 기준은 최소 표본 수 이상일 때, 하위 백분위와 중앙 시간 대비 비율을 모두 만족해야 합니다. 긴 시간도 성실함을 증명하지 않습니다.')
    if timed.empty:
        st.warning('측정된 시작 시각이 없습니다. 과거 응답 시간을 임의로 생성하지 않습니다.')
    else:
        fig=px.histogram(timed,x='seconds_per_question',color='is_straight',nbins=30,
            labels={'seconds_per_question':'문항당 시간(초)','is_straight':'동일 점수'})
        fig.add_vline(x=seconds,line_dash='dash',line_color='#da663b',annotation_text='절대 기준')
        st.plotly_chart(fig,width='stretch')
        st.plotly_chart(px.scatter(timed,x='duration_seconds',y='mean_score',color='response_type',
            labels={'duration_seconds':'총 응답 시간(초)','mean_score':'응답 평균'}),width='stretch')
        st.dataframe(timed.groupby('survey_id').agg(시간표본=('cohort_count','first'),평균초=('survey_mean_seconds','first'),
            중앙초=('survey_median_seconds','first')),width='stretch')
        st.dataframe(timed.groupby('is_fast').agg(응답수=('mean_score','size'),평균=('mean_score','mean')),width='stretch')
        st.caption('응답별 시간 백분위(0~1)는 응답 품질 표에서 근거와 함께 조회할 수 있습니다. 동률은 같은 백분위를 사용합니다.')
        st.dataframe(timed[['duration_seconds','seconds_per_question','time_percentile','cohort_count']],hide_index=True)


# 설문에만 의존하는 추가 검토는 기본 탭 안에 접어 둔다.
with tabs[0]:
    with st.expander('기준 민감도 · 검토 항목'):
        st.subheader('관찰 결과에 따른 검토 항목')
        if pd.notna(row.mean_change):
            st.write(f'원본 대비 제외 평균 변화는 {row.mean_change:+.3f}점입니다. 방향과 크기를 함께 확인하세요.')
            if abs(row.mean_change)>=.1:
                st.info('평균이 응답 제외 기준에 따라 달라집니다. 기준의 타당성과 설문 작성 환경을 함께 검토할 수 있습니다.')
        if not df.empty and (df.is_fast & df.is_straight).any():
            st.write(f'빠른 응답과 동일 점수 동시 발생 {(df.is_fast & df.is_straight).sum()}건: 문항 길이와 작성 환경을 확인할 근거입니다.')
        if row.unknown_count:
            st.write(f'정보 부족 {int(row.unknown_count)}건: 다음 조사부터 실제 시작 시각 수집을 검토하세요.')
        if pd.isna(row.filtered_mean):
            st.warning('제외 후 유효한 점수가 없습니다. 평균을 0점으로 대체하지 않습니다.')
        st.subheader('학과·학년별 제외율 점검')
        bias=df.groupby(['dept_code','grade']).agg(응답수=('response_id','size'),의심수=('is_suspicious','sum')).reset_index()
        bias['제외율']=bias.의심수/bias.응답수
        st.dataframe(bias[bias.응답수>=5],hide_index=True,width='stretch')
        st.caption('5건 미만 집단은 공개하지 않습니다. 제외율 차이만으로 집단 편향의 원인을 확정할 수 없습니다.')
        if st.button('임계값 민감도 계산'):
            sens=sensitivity(config,source)
            st.dataframe(sens[sens.program_id==pid].drop(columns=['program_id']),hide_index=True,width='stretch')
            penalty_rows=[]
            for penalty in (0,15,30):
                changed=replace(config,straight_penalty=penalty)
                s,_,_=load_analysis(changed,source,asof)
                s=s[s.program_id==pid].copy()
                s['동일점수 감점']=penalty
                penalty_rows.append(s)
            st.write('가중치 산식에 대한 민감도 (동일 점수 감점만 변경)')
            st.dataframe(pd.concat(penalty_rows)[['동일점수 감점','original_mean','filtered_mean','weighted_mean','suspicious_count']],hide_index=True)
        with st.expander('현재 설정 · 한계 · 발전 계획'):
            st.json(asdict(config))
            st.write('기본 임계값과 감점은 시연용 가설입니다. 실제 정답 레이블과 현장 검증이 없습니다. 소표본·관찰 누락·장시간 방치 영향을 받습니다.')
        st.write('다음 단계: 공통 출석 데이터와 관찰 가능한 기간을 확인한 뒤 실제 재참여 결과를 연결합니다.')
