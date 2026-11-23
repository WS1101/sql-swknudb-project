"""Start the prepared .local PostgreSQL demo and Streamlit without shell policy changes.

Fresh checkouts: prepare a database following analysis/README.md first.
"""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
from urllib.parse import urlsplit


def main():
    root=Path(__file__).resolve().parents[1]
    dsn_file=root/'.local'/'test_dsn.txt'
    if not dsn_file.exists():
        raise SystemExit('Prepared local database not found. Follow analysis/README.md first.')
    env=os.environ.copy()
    packages=root/'.local'/'python'
    if packages.exists():
        env['PYTHONPATH']=str(packages)+os.pathsep+env.get('PYTHONPATH','')
    dsn=dsn_file.read_text(encoding='ascii').strip()
    address=urlsplit(dsn)
    if address.hostname!='127.0.0.1' or not address.port:
        raise SystemExit('The prepared demo must use an explicit loopback address and port.')
    flags={'creationflags':subprocess.CREATE_NO_WINDOW} if os.name=='nt' else {}
    # Process ownership checks can fail inside IDE sandboxes even for a live server.
    try:
        with socket.create_connection((address.hostname,address.port),timeout=2):
            ready=True
    except OSError:
        ready=False
    if not ready:
        if not shutil.which('psql'):
            raise SystemExit('PostgreSQL bin directory must be in PATH.')
        subprocess.run([sys.executable,'-m','analysis.local_test_db','start'],cwd=root,env=env,
                       check=True,timeout=30,**flags)
    env['SURVEY_DATABASE_URL']=dsn
    try:
        subprocess.run([sys.executable,'-m','streamlit','run','analysis/app.py','--server.address','127.0.0.1',
                        '--server.headless','true','--browser.gatherUsageStats','false'],cwd=root,env=env,check=True)
    except KeyboardInterrupt:
        pass


if __name__=='__main__': main()
