"""Check delivered measurements, source hashes and export properties offline."""
from pathlib import Path
from decimal import Decimal, ROUND_HALF_UP
import hashlib
import json

import numpy as np
import pandas as pd
from PIL import Image
from sklearn.metrics import accuracy_score,precision_score,recall_score,f1_score,roc_auc_score

ROOT=Path(__file__).resolve().parents[2]/'presentation_assets'
DATA=ROOT/'data'


def main():
    checks=[]

    def check(name,condition):
        checks.append({'check':name,'passed':bool(condition)})

    manifest=json.loads((DATA/'sources/source_manifest.json').read_text(encoding='utf-8'))
    for row in manifest:
        path=DATA/'sources'/row.get('snapshot_path',row['path'])
        check('source_hash:'+str(path.relative_to(DATA)),hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'])
    measured=pd.read_csv(DATA/'satisfaction_model_metrics.csv')
    predictions=pd.read_csv(DATA/'satisfaction_test_predictions.csv')
    check('same_194_test_rows',len(predictions)==194 and predictions.response_id.is_unique)
    check('observed_class_counts',predictions.actual.sum()==141 and (predictions.actual==0).sum()==53)
    for i,(prob,pred) in enumerate([('p_logistic','pred_logistic'),('p_filtered','pred_filtered')],start=1):
        for metric,fn in [('accuracy',accuracy_score),('precision',precision_score),('recall',recall_score),('f1',f1_score)]:
            check(f'prediction_metric:{i}:{metric}',np.isclose(fn(predictions.actual,predictions[pred]),measured.iloc[i][metric],atol=1e-12,rtol=0))
        check(f'prediction_metric:{i}:roc_auc',np.isclose(roc_auc_score(predictions.actual,predictions[prob]),measured.iloc[i].roc_auc,atol=1e-12,rtol=0))
    check('baseline_accuracy',np.isclose(measured.iloc[0].accuracy,predictions.actual.mean(),atol=1e-12,rtol=0))
    check('baseline_auc',measured.iloc[0].roc_auc==.5)
    check('stored_reproduction',pd.read_csv(DATA/'satisfaction_reproduction_check.csv').matches.all())
    split=pd.read_csv(DATA/'satisfaction_split.csv',dtype={'student_no':str})
    split['submitted_at']=pd.to_datetime(split.submitted_at,format='ISO8601')
    train=split[split.split.eq('train')]; test=split[split.split.eq('test')]
    check('train_test_students_disjoint',not(set(train.student_no)&set(test.student_no)))
    check('training_labels_mature_before_test',(train.submitted_at+pd.Timedelta(days=90)).max()<test.submitted_at.min())
    check('training_counts',len(train)==1179 and (~train.is_suspicious).sum()==1093)
    bs=json.loads((DATA/'satisfaction_bootstrap_summary.json').read_text(encoding='utf-8'))
    trials=pd.read_csv(DATA/'satisfaction_bootstrap_replicates.csv')
    check('bootstrap_counts',len(trials[trials['resample'].eq('training_students')])==bs['training_replicates'] and len(trials[trials['resample'].eq('test_students')])==bs['test_replicates'])
    check('bootstrap_pairing',np.allclose(trials.delta_auc,trials.auc_filtered-trials.auc_logistic,atol=1e-12,rtol=0))
    for kind,stats in bs['results'].items():
        part=trials[trials['resample'].eq(kind)]
        for col,s in stats.items():
            for name,value in [('mean',part[col].mean()),('sd',part[col].std(ddof=1)),('p025',part[col].quantile(.025)),('p975',part[col].quantile(.975))]:
                check(f'bootstrap_summary:{kind}:{col}:{name}',np.isclose(value,s[name],atol=1e-12,rtol=0))
    budget=pd.read_csv(DATA/'budget_program_cost.csv')
    for denominator,col in [('unique_attendees','cost_per_unique_attendee'),('satisfied_attendees','cost_per_satisfied'),('returning_attendees','cost_per_returning')]:
        ok=True
        for row in budget.to_dict('records'):
            n=int(row[denominator])
            if not n:
                ok=ok and pd.isna(row[col])
            else:
                exact=int((Decimal(int(row['approved_cost']))/Decimal(n)).quantize(Decimal('1'),rounding=ROUND_HALF_UP))
                ok=ok and exact==row[col]
        check('budget_formula:'+col,ok)
    check('budget_unique_counts',(budget.unique_attendees<=budget.attendance_records).all())
    check('budget_satisfied_subset',(budget.satisfied_attendees<=budget.unique_attendees).all())
    check('budget_sql_audit',(pd.read_csv(DATA/'budget_validation.csv').violations==0).all())
    sensitivity=pd.read_csv(DATA/'budget_quality_sensitivity.csv')
    current=sensitivity[sensitivity.policy.eq('straightline_excluded')].set_index('program_id').sort_index()
    check('budget_sensitivity_original_matches_view',np.array_equal(current.cost_per_satisfied,budget.set_index('program_id').sort_index().cost_per_satisfied))
    cohort=pd.read_csv(DATA/'budget_presentation_cohort.csv')
    check('budget_cohort_complete',set(cohort.program_id)==set(budget[budget.program_type_code.eq('LECTURE')&budget.program_name.str.endswith('2025')].program_id))
    check('budget_cohort_ranks',cohort.rank_unique.equals(cohort.cost_per_unique_attendee.rank(method='min')) and cohort.rank_satisfied.equals(cohort.cost_per_satisfied.rank(method='min')))
    figures=list((ROOT/'figures').glob('*.png'))
    check('eight_png_figures',len(figures)==8)
    for path in figures:
        with Image.open(path) as im:
            check('16_9:'+path.name,im.width*9==im.height*16)
            check('dpi_300_or_more:'+path.name,min(im.info['dpi'])>=300)
        check('svg_exists:'+path.name,path.with_suffix('.svg').is_file())
    # Missing evidence must not silently become zero-valued performance rows.
    check('no_fabricated_participation_prediction',not(ROOT/'figures/performance_participation_prediction.png').exists())
    check('no_fabricated_participation_auc_data',not(DATA/'participation_model_metrics.csv').exists())
    report={'passed':all(x['passed'] for x in checks),'check_count':len(checks),'checks':checks}
    (DATA/'validation_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f"{'PASS' if report['passed'] else 'FAIL'}: {len(checks)} source/measurement/export checks")
    if not report['passed']:
        raise SystemExit(str([x for x in checks if not x['passed']]))


if __name__=='__main__':
    main()
