"""Capture immutable branch evidence without checkout, merge, fetch, or DB access.

Requires the origin/* refs recorded in the delivered manifest. Ref changes will
produce different snapshots; use the recorded commit SHAs for an exact rerun.
"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'presentation_assets/data/sources'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    specs = {
        'origin/main': ['pbl3/'+name for name in [
            '10_pbl3_schema.sql','11_pbl3_generate.sql','12_pbl3_views.sql',
            '13_pbl3_verify.sql','14_pbl3_survey_insight.sql','README.md']],
        'origin/feat/satisfaction-analysis_1': ['analysis/model.py','analysis/db.py',
            'analysis/reports/pbl3_model.json','analysis/reports/pbl3_extended_metadata.json',
            *['analysis/reports/pbl3_extended_'+suffix+'.csv' for suffix in [
                'quality','summary','behavior','satisfaction_behavior','sensitivity']],
            'pbl3/14_pbl3_survey_insight.sql'],
    }
    manifest=[]
    for ref,paths in specs.items():
        commit=git('rev-parse',ref).decode().strip()
        for name in paths:
            raw=git('show',f'{commit}:{name}')
            relative='satisfaction_branch/'+name if ref.endswith('satisfaction-analysis_1') and name.startswith('pbl3/') else name
            target=OUT/relative
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(raw)
            manifest.append({'ref':ref,'commit':commit,'path':name,'snapshot_path':relative,
                             'sha256':hashlib.sha256(raw).hexdigest()})
    (OUT/'source_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    inventory=[]; searches=[]
    for ref in git('for-each-ref','--format=%(refname:short)','refs/heads','refs/remotes').decode().splitlines():
        files=git('-c','core.quotepath=false','ls-tree','-r','--name-only',ref).decode('utf-8').splitlines()
        commit=git('rev-parse',ref).decode().strip()
        inventory.append({'ref':ref,'commit':commit,'code_files':[
            f for f in files if f.endswith(('.py','.ipynb','.R','.r')) or ('pbl3' in f and f.endswith('.sql'))]})
        result=subprocess.run(['git','grep','-n','-I','-E',
            '0[.]69|roc_auc|LogisticRegression|RandomForest|train_test_split|statsmodels',
            ref,'--','*.py','*.R','*.r','*.ipynb','*.sql','*.md','*.json'],
            cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace')
        if result.returncode not in (0,1):
            raise RuntimeError(f'Git search failed: {ref}')
        searches.append({'ref':ref,'commit':commit,'matches':result.stdout.splitlines()})
    for name,data in [('branch_inventory.json',inventory),('model_search.json',searches)]:
        (OUT/name).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Captured {len(manifest)} files; searched {len(inventory)} branch refs. No checkout or merge.')


if __name__=='__main__':
    main()
