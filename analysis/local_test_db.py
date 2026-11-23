"""Create an isolated PostgreSQL cluster under ignored .local (never touches port 5432).

Windows: python -m analysis.local_test_db init|start|stop
The generated password/DSN is stored only inside ignored .local, never printed.
"""
import argparse
import os
from pathlib import Path
import secrets
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
LOCAL=ROOT/'.local'
DATA=LOCAL/'pgdata'
PORT=55439


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['init','start','stop'])
    p.add_argument('--pg-bin',default=str(Path(shutil.which('psql') or '').parent))
    a=p.parse_args()
    suffix='.exe' if os.name=='nt' else ''
    flags={'creationflags':subprocess.CREATE_NO_WINDOW} if os.name=='nt' else {}
    def run(name,*args):
        subprocess.run([str(Path(a.pg_bin)/(name+suffix)),*map(str,args)],check=True,cwd=ROOT,**flags)
    LOCAL.mkdir(exist_ok=True)
    if a.action=='init':
        if DATA.exists():
            raise SystemExit('기존 클러스터가 있습니다. 삭제하지 않고 중단합니다. start를 사용하세요.')
        password=secrets.token_urlsafe(32)
        pw=LOCAL/'init-password.tmp'
        try:
            pw.write_text(password,encoding='ascii')
            run('initdb','-D',DATA,'-U','survey_test','-A','scram-sha-256',f'--pwfile={pw}','--encoding=UTF8','--locale=C')
        finally:
            pw.unlink(missing_ok=True)
        (LOCAL/'test_dsn.txt').write_text(f'postgresql://survey_test:{password}@127.0.0.1:{PORT}/survey_insight_test',encoding='ascii')
        with (DATA/'postgresql.conf').open('a',encoding='ascii') as f:
            f.write(f"\nlisten_addresses = '127.0.0.1'\nport = {PORT}\n")
        print('Isolated test cluster initialized; credentials stored in ignored .local/test_dsn.txt')
    elif a.action=='start':
        run('pg_ctl','-D',DATA,'-l',LOCAL/'postgres.log','-w','start')
    else:
        run('pg_ctl','-D',DATA,'-m','fast','-w','stop')


if __name__=='__main__': main()
