"""Generate measured PBL3 experiment figures from CSV/JSON (no DB writes).

Run from any directory: python presentation_assets/scripts/generate_performance_charts.py
Requires numpy, pandas, matplotlib, scikit-learn, pillow. All PNGs are 320 dpi;
SVG text is converted to paths for Korean-font portability. Missing participation
models are displayed as missing evidence, never as invented AUC values.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import platform
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MPL_CACHE = ROOT / '.local/matplotlib/performance'
MPL_CACHE.mkdir(parents=True,exist_ok=True)
os.environ.setdefault('MPLCONFIGDIR',str(MPL_CACHE))

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager, ticker
import numpy as np
import pandas as pd
import sklearn
from sklearn.dummy import DummyClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

ASSETS = ROOT / 'presentation_assets'
DATA, FIGURES = ASSETS / 'data', ASSETS / 'figures'
SOURCE = DATA / 'sources/analysis/reports'
GREY, BLUE, GREEN, ORANGE = '#9099A4', '#377EB8', '#16816A', '#DC8C32'
INK = '#202C39'
MODEL_LABELS = ['다수 클래스\n기준 모델', 'Logistic\nRegression', '의심 응답 제외\nLogistic']
METRICS = ['accuracy', 'precision', 'recall', 'f1', 'roc_auc']
SHORT = {'파이썬 기초 특강 2025':'파이썬 기초', 'AI 리터러시 특강 2025':'AI 리터러시',
         '데이터 분석 실습 2025':'데이터 분석', '클라우드 입문 특강 2025':'클라우드 입문',
         '생성형 AI 활용 특강 2025':'생성형 AI 활용'}


def dump(value, path):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')


def style():
    candidates = [Path('C:/Windows/Fonts/malgun.ttf'), Path('/usr/share/fonts/truetype/nanum/NanumGothic.ttf')]
    for path in candidates:
        if path.exists():
            font_manager.fontManager.addfont(str(path))
            family = font_manager.FontProperties(fname=str(path)).get_name()
            break
    else:
        families = {f.name for f in font_manager.fontManager.ttflist}
        family = next((s for s in ['Malgun Gothic', 'NanumGothic', 'Noto Sans CJK KR', 'AppleGothic'] if s in families), None)
        if not family:
            raise RuntimeError('A Korean font is required; install Malgun Gothic/NanumGothic/Noto Sans CJK KR.')
    plt.rcParams.update({'font.family': family, 'font.size': 14, 'axes.titlesize': 19,
        'axes.labelsize': 15, 'xtick.labelsize': 13, 'ytick.labelsize': 13,
        'legend.fontsize': 12, 'axes.unicode_minus': False, 'svg.fonttype': 'path',
        'axes.spines.top': False, 'axes.spines.right': False, 'axes.edgecolor': '#8692A0',
        'text.color': INK, 'axes.labelcolor': INK, 'xtick.color': INK, 'ytick.color': INK,
        'figure.facecolor': 'white', 'axes.facecolor': 'white', 'savefig.facecolor': 'white'})
    return family


def axis(ax, ylabel):
    ax.set_ylabel(ylabel)
    ax.set_axisbelow(True)
    ax.yaxis.grid(True, color='#DFE5EB', linewidth=.7)
    ax.tick_params(length=0, pad=9)


def canvas(title, subtitle, footnote):
    fig, ax = plt.subplots(figsize=(16, 9))
    fig.subplots_adjust(left=.10, right=.97, bottom=.23, top=.78)
    fig.text(.055,.94,title,fontsize=23,weight='bold',ha='left')
    fig.text(.055,.875,subtitle,fontsize=13,ha='left',color='#516274')
    fig.text(.055,.045,footnote,fontsize=11,ha='left',color='#516274',linespacing=1.6)
    return fig, ax


def save(fig, name):
    FIGURES.mkdir(parents=True,exist_ok=True)
    # Do not use bbox_inches='tight': preserve the exact 16:9 slide canvas.
    fig.savefig(FIGURES / f'{name}.png',dpi=320)
    fig.savefig(FIGURES / f'{name}.svg')
    plt.close(fig)


def auc_panel(ax, metrics, compact=False):
    vals=metrics.roc_auc.to_numpy()
    bars=ax.bar(np.arange(3),vals,color=[GREY,BLUE,GREEN],width=.58)
    bars[0].set_hatch('//')
    for bar,v in zip(bars,vals):
        ax.text(bar.get_x()+bar.get_width()/2,v+.025,f'{v:.4f}',ha='center',fontsize=16 if compact else 19,weight='bold')
    ax.axhline(.5,ls='--',lw=1,color='#7D8790',zorder=0)
    ax.set_ylim(0,1)
    ax.set_xticks(range(3),MODEL_LABELS)
    axis(ax,'ROC-AUC (0–1)')
    ax.yaxis.set_major_locator(ticker.MultipleLocator(.2))
    if compact:
        ax.tick_params(axis='x',labelsize=12)


def cost_cohort(budget):
    # All five completed 2025 lecture-series programs, selected by type/year.
    # No selection based on measured costs or observed rank changes.
    return budget[budget.program_type_code.eq('LECTURE') & budget.program_name.str.endswith('2025')].sort_values('program_id').copy()


def cost_panel(ax, cohort, compact=False):
    x=np.arange(len(cohort)); w=.35
    cols=['cost_per_unique_attendee','cost_per_satisfied']
    for offset,col,label,color in zip([-.5,.5],cols,['고유 출석자당 비용','만족 출석자당 비용'],[BLUE,ORANGE]):
        v=cohort[col].to_numpy(dtype=float)
        bars=ax.bar(x+offset*w,v,width=w,color=color,label=label)
        for b,y in zip(bars,v):
            if np.isfinite(y):
                ax.annotate(f'{y:,.0f}',(b.get_x()+b.get_width()/2,y),xytext=(0,6),textcoords='offset points',
                    ha='center',fontsize=9 if compact else 11,rotation=90 if compact else 0)
            else:
                ax.text(b.get_x()+b.get_width()/2,0,'산출 불가',ha='center',va='bottom',fontsize=10,rotation=90)
    ax.set_xticks(x,[SHORT.get(s,s) for s in cohort.program_name],rotation=23 if compact else 0,ha='right' if compact else 'center')
    ax.set_ylim(0,float(cohort[cols].max().max())*(1.32 if compact else 1.2))
    ax.yaxis.set_major_formatter(ticker.StrMethodFormatter('{x:,.0f}'))
    axis(ax,'비용 (원/명)')
    ax.legend(frameon=False,loc='upper left',fontsize=11 if compact else 12)
    if compact:
        ax.tick_params(axis='x',labelsize=12)
        ax.tick_params(axis='y',labelsize=11)


def missing_panel(ax, compact=False):
    ax.set_axis_off()
    ax.text(.5,.72,'구현 또는 결과 파일\n확인 필요',transform=ax.transAxes,ha='center',va='center',
            fontsize=20 if compact else 27,weight='bold',linespacing=1.5)
    ax.text(.5,.43,'mv_candidate 입력 뷰는 존재\n학습 코드 · 예측값 · 평가 분할 미확인',
            transform=ax.transAxes,ha='center',va='center',fontsize=13 if compact else 17,linespacing=1.8,color='#516274')
    ax.text(.5,.15,'PPT 초안 AUC 0.69: 재현 근거 없음\n성능 수치와 인원 예측 그래프는 제시 보류',
            transform=ax.transAxes,ha='center',fontsize=11 if compact else 15,linespacing=1.8,color='#80572E')


def split_data(responses,categories):
    q=responses[responses.is_latest & responses.is_valid & responses.rejoined.notna()].copy()
    categories=categories.copy()
    categories['value']=categories.score_sum/categories.score_count
    features=categories.pivot_table(index='response_id',columns='category_code',values='value')
    columns=list(features.columns)
    data=q.merge(features,left_on='response_id',right_index=True,how='inner')
    data=data.dropna(subset=columns).sort_values('submitted_at')
    cutoff=data.submitted_at.quantile(.65)
    held=data.student_no.map(lambda s:int(hashlib.sha256(str(s).encode()).hexdigest()[:8],16)%5==0)
    train=data[(~held)&(data.submitted_at+pd.Timedelta(days=90)<=cutoff)].copy()
    test=data[held&(data.submitted_at>=cutoff)].copy()
    assert not (set(train.student_no)&set(test.student_no))
    assert (train.submitted_at+pd.Timedelta(days=90)).max()<=cutoff<=test.submitted_at.min()
    return train,test,columns,cutoff


def lr():
    return make_pipeline(StandardScaler(),LogisticRegression(max_iter=1000,random_state=42))


def cluster_indices(students):
    return [np.flatnonzero(students==s) for s in pd.unique(students)]


def resample(rng,groups):
    return np.concatenate([groups[i] for i in rng.integers(0,len(groups),len(groups))])


def experiments(ntrain,ntest,seed):
    r=pd.read_csv(DATA/'satisfaction_responses.csv',dtype={'student_no':str})
    r['submitted_at']=pd.to_datetime(r.submitted_at,format='ISO8601')
    c=pd.read_csv(DATA/'satisfaction_categories.csv')
    original=json.loads((SOURCE/'pbl3_model.json').read_text(encoding='utf-8'))
    # Execute the original evaluate function verbatim, without importing/mutating
    # the older working-tree analysis package. Imports inside evaluate are kept.
    tree=ast.parse((DATA/'sources/analysis/model.py').read_text(encoding='utf-8'))
    fn=next(x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name=='evaluate')
    ns={'pd':pd,'np':np,'hashlib':hashlib}
    exec(compile(ast.Module(body=[fn],type_ignores=[]),'committed_analysis_model','exec'),ns)
    evaluated=ns['evaluate'](r,c)
    dump(evaluated,DATA/'satisfaction_reproduced_model.json')
    measured=pd.DataFrame(evaluated['metrics'])
    stored=pd.DataFrame(original['metrics'])
    comparison=[]
    for i,row in stored.iterrows():
        for col in ['train_n','test_n',*METRICS]:
            actual=float(measured.iloc[i][col]); expected=float(row[col])
            comparison.append({'model':row['model'],'metric':col,'stored':expected,'reproduced':actual,
                               'difference':actual-expected,'matches':abs(actual-expected)<1e-12})
    comparison=pd.DataFrame(comparison)
    comparison.to_csv(DATA/'satisfaction_reproduction_check.csv',index=False,encoding='utf-8-sig')
    if not comparison.matches.all():
        raise RuntimeError('Original JSON not reproduced; inspect satisfaction_reproduction_check.csv')
    train,test,columns,cutoff=split_data(r,c)
    x=train[columns].to_numpy(); y=train.rejoined.astype(int).to_numpy()
    xt=test[columns].to_numpy(); yt=test.rejoined.astype(int).to_numpy()
    suspicious=train.is_suspicious.to_numpy()
    full=lr().fit(x,y); filtered=lr().fit(x[~suspicious],y[~suspicious])
    probabilities=[full.predict_proba(xt)[:,1],filtered.predict_proba(xt)[:,1]]
    pred=test[['response_id','student_no','session_id']].copy()
    pred['actual']=yt
    pred['p_logistic'],pred['p_filtered']=probabilities
    pred['pred_logistic']=full.predict(xt); pred['pred_filtered']=filtered.predict(xt)
    pred.to_csv(DATA/'satisfaction_test_predictions.csv',index=False,encoding='utf-8-sig')
    split=pd.concat([train[['response_id','student_no','submitted_at','rejoined','is_suspicious']].assign(split='train'),
                     test[['response_id','student_no','submitted_at','rejoined','is_suspicious']].assign(split='test')])
    split.to_csv(DATA/'satisfaction_split.csv',index=False,encoding='utf-8-sig')
    # Cross-check stored aggregate CSVs against the regenerated data.
    old=pd.read_csv(SOURCE/'pbl3_extended_summary.csv').sort_values('program_id').reset_index(drop=True)
    new=pd.read_csv(DATA/'satisfaction_summary_reproduced.csv').sort_values('program_id').reset_index(drop=True)
    summary_checks=[]
    for col in old.columns:
        a,b=old[col],new[col]
        match=bool(np.allclose(a,b,atol=1e-12,rtol=0,equal_nan=True)) if pd.api.types.is_numeric_dtype(a) else bool(a.equals(b))
        summary_checks.append({'field':col,'matches':match})
    if not all(s['matches'] for s in summary_checks):
        raise RuntimeError('Stored summary CSV does not match recreated dataset')
    key=hashlib.sha256((pred.to_csv(index=False)+train[columns+['student_no','rejoined','is_suspicious']].to_csv(index=False)
        +str((ntrain,ntest,seed,np.__version__,sklearn.__version__))).encode()).hexdigest()
    cache=DATA/'satisfaction_bootstrap_summary.json'
    if cache.exists() and json.loads(cache.read_text(encoding='utf-8')).get('cache_key')==key:
        summary=json.loads(cache.read_text(encoding='utf-8'))
        print('Using validated cached bootstrap experiment.',flush=True)
    else:
        rng=np.random.default_rng(seed)
        train_groups=cluster_indices(train.student_no.to_numpy())
        test_groups=cluster_indices(test.student_no.to_numpy())
        trials=[]
        print(f'Paired training-student bootstrap: {ntrain} replicates, fixed test n={len(test)}',flush=True)
        for i in range(ntrain):
            idx=resample(rng,train_groups)
            clean=idx[~suspicious[idx]]
            if len(np.unique(y[idx]))<2 or len(np.unique(y[clean]))<2:
                raise RuntimeError('Training bootstrap has a single class')
            models=[lr().fit(x[idx],y[idx]),lr().fit(x[clean],y[clean])]
            a,b=[roc_auc_score(yt,m.predict_proba(xt)[:,1]) for m in models]
            acca,accb=[accuracy_score(yt,m.predict(xt)) for m in models]
            trials.append({'resample':'training_students','replicate':i,'auc_logistic':a,'auc_filtered':b,
                           'delta_auc':b-a,'delta_accuracy':accb-acca,'rows':len(idx)})
            if (i+1)%250==0: print(f'  {i+1}/{ntrain}',flush=True)
        print(f'Paired test-student bootstrap: {ntest} replicates, fixed fitted models',flush=True)
        attempted=0; valid=0
        while valid<ntest:
            attempted+=1
            idx=resample(rng,test_groups)
            if len(np.unique(yt[idx]))<2:
                continue
            a,b=[roc_auc_score(yt[idx],prob[idx]) for prob in probabilities]
            acca,accb=[accuracy_score(yt[idx],m.predict(xt[idx])) for m in [full,filtered]]
            trials.append({'resample':'test_students','replicate':valid,'auc_logistic':a,'auc_filtered':b,
                           'delta_auc':b-a,'delta_accuracy':accb-acca,'rows':len(idx)})
            valid+=1
        trials=pd.DataFrame(trials)
        trials.to_csv(DATA/'satisfaction_bootstrap_replicates.csv',index=False,encoding='utf-8-sig')
        summary={'cache_key':key,'seed':seed,'training_replicates':ntrain,'test_replicates':ntest,
                 'test_bootstrap_attempts':attempted,'resampling_unit':'student',
                 'observed_auc_delta':float(measured.roc_auc.iloc[2]-measured.roc_auc.iloc[1]),'results':{}}
        for kind,part in trials.groupby('resample'):
            stats={}
            for col in ['auc_logistic','auc_filtered','delta_auc','delta_accuracy']:
                v=part[col]
                stats[col]={'mean':float(v.mean()),'sd':float(v.std(ddof=1)),
                            'p025':float(v.quantile(.025)),'p975':float(v.quantile(.975))}
            summary['results'][kind]=stats
        dump(summary,cache)
    protocol={'source':'repository synthetic data; recreated in isolated PostgreSQL',
        'original_json_matches':True,'aggregate_csv_checks':summary_checks,'features':columns,
        'train_n':len(train),'filtered_train_n':int((~train.is_suspicious).sum()),'test_n':len(test),
        'train_students':train.student_no.nunique(),'test_students':test.student_no.nunique(),
        'test_positive':int(yt.sum()),'test_negative':int((1-yt).sum()),'student_overlap':0,
        'cutoff':cutoff.isoformat(),'latest_training_label_time':(train.submitted_at+pd.Timedelta(days=90)).max().isoformat(),
        'earliest_test_time':test.submitted_at.min().isoformat(),'threshold':.5,
        'truth_used_as_features':False,'bootstrap_summary':'satisfaction_bootstrap_summary.json',
        'python':platform.python_version(),'numpy':np.__version__,'pandas':pd.__version__,
        'sklearn':sklearn.__version__,'matplotlib':matplotlib.__version__,
        'limits':['One synthetic world; no external student validation.',
                  'Cluster bootstrap handles repeated students, not shared program/session shocks.',
                  'Training bootstrap has a fixed test set and describes training variability, not a population CI.',
                  'Test percentile interval is conditional on the fitted models and observed student distribution.']}
    dump(protocol,DATA/'experiment_protocol.json')
    return summary


def additional_charts(summary,cohort):
    fig,axs=plt.subplots(1,2,figsize=(16,9),gridspec_kw={'width_ratios':[1,1.3]})
    fig.subplots_adjust(left=.085,right=.96,top=.76,bottom=.27,wspace=.42)
    fig.text(.055,.94,'A-3  응답 품질 보정 효과의 불확실성',fontsize=23,weight='bold')
    fig.text(.055,.875,'학생 단위 paired bootstrap | 학습 재표집과 평가 재표집을 분리',fontsize=13,color='#516274')
    s=summary['results']['training_students']
    means=[s[k]['mean'] for k in ['auc_logistic','auc_filtered']]
    sd=[s[k]['sd'] for k in ['auc_logistic','auc_filtered']]
    bars=axs[0].bar([0,1],means,color=[BLUE,GREEN],width=.55,yerr=sd,capsize=6)
    for bar,v,e in zip(bars,means,sd):
        axs[0].text(bar.get_x()+bar.get_width()/2,v+e+.025,f'{v:.4f}\n± {e:.4f}',ha='center',fontsize=12)
    axs[0].set_xticks([0,1],['전체 응답\n학습','의심 제외\n학습']); axs[0].set_ylim(0,1)
    axs[0].set_title(f"학습 재표집 {summary['training_replicates']:,}회",fontsize=16)
    axis(axs[0],'ROC-AUC (평균 ± 표준편차)')
    obs=summary['observed_auc_delta']
    names=['학습 학생 재표집','평가 학생 재표집']
    intervals=[summary['results'][k]['delta_auc'] for k in ['training_students','test_students']]
    for i,(name,st) in enumerate(zip(names,intervals)):
        center=st['mean'] if i==0 else obs
        axs[1].plot([st['p025'],st['p975']],[1-i,1-i],color=[BLUE,GREEN][i],lw=3)
        axs[1].scatter([center],[1-i],color=[BLUE,GREEN][i],s=65,zorder=3)
        axs[1].text((st['p025']+st['p975'])/2,1-i+.17,
                    f"[{st['p025']:+.4f}, {st['p975']:+.4f}]",ha='center',fontsize=11)
    bound=max(abs(st[k]) for st in intervals for k in ['p025','p975'])
    bound=max(.04,float(np.ceil(bound/.02)*.02))
    axs[1].set_xlim(-bound*1.35,bound*1.35); axs[1].set_ylim(-.5,1.65)
    axs[1].set_yticks([1,0],names); axs[1].axvline(0,color=GREY,ls='--',lw=1)
    axs[1].set_xlabel('Δ ROC-AUC (의심 제외 - 전체 응답)')
    axs[1].set_title(f'관측 차이 {obs:+.4f}',fontsize=16)
    axs[1].spines['left'].set_visible(False); axs[1].tick_params(axis='y',length=0)
    fig.text(.055,.065,
        f"왼쪽: 동일 평가 194건, 학습 학생 {summary['training_replicates']:,}회 재표집의 평균±SD.\n"
        f"오른쪽: 학습 분포의 2.5–97.5% 구간 / 고정 모델의 평가 학생 {summary['test_replicates']:,}회 재표집 95% percentile CI.\n"
        '평가 CI가 0을 포함하면 개선을 단정할 수 없음. 단일 합성 데이터·프로그램 간 상관 미반영.',
        fontsize=10,color='#516274',linespacing=1.5)
    save(fig,'performance_satisfaction_quality_effect')
    sensitivity=pd.read_csv(DATA/'budget_quality_sensitivity.csv')
    b=sensitivity[sensitivity.program_id.isin(cohort.program_id)].pivot(index='program_id',columns='policy',values='cost_per_satisfied').reindex(cohort.program_id)
    fig,ax=canvas('C-3  응답 제외 기준에 따른 비용 민감도','2025년 특강 5개 | 내용 평균 4점 이상을 유지하고 응답 제외 규칙만 비교',
        '합성 데이터 · 별도 SELECT로만 계산 · DB VIEW/설정 변경 없음\nSurvey Insight: 품질점수 70 미만 제외 / 기존 예산 뷰: 동일 점수 반복 응답 전체 제외')
    x=np.arange(len(cohort)); w=.35
    for offset,col,label,color in [(-.5,'straightline_excluded','동일 점수 반복 제외 (현재 예산 뷰)',ORANGE),
                                  (.5,'survey_quality_excluded','Survey Insight 의심 응답 제외',GREEN)]:
        bars=ax.bar(x+offset*w,b[col],width=w,label=label,color=color)
        for bar,v in zip(bars,b[col]):
            if pd.notna(v): ax.text(bar.get_x()+bar.get_width()/2,v+4000,f'{v:,.0f}',ha='center',fontsize=11)
    ax.set_xticks(x,[SHORT[s] for s in cohort.program_name]); axis(ax,'만족 출석자당 비용 (원/명)')
    ax.set_ylim(0,b.max().max()*1.25); ax.yaxis.set_major_formatter(ticker.StrMethodFormatter('{x:,.0f}'))
    ax.legend(frameon=False,loc='upper left')
    save(fig,'performance_budget_quality_sensitivity')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bootstrap-train',type=int,default=1000)
    p.add_argument('--bootstrap-test',type=int,default=2000)
    p.add_argument('--seed',type=int,default=20261124)
    args=p.parse_args()
    if min(args.bootstrap_train,args.bootstrap_test)<100:
        p.error('At least 100 replicates are required')
    family=style()
    stored=json.loads((SOURCE/'pbl3_model.json').read_text(encoding='utf-8'))
    metrics=pd.DataFrame(stored['metrics'])
    metrics.to_csv(DATA/'satisfaction_model_metrics.csv',index=False,encoding='utf-8-sig')
    fig,ax=canvas('A-1  만족도 기반 재참여 예측 성능','동일 평가 194건 | 다수 클래스 기준과 Logistic Regression 비교',
        '출처: pbl3_model.json · 합성 데이터 · 오차막대 없음(원본 단일 holdout)\n재참여: 설문 제출 후 90일 이내 후속 회차 출석(같은 프로그램 포함)')
    auc_panel(ax,metrics); save(fig,'performance_satisfaction_auc')
    fig,ax=canvas('A-2  분류 성능 지표 비교','양성 클래스: 90일 이내 재참여 | 임계값 0.5 | 동일 평가 194건',
        'Accuracy=전체 정답률 · Precision=재참여 예측 중 실제 비율 · Recall=실제 재참여 중 탐지 비율\nF1=Precision·Recall 조화평균 · 합성 데이터 · 기준 모델은 전원 재참여로 예측')
    colors=[BLUE,ORANGE,GREEN,'#8064A2']; w=.18; x=np.arange(3)
    for i,(col,label,color) in enumerate(zip(METRICS[:4],['Accuracy','Precision','Recall','F1-score'],colors)):
        bars=ax.bar(x+(i-1.5)*w,metrics[col],width=w,color=color,label=label)
        for b,v in zip(bars,metrics[col]):
            ax.text(b.get_x()+b.get_width()/2,v+.012,f'{v:.4f}',ha='center',fontsize=10)
        bars[0].set_hatch('//')
    ax.set_ylim(0,1.12); ax.set_yticks(np.arange(0,1.01,.2)); ax.set_xticks(x,MODEL_LABELS)
    axis(ax,'분류 성능 (0–1)'); ax.legend(frameon=False,ncol=4,loc='upper center',bbox_to_anchor=(.5,1.16))
    save(fig,'performance_satisfaction_metrics')
    fig,ax=canvas('B  시간표 정보 추가에 따른 참여 예측 성능','저장소 브랜치·코드·결과 파일 확인 결과',
        '기준 / 기본 / 시간표 추가 / 전체 특징: 동일 평가 실험의 구현 또는 결과 파일 확인 필요\n값이 없는 항목을 0 또는 추정 AUC로 표시하지 않음')
    missing_panel(ax); save(fig,'performance_participation_auc')
    budget=pd.read_csv(DATA/'budget_program_cost.csv')
    cohort=cost_cohort(budget)
    if len(cohort)!=5: raise RuntimeError('Expected all five 2025 lecture programs')
    for col,name in [('cost_per_unique_attendee','rank_unique'),('cost_per_satisfied','rank_satisfied')]:
        budget[name]=budget.groupby('program_type_code')[col].rank(method='min')
        cohort[name]=cohort[col].rank(method='min')
    budget['rank_change']=budget.rank_unique-budget.rank_satisfied
    cohort['rank_change']=cohort.rank_unique-cohort.rank_satisfied
    budget.to_csv(DATA/'budget_rankings_all_programs.csv',index=False,encoding='utf-8-sig')
    cohort.to_csv(DATA/'budget_presentation_cohort.csv',index=False,encoding='utf-8-sig')
    sensitivity=pd.read_csv(DATA/'budget_quality_sensitivity.csv')
    policy=sensitivity.pivot(index='program_id',columns='policy',values=[
        'satisfied_attendees','cost_per_satisfied','satisfied_five_score','cost_per_satisfied_five_score'])
    policy.columns=['_'.join(col) for col in policy.columns]
    policy['cost_delta_pct']=(policy.cost_per_satisfied_survey_quality_excluded /
                              policy.cost_per_satisfied_straightline_excluded-1)*100
    policy.to_csv(DATA/'budget_quality_policy_comparison.csv',encoding='utf-8-sig')
    fig,ax=canvas('C-1  출석 인원과 만족도를 반영한 비용 비교','같은 유형·연도: 2025년 특강 5개 전체 | 낮을수록 해당 기준의 비용이 낮음',
        '합성 데이터 · 승인 지출만 포함 · 학생별 고유 집계\n만족 출석자: 동일 점수 반복을 제외한 완료 응답의 개인별 내용 평균 4점 이상 · main 뷰 정의')
    cost_panel(ax,cohort); save(fig,'performance_budget_cost')
    fig,ax=canvas('C-2  비용 평가 기준에 따른 순위 변화','2025년 특강 5개 | 각 기준의 비용이 낮을수록 1위',
        '합성 데이터 · 같은 유형·연도 안에서만 비교 · 비용 기준의 순위 변화는 교육 성과의 인과효과가 아님\n전체 35개 프로그램의 승인 지출·고유/만족/반복 출석자당 비용과 유형 내 순위는 CSV에 수록')
    fig.subplots_adjust(left=.27,right=.76)
    palette=plt.get_cmap('tab10')
    for i,row in enumerate(cohort.itertuples()):
        color=palette(i)
        ax.plot([0,1],[row.rank_unique,row.rank_satisfied],'-o',color=color,lw=2.5,markersize=9)
        ax.text(-.08,row.rank_unique,f'{int(row.rank_unique)}위  {SHORT[row.program_name]}',ha='right',va='center',fontsize=13,color=color)
        ax.text(1.08,row.rank_satisfied,f'{SHORT[row.program_name]}  {int(row.rank_satisfied)}위',ha='left',va='center',fontsize=13,color=color)
    ax.set_xlim(-.05,1.05); ax.set_ylim(len(cohort)+.5,.5)
    ax.set_xticks([0,1],['고유 출석자당 비용','만족 출석자당 비용']); ax.set_yticks(range(1,len(cohort)+1))
    fig.text(.055,.81,'세로 위치: 유형·연도 내 순위 (1위 = 최저 비용)',fontsize=12,color='#516274')
    ax.yaxis.grid(True,alpha=.2); ax.spines['left'].set_visible(False); ax.tick_params(axis='y',labelleft=False,left=False)
    save(fig,'performance_budget_ranking')
    summary=experiments(args.bootstrap_train,args.bootstrap_test,args.seed)
    additional_charts(summary,cohort)
    fig=plt.figure(figsize=(20,11.25))
    gs=fig.add_gridspec(1,3,width_ratios=[1.05,.95,1.8],left=.065,right=.98,bottom=.27,top=.73,wspace=.35)
    axes=[fig.add_subplot(gs[0,i]) for i in range(3)]
    fig.text(.05,.945,'PBL 미션 3  |  세 분석 기술의 정량 평가',fontsize=29,weight='bold')
    fig.text(.05,.875,'합성 데이터 실험 · 기술별 평가 지표와 단위는 각 패널에 별도 표시',fontsize=17,color='#516274')
    auc_panel(axes[0],metrics,True); axes[0].set_title('A  만족도 → 재참여\n동일 평가 194건',fontsize=18,pad=25)
    missing_panel(axes[1],True); axes[1].set_title('B  시간표 → 참여 예측\n평가 결과 확인 필요',fontsize=18,pad=25)
    cost_panel(axes[2],cohort,True); axes[2].set_title('C  비용 평가 기준 비교\n2025년 특강 5개 전체',fontsize=18,pad=25)
    st=summary['results']['test_students']['delta_auc']
    fig.text(.05,.115,f"A  의심 제외 학습 ΔAUC {summary['observed_auc_delta']:+.4f}; 학생 재표집 95% CI [{st['p025']:+.4f}, {st['p975']:+.4f}]. 개선 단정 불가.",fontsize=13,color='#516274')
    fig.text(.05,.072,'B  AUC 0.69의 재현 근거 없음.  C  승인 지출 / 고유 학생 수; 만족=동일 점수 반복 제외 후 내용 평균 4점 이상.',fontsize=13,color='#516274')
    fig.text(.05,.035,'A는 모델 예측력, C는 비용 평가 관점의 변화. 실데이터 외부 검증·인과효과 검증은 수행하지 않음.',fontsize=13,color='#516274')
    save(fig,'performance_three_services')
    dump({'korean_font':family,'dpi':320,'standalone_aspect_ratio':'16:9','combined_aspect_ratio':'16:9',
          'files':[f.name for f in sorted(FIGURES.glob('*'))],
          'participation_status':'implementation_or_result_missing; no numerical estimate',
          'budget_cohort_rule':'all LECTURE programs named *2025 (n=5), no outcome-based selection'},
         DATA/'figure_manifest.json')
    print('Created 8 PNG/SVG figure pairs. Participation panel explicitly marks missing evidence.',flush=True)


if __name__=='__main__':
    main()
