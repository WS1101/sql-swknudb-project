"""Optional reattendance prediction; only survey category scores enter the model.

Future labels are purged from training; test students never appear in training.
Synthetic results describe the generator, never real student accuracy/causal effects.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd

from analysis.db import PBL3_FOLLOWUP_DEFINITION, PBL3_INTERPRETATION_NOTE, QualityConfig, load_analysis


def evaluate(responses, categories):
    # Import lazily so the primary dashboard does not require sklearn.
    from sklearn.dummy import DummyClassifier
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import StandardScaler

    q=responses[responses.is_latest & responses.is_valid & responses.rejoined.notna()].copy()
    if q.empty:
        return {'status':'평가 불가','reason':'90일 관찰 완료 응답이 없습니다.'}
    cat=categories.copy()
    cat['value']=cat.score_sum/cat.score_count
    features=cat.pivot_table(index='response_id',columns='category_code',values='value')
    data=q.merge(features,left_on='response_id',right_index=True,how='inner')
    # Distinct categories are used by their actual code; never fabricate missing instructor/time scores.
    columns=list(features.columns)
    if len(columns)<2:
        return {'status':'평가 불가','reason':'서로 다른 점수형 문항분류가 2개 미만입니다.'}
    data=data.dropna(subset=columns).sort_values('submitted_at')
    if len(data)<100:
        return {'status':'평가 불가','reason':'관찰 완료·문항분류 완비 응답 100건 미만입니다.'}
    cutoff=data.submitted_at.quantile(.65)
    heldout=data.student_no.map(lambda x:int(hashlib.sha256(str(x).encode()).hexdigest()[:8],16)%5==0)
    train=data[(~heldout) & (data.submitted_at+pd.Timedelta(days=90)<=cutoff)]
    test=data[heldout & (data.submitted_at>=cutoff)]
    if len(train)<50 or len(test)<20 or train.rejoined.nunique()<2 or test.rejoined.nunique()<2:
        return {'status':'평가 불가','reason':'시간 분리·학생 분리 후 표본 또는 두 클래스가 부족합니다.',
                'train_n':len(train),'test_n':len(test),'cutoff':cutoff.isoformat()}
    ytrain=train.rejoined.astype(int)
    ytest=test.rejoined.astype(int)
    models={'기준: 다수 클래스':DummyClassifier(strategy='most_frequent'),
            'Logistic Regression':make_pipeline(StandardScaler(),LogisticRegression(max_iter=1000,random_state=42))}
    filtered=train[~train.is_suspicious]
    if len(filtered)>=50 and filtered.rejoined.nunique()==2:
        models['의심 제외 학습 Logistic']=make_pipeline(StandardScaler(),LogisticRegression(max_iter=1000,random_state=42))
    metrics=[]
    fitted={}
    for name,model in models.items():
        tr=filtered if name=='의심 제외 학습 Logistic' else train
        model.fit(tr[columns],tr.rejoined.astype(int))
        pred=model.predict(test[columns])
        prob=model.predict_proba(test[columns])[:,1]
        metrics.append({'model':name,'train_n':len(tr),'test_n':len(test),'accuracy':accuracy_score(ytest,pred),
            'precision':precision_score(ytest,pred,zero_division=0),'recall':recall_score(ytest,pred,zero_division=0),
            'f1':f1_score(ytest,pred,zero_division=0),'roc_auc':roc_auc_score(ytest,prob)})
        fitted[name]=model
    model=fitted['Logistic Regression']
    coefficients=model.named_steps['logisticregression'].coef_[0]
    importance=[]
    base=model.predict_proba(test[columns])[:,1]
    names=cat.drop_duplicates('category_code').set_index('category_code').category_name.to_dict()
    for col,coef in zip(columns,coefficients):
        deltas={}
        for step in (-.5,.5):
            changed=test[columns].copy()
            changed[col]=(changed[col]+step).clip(1,5)
            deltas[str(step)]=float(np.mean(model.predict_proba(changed)[:,1]-base))
        importance.append({'category_code':col,'category_name':names[col],
                           'standardized_coefficient':float(coef),'absolute_coefficient':float(abs(coef)),
                           'delta_minus_0.5':deltas['-0.5'],'delta_plus_0.5':deltas['0.5']})
    return {'status':'evaluated','cutoff':cutoff.isoformat(),'train_n':len(train),'test_n':len(test),
        'train_positive_rate':float(ytrain.mean()),'test_positive_rate':float(ytest.mean()),
        'student_overlap':len(set(train.student_no)&set(test.student_no)),
        'latest_training_label_time':(train.submitted_at+pd.Timedelta(days=90)).max().isoformat(),
        'earliest_test_time':test.submitted_at.min().isoformat(),'metrics':metrics,'importance':importance,
        'limitation':'단일 시점 holdout 평가. 반복 응답의 상관·합성 생성 가정 영향을 받음. 계수/±0.5 변화는 인과효과가 아님.'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',choices=['existing','synthetic','pbl3'],default='existing')
    p.add_argument('--asof',default=datetime.now(timezone.utc).date().isoformat())
    p.add_argument('--output',type=Path,default=Path('analysis/reports/model.json'))
    a=p.parse_args()
    _,r,c=load_analysis(QualityConfig(),a.source,datetime.fromisoformat(a.asof+'T23:59:59+00:00'),include_participation=True)
    result={'source':a.source,'asof':a.asof,**evaluate(r,c)}
    if a.source == 'pbl3':
        result['followup_definition'] = PBL3_FOLLOWUP_DEFINITION
        result['interpretation_note'] = PBL3_INTERPRETATION_NOTE
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__': main()
