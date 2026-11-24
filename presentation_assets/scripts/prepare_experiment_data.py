"""Recreate the committed synthetic world in a NEW, isolated PostgreSQL cluster.

Never connects to a user's database. Never runs reset.sql/reset_pbl3.sql. The SQL
snapshots are applied only after checking that this newly created database is empty.
Only observed pbl3 survey data and aggregate costs are exported; no latent truth
variables are model inputs. Requires psycopg[binary] and PostgreSQL 16 binaries.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile
import time

import pandas as pd
import psycopg
from psycopg.rows import dict_row

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'presentation_assets/data'
SOURCES = DATA / 'sources'


def sql_text(path):
    return '\n'.join(line for line in path.read_text(encoding='utf-8').splitlines()
                     if not line.lstrip().startswith('\\'))


def export(conn, sql, filename):
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql)
        df = pd.DataFrame(cur.fetchall(), columns=[x.name for x in cur.description])
    # Decimal values serialize as decimal strings in CSV, without float rounding.
    df.to_csv(DATA / filename, index=False, encoding='utf-8-sig')
    return df


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--pg-bin', type=Path, default=Path(shutil.which('psql') or '').parent)
    args = p.parse_args()
    pg_bin = args.pg_bin.resolve()
    suffix = '.exe' if os.name == 'nt' else ''
    for binary in ('initdb', 'pg_ctl', 'postgres'):
        if not (pg_bin / (binary + suffix)).is_file():
            raise SystemExit(f'PostgreSQL binary not found: {binary}')
    local = ROOT / '.local'
    local.mkdir(exist_ok=True)
    # mkdtemp guarantees a fresh location; no reuse of an existing cluster/DB.
    scratch = Path(tempfile.mkdtemp(prefix='pbl3_performance_', dir=local)).resolve()
    if not scratch.is_relative_to(local.resolve()):
        raise RuntimeError('Scratch directory outside .local')
    cluster = scratch / 'pgdata'
    password = secrets.token_urlsafe(32)
    pwfile = scratch / 'init_password.tmp'
    pwfile.write_text(password, encoding='ascii')
    flags = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
    log = scratch / 'commands.log'

    def run(binary, *argv, timeout=50):
        with log.open('a', encoding='utf-8') as out:
            subprocess.run([str(pg_bin / (binary + suffix)), *map(str, argv)],
                           check=True, cwd=ROOT, stdout=out, stderr=out,
                           timeout=timeout, **flags)

    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    started = False
    server = None
    server_log = None
    try:
        print('Initializing a new isolated cluster...', flush=True)
        try:
            run('initdb', '-D', cluster, '-U', 'performance_eval', '-A', 'scram-sha-256',
                f'--pwfile={pwfile}', '--encoding=UTF8', '--locale=C')
        finally:
            pwfile.unlink(missing_ok=True)
        with (cluster / 'postgresql.conf').open('a', encoding='ascii') as f:
            f.write(f"\nlisten_addresses='127.0.0.1'\nport={port}\nmax_connections=10\n"
                    "shared_buffers='32MB'\n")
        options = dict(host='127.0.0.1', port=port, user='performance_eval',
                       password=password, connect_timeout=5, autocommit=True)
        # Launch the server directly. pg_ctl start cannot create its Windows
        # restricted token in some IDE process sandboxes (Windows error 87).
        server_log = (scratch / 'postgres.log').open('w', encoding='utf-8')
        server = subprocess.Popen([str(pg_bin / ('postgres' + suffix)), '-D', str(cluster)],
                                  cwd=ROOT, stdout=server_log, stderr=server_log, **flags)
        started = True
        deadline = time.monotonic() + 20
        while True:
            if server.poll() is not None:
                raise RuntimeError(f'Isolated server failed; inspect {scratch.name}/postgres.log')
            try:
                with psycopg.connect(dbname='postgres', **options):
                    break
            except psycopg.OperationalError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Isolated server startup timed out') from None
                time.sleep(.2)
        dbname = 'pbl3_performance_synthetic_test'
        with psycopg.connect(dbname='postgres', **options) as conn:
            conn.execute('CREATE DATABASE pbl3_performance_synthetic_test')
        with psycopg.connect(dbname=dbname, **options) as conn:
            if conn.execute('SELECT current_database()').fetchone()[0] != dbname:
                raise RuntimeError('Unexpected database')
            if conn.execute("SELECT to_regnamespace('pbl3')").fetchone()[0] is not None:
                raise RuntimeError('Refusing to apply schema to a populated database')
            conn.execute("SET timezone='Asia/Seoul'")
            conn.execute("SET statement_timeout='300s'")
            conn.execute('CREATE EXTENSION btree_gist')
            for name in ('10_pbl3_schema.sql', '11_pbl3_generate.sql',
                         '12_pbl3_views.sql', '13_pbl3_verify.sql',
                         '14_pbl3_survey_insight.sql'):
                print(f'Applying snapshot: {name}', flush=True)
                # Same follow-up semantics, with the committed NOT MATERIALIZED
                # query optimization used by the original 194-row evaluation.
                source_dir = SOURCES / 'satisfaction_branch' if name.startswith('14_') else SOURCES
                conn.execute(sql_text(source_dir / 'pbl3' / name), prepare=False)
            # All subsequent operations are enforced read-only, in one snapshot.
            conn.autocommit = False
            conn.read_only = True
            conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            print('Exporting observed survey rows and aggregate costs (read only)...', flush=True)
            responses = export(conn, """
                SELECT q.*, f.followup_status, f.rejoined, f.opportunity_count,
                       sv.session_id
                  FROM pbl3.fn_survey_quality('{}', 'pbl3') q
                  LEFT JOIN pbl3.fn_survey_followup('2026-11-23T23:59:59+00:00','pbl3') f
                    USING (response_id)
                  JOIN pbl3.survey sv ON sv.survey_id=q.survey_id
                 ORDER BY q.response_id
                """, 'satisfaction_responses.csv')
            categories = export(conn, """SELECT * FROM pbl3.v_survey_insight_category
                WHERE data_source='pbl3' ORDER BY response_id,category_code""",
                'satisfaction_categories.csv')
            budget = export(conn, """SELECT c.*,t.program_type_name
                FROM pbl3.v_program_cost c JOIN pbl3.program_type t USING(program_type_code)
                ORDER BY program_type_code,program_id""", 'budget_program_cost.csv')
            export(conn, "SELECT * FROM pbl3.fn_survey_summary('{}','pbl3') ORDER BY program_id",
                   'satisfaction_summary_reproduced.csv')
            # Change only the query's response filter; do not replace DB views/settings.
            export(conn, """
                WITH att AS (
                    SELECT s.program_id,pp.student_no,count(*) AS n
                    FROM pbl3.program_participant pp JOIN pbl3.program_session s USING(session_id)
                    WHERE attendance_status='ATTENDED' GROUP BY s.program_id,pp.student_no
                ), q AS (
                    SELECT * FROM pbl3.fn_survey_quality('{}','pbl3')
                ), policy AS (
                    SELECT r.*,v.policy FROM pbl3.v_response_scored r
                    JOIN q USING(response_id)
                    CROSS JOIN (VALUES ('straightline_excluded'),('survey_quality_excluded'),
                                       ('all_completed')) v(policy)
                    WHERE r.is_completed AND q.is_valid AND q.is_latest
                      AND CASE v.policy
                          WHEN 'straightline_excluded' THEN NOT r.is_straightline
                          WHEN 'survey_quality_excluded' THEN NOT q.is_suspicious
                          ELSE TRUE END
                ), sat AS (
                    SELECT policy,program_id,student_no,avg(content) AS avg_content,
                           avg((content+instructor+operation+facility+schedule)/5.0) AS avg_score
                    FROM policy GROUP BY policy,program_id,student_no
                )
                SELECT c.program_id,c.program_name,c.program_type_code,v.policy,c.approved_cost,
                       count(st.student_no) FILTER(WHERE st.avg_content>=4) AS satisfied_attendees,
                       round(c.approved_cost/NULLIF(count(st.student_no) FILTER(WHERE st.avg_content>=4),0))
                           AS cost_per_satisfied,
                       count(st.student_no) FILTER(WHERE st.avg_score>=4) AS satisfied_five_score,
                       round(c.approved_cost/NULLIF(count(st.student_no) FILTER(WHERE st.avg_score>=4),0))
                           AS cost_per_satisfied_five_score
                FROM pbl3.v_program_cost c
                CROSS JOIN (VALUES ('straightline_excluded'),('survey_quality_excluded'),
                                   ('all_completed')) v(policy)
                LEFT JOIN att a ON a.program_id=c.program_id
                LEFT JOIN sat st ON st.program_id=c.program_id AND st.student_no=a.student_no
                                 AND st.policy=v.policy
                GROUP BY c.program_id,c.program_name,c.program_type_code,v.policy,c.approved_cost
                ORDER BY c.program_id,v.policy
                """, 'budget_quality_sensitivity.csv')
            checks = export(conn, """
                WITH cost AS (
                    SELECT program_id,sum(amount) AS amount FROM pbl3.expenditure
                    WHERE status='APPROVED' GROUP BY program_id
                ), att AS (
                    SELECT s.program_id,count(DISTINCT pp.student_no) AS n
                    FROM pbl3.program_participant pp JOIN pbl3.program_session s USING(session_id)
                    WHERE attendance_status='ATTENDED' GROUP BY s.program_id
                )
                SELECT 'approved_cost_matches' AS check_name,
                       count(*) FILTER(WHERE v.approved_cost IS DISTINCT FROM c.amount) AS violations
                  FROM pbl3.v_program_cost v LEFT JOIN cost c USING(program_id)
                UNION ALL
                SELECT 'unique_attendees_match',count(*) FILTER(WHERE v.unique_attendees<>coalesce(a.n,0))
                  FROM pbl3.v_program_cost v LEFT JOIN att a USING(program_id)
                UNION ALL
                SELECT 'zero_satisfied_is_null',count(*) FROM pbl3.v_program_cost
                 WHERE satisfied_attendees=0 AND cost_per_satisfied IS NOT NULL
                UNION ALL
                SELECT 'zero_returning_is_null',count(*) FROM pbl3.v_program_cost
                 WHERE returning_attendees=0 AND cost_per_returning IS NOT NULL
                UNION ALL
                SELECT 'participant_duplicates',count(*) FROM (
                    SELECT session_id,student_no FROM pbl3.program_participant
                    GROUP BY session_id,student_no HAVING count(*)>1) d
                """, 'budget_validation.csv')
            if checks.violations.astype(int).sum():
                raise RuntimeError('Budget validation failed')
            export(conn, "SELECT status,count(*) AS rows,sum(amount) AS amount FROM pbl3.expenditure GROUP BY status ORDER BY status",
                   'budget_expenditure_status.csv')
            export(conn, "SELECT * FROM pbl3.generation_meta", 'generation_metadata.csv')
            export(conn, """SELECT 'students' AS item,count(*) AS rows FROM pbl3.student
                UNION ALL SELECT 'programs',count(*) FROM pbl3.program
                UNION ALL SELECT 'sessions',count(*) FROM pbl3.program_session
                UNION ALL SELECT 'completed_sessions',count(*) FROM pbl3.program_session WHERE session_status='COMPLETED'
                UNION ALL SELECT 'candidates',count(*) FROM pbl3.mv_candidate
                UNION ALL SELECT 'participants',count(*) FROM pbl3.program_participant
                UNION ALL SELECT 'attended',count(*) FROM pbl3.program_participant WHERE attendance_status='ATTENDED'
                UNION ALL SELECT 'survey_responses',count(*) FROM pbl3.survey_response
                UNION ALL SELECT 'valid_responses',count(*) FROM pbl3.fn_survey_quality('{}','pbl3') WHERE is_latest AND is_valid
                """, 'dataset_counts.csv')
            # Truth is exported separately for a future scoring task; never joined to features.
            export(conn, "SELECT reg_class_conflict,reg_near_exam,reg_cross_campus,reg_prev_content,reg_session_fatigue,att_class_conflict,att_near_exam,att_cross_campus FROM pbl3_truth.coef",
                   'participation_truth_reference_only.csv')
            protocol = {
                'dataset': 'repository deterministic synthetic generator v2',
                'asof': '2026-11-23', 'postgres_version': conn.info.server_version,
                'isolation': 'fresh cluster and new database; existing DBs never connected',
                'extraction_read_only': conn.execute('SHOW transaction_read_only').fetchone()[0],
                'integrity_sql': '13_pbl3_verify.sql passed',
                'existing_reset_scripts_executed': False,
                'source_manifest': 'sources/source_manifest.json',
                'responses': len(responses), 'categories': len(categories), 'programs': len(budget),
                'note': 'Synthetic student identifiers are exported solely to reproduce the original hash split and clustered bootstrap.',
            }
            conn.rollback()
        files = {f.name: hashlib.sha256(f.read_bytes()).hexdigest()
                 for f in sorted(DATA.glob('*.csv'))}
        protocol['data_sha256'] = files
        (DATA / 'extraction_protocol.json').write_text(json.dumps(protocol,ensure_ascii=False,indent=2),encoding='utf-8')
        print('Export complete. Existing databases were not accessed.', flush=True)
    finally:
        if started:
            if server is not None and server.poll() is None:
                run('pg_ctl', '-D', cluster, '-m', 'fast', '-w', 'stop')
                server.wait(timeout=20)
                print('Isolated PostgreSQL stopped.', flush=True)
        if server_log is not None:
            server_log.close()


if __name__ == '__main__':
    main()
