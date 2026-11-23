"""Export aggregate charts/tables from the same SQL used by the dashboard."""
import argparse
from dataclasses import asdict
from datetime import datetime, timezone
import json
import os
from pathlib import Path

import pandas as pd
import plotly.express as px

from analysis.db import QualityConfig, behavior_groups, load_analysis, sensitivity, satisfaction_behavior


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',choices=['existing','synthetic'],default='existing')
    p.add_argument('--asof',default=datetime.now(timezone.utc).date().isoformat())
    p.add_argument('--output',type=Path,default=Path('analysis/reports'))
    p.add_argument('--with-participation',action='store_true',help='06 연결 완료 시에만 재참여 그래프 포함')
    a=p.parse_args()
    at=datetime.fromisoformat(a.asof+'T23:59:59+00:00')
    cfg=QualityConfig()
    summary,responses,_=load_analysis(cfg,a.source,at,include_participation=a.with_participation)
    valid=responses[responses.is_latest & responses.is_valid]
    out=a.output
    out.mkdir(parents=True,exist_ok=True)
    prefix=a.source+'_extended' if a.with_participation else a.source
    export_summary=summary if a.with_participation else summary.drop(columns=['attendance_count'])
    export_summary.to_csv(out/f'{prefix}_summary.csv',index=False,encoding='utf-8-sig')
    groups=behavior_groups(valid)
    if a.with_participation:
        groups.to_csv(out/f'{prefix}_behavior.csv',index=False,encoding='utf-8-sig')
        satisfaction_behavior(valid).to_csv(out/f'{prefix}_satisfaction_behavior.csv',index=False,encoding='utf-8-sig')
    counts=valid.response_type.value_counts().rename_axis('응답 유형').reset_index(name='응답수')
    counts.to_csv(out/f'{prefix}_quality.csv',index=False,encoding='utf-8-sig')
    sens=sensitivity(cfg,a.source)
    sens.to_csv(out/f'{prefix}_sensitivity.csv',index=False,encoding='utf-8-sig')
    plot=summary.melt(id_vars=['program_name'],value_vars=['original_mean','filtered_mean'],var_name='집계',value_name='만족도')
    figures=[px.bar(plot,x='program_name',y='만족도',color='집계',barmode='group',range_y=[0,5],title='원본 / 의심 응답 제외 만족도'),
             px.pie(counts,names='응답 유형',values='응답수',hole=.5,title='응답 품질 유형')]
    if a.with_participation:
        figures.append(px.bar(groups,x='집단',y='재참여율',range_y=[0,1],title='90일 관찰 완료 집단의 재참여율'))
    timed=valid.dropna(subset=['seconds_per_question'])
    if not timed.empty:
        fig=px.histogram(timed,x='seconds_per_question',color='response_type',nbins=40,title='문항당 응답 시간')
        fig.add_vline(x=cfg.absolute_seconds,line_dash='dash')
        figures.append(fig)
    html='<html lang="ko"><meta charset="utf-8"><title>Survey Insight</title><body><h1>Survey Insight</h1>'
    html+=f'<p>데이터: {a.source} | 분석 시점: {a.asof} | 합성 시연 결과는 실제 학생 정확도/인과효과가 아닙니다.</p>'
    for i,fig in enumerate(figures):
        html+=fig.to_html(full_html=False,include_plotlyjs=True if i==0 else False)
    html+='</body></html>'
    (out/f'{prefix}_charts.html').write_text(html,encoding='utf8')
    # Standalone figures for slides and offline review.
    cache=Path(__file__).resolve().parents[1]/'.local'/'matplotlib'
    cache.mkdir(parents=True,exist_ok=True)
    os.environ.setdefault('MPLCONFIGDIR',str(cache))
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib import font_manager
    korean_font=Path('C:/Windows/Fonts/malgun.ttf')
    if korean_font.exists():
        font_manager.fontManager.addfont(str(korean_font))
        plt.rcParams['font.family']='Malgun Gothic'
    plt.rcParams['axes.unicode_minus']=False
    fig,axes=plt.subplots(2,2,figsize=(15,10),layout='constrained')
    fig.suptitle(f'Survey Insight | {a.source} | {a.asof} (UTC)',fontsize=18)
    x=list(range(1,len(summary)+1))
    axes[0,0].bar([v-.2 for v in x],summary.original_mean,width=.4,label='Original',color='#2864b4')
    axes[0,0].bar([v+.2 for v in x],summary.filtered_mean,width=.4,label='Filtered',color='#00a192')
    axes[0,0].set(ylim=(0,5),title='Program satisfaction (score-level mean)',xlabel='Program order',ylabel='Score')
    axes[0,0].legend()
    axes[0,1].barh(counts['응답 유형'],counts['응답수'],color='#2864b4')
    axes[0,1].set(title='Response signals (valid latest responses)',xlabel='Responses')
    if a.with_participation:
        axes[1,0].barh(groups['집단'],groups['재참여율'],color='#00a192')
        axes[1,0].set(xlim=(0,1),title='Reattendance (fully observed only)',xlabel='Rate')
    else:
        axes[1,0].bar(x,summary.mean_change,color='#00a192')
        axes[1,0].axhline(0,color='#182a43',linewidth=.8)
        axes[1,0].set(title='Filtered minus original',xlabel='Program order',ylabel='Score change')
    if timed.empty:
        axes[1,1].text(.5,.5,'No measured start times',ha='center')
        axes[1,1].set_axis_off()
    else:
        axes[1,1].hist(timed.seconds_per_question,bins=40,color='#2864b4')
        axes[1,1].axvline(cfg.absolute_seconds,color='#da663b',linestyle='--',label='Absolute threshold')
        axes[1,1].set(title='Measured response time',xlabel='Seconds per scale question',ylabel='Responses')
        axes[1,1].legend()
    fig.savefig(out/f'{prefix}_overview.png',dpi=160)
    fig.savefig(out/f'{prefix}_overview.svg')
    plt.close(fig)
    metadata={'source':a.source,'asof':a.asof,'include_participation':a.with_participation,'config':asdict(cfg),'valid_responses':len(valid),
        'suspicious_responses':int(valid.is_suspicious.sum()),'unknown_responses':int(valid.quality_score.isna().sum()),
        'observable':int(valid.rejoined.notna().sum()),'charts':f'{prefix}_charts.html'}
    (out/f'{prefix}_metadata.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(metadata,ensure_ascii=False))


if __name__=='__main__': main()
