"""Optional extension tests: prepare 06 and --with-participation in a separate *_test DB."""
import os
from datetime import datetime, timedelta, timezone
import pandas as pd
import pytest
from analysis.db import QualityConfig,load_analysis

UTC=timezone.utc
AT=datetime(2025,10,1,6,tzinfo=UTC)

@pytest.fixture(autouse=True)
def require_participation(conn):
    if not conn.execute("SELECT to_regclass('analytics.survey_participation_setting') AS name").fetchone()['name']:
        pytest.skip('06_survey_participation.sql is required for optional tests')


@pytest.fixture
def mapped(conn):
    # Simulate Wu-jin changing the storage design to event/session rows.
    # No production/common table is created or modified by the extension itself.
    conn.execute('CREATE TABLE analytics.test_attendance_event(student_no VARCHAR(20),program_id INT,attended_at TIMESTAMPTZ)')
    conn.execute('CREATE TABLE analytics.test_program_opportunity(student_no VARCHAR(20),program_id INT,offered_at TIMESTAMPTZ,scheduled_at TIMESTAMPTZ)')
    conn.execute('CREATE OR REPLACE VIEW analytics.v_attendance_event AS SELECT * FROM analytics.test_attendance_event')
    conn.execute('CREATE OR REPLACE VIEW analytics.v_program_opportunity AS SELECT * FROM analytics.test_program_opportunity')
    conn.execute('UPDATE analytics.survey_participation_setting SET attendance_connected=TRUE,opportunity_connected=TRUE')


def follow(conn,asof=AT+timedelta(days=100)):
    return {r['response_id']:r for r in conn.execute('SELECT * FROM analytics.fn_survey_followup(%s)',(asof,))}


def test_link_flags_and_unknown_opportunities(conn,sample,mapped):
    conn.execute('UPDATE analytics.survey_participation_setting SET attendance_connected=FALSE,opportunity_connected=FALSE')
    r=follow(conn)[sample['ids'][0]]
    assert r['followup_status']=='출석 연계 대기' and r['rejoined'] is None
    conn.execute('UPDATE analytics.survey_participation_setting SET attendance_connected=TRUE')
    r=follow(conn)[sample['ids'][0]]
    assert r['followup_status']=='참여 기회 연계 대기' and r['rejoined'] is None
    assert conn.execute('SELECT attendance_count FROM analytics.v_program_attendance_count WHERE program_id=%s',(sample['pid'],)).fetchone()['attendance_count']==0


def test_session_rows_count_students_once_and_window_rules(conn,sample,mapped):
    future=sample['program']('future session',AT+timedelta(days=20))
    past=sample['program']('past session',AT-timedelta(days=20))
    late=sample['program']('after window',AT+timedelta(days=91))
    for no,pid,at in [
        (sample['students'][0],future,AT+timedelta(days=20)),
        (sample['students'][0],future,AT+timedelta(days=21)),
        (sample['students'][0],future,AT+timedelta(days=21)),
        (sample['students'][1],past,AT-timedelta(days=1)),
        (sample['students'][1],late,AT+timedelta(days=91)),
        (sample['students'][2],sample['pid'],AT+timedelta(days=1)),
        (sample['students'][2],future,AT),
        (sample['students'][3],future,AT+timedelta(days=90))]:
        conn.execute('INSERT INTO analytics.test_attendance_event VALUES (%s,%s,%s)',(no,pid,at))
    conn.execute('INSERT INTO analytics.test_program_opportunity VALUES (%s,%s,%s,%s)',
                 (sample['students'][1],future,AT,AT+timedelta(days=20)))
    assert follow(conn)[sample['ids'][0]]['followup_status']=='기록 범위 불명'
    conn.execute("INSERT INTO analytics.participation_coverage VALUES ('existing',%s,%s,'test')",
                 (AT-timedelta(days=2),AT+timedelta(days=100)))
    f=follow(conn)
    assert f[sample['ids'][0]]['rejoined'] is True
    assert f[sample['ids'][0]]['opportunity_count']==1
    assert f[sample['ids'][1]]['rejoined'] is False
    assert f[sample['ids'][2]]['followup_status']=='후속 기회 없음'
    assert f[sample['ids'][3]]['rejoined'] is True
    assert follow(conn,AT+timedelta(days=30))[sample['ids'][0]]['rejoined'] is None
    assert conn.execute('SELECT attendance_count FROM analytics.v_program_attendance_count WHERE program_id=%s',(future,)).fetchone()['attendance_count']==3


def test_reapply_preserves_custom_mapping_and_setting(conn,mapped):
    from pathlib import Path
    original=conn.execute("SELECT pg_get_viewdef('analytics.v_attendance_event'::regclass) AS definition").fetchone()['definition']
    # The transaction wrapper is removed here so the test can roll its own fixture back.
    sql=Path('schema/11_survey_participation_link.sql').read_text(encoding='utf8')
    sql=sql.replace('BEGIN;\n','',1).removesuffix('COMMIT;\n')
    conn.execute(sql)
    current=conn.execute("SELECT pg_get_viewdef('analytics.v_attendance_event'::regclass) AS definition").fetchone()['definition']
    assert current==original
    assert conn.execute('SELECT attendance_connected FROM analytics.survey_participation_setting').fetchone()['attendance_connected']


def test_reader_optional_access(conn):
    conn.execute('SET LOCAL ROLE analytics_reader')
    assert conn.execute("SELECT count(*) AS n FROM analytics.fn_survey_followup(now(),'synthetic')").fetchone()['n']>0
    assert conn.execute("SELECT count(*) AS n FROM analytics.v_program_attendance_count").fetchone()['n']>0


def test_extended_dashboard_is_separate_and_runs(conn,monkeypatch):
    from streamlit.testing.v1 import AppTest
    monkeypatch.setenv('SURVEY_DATABASE_URL',os.environ['SURVEY_TEST_DATABASE_URL'])
    app=AppTest.from_file('analysis/app_extended.py',default_timeout=60).run()
    assert not app.exception and len(app.tabs)==5
    app.sidebar.selectbox[0].select('합성 시연 데이터').run()
    assert not app.exception and len(app.date_input)==1

def test_optional_model_split_and_metrics(conn,monkeypatch):
    pytest.importorskip('sklearn')
    from analysis.model import evaluate
    monkeypatch.setenv('SURVEY_DATABASE_URL',os.environ['SURVEY_TEST_DATABASE_URL'])
    _,r,c=load_analysis(QualityConfig(),'synthetic',datetime(2026,11,23,tzinfo=UTC),include_participation=True)
    result=evaluate(r,c)
    assert result['status']=='evaluated' and result['student_overlap']==0
    assert pd.Timestamp(result['latest_training_label_time'])<=pd.Timestamp(result['cutoff'])
    assert pd.Timestamp(result['earliest_test_time'])>=pd.Timestamp(result['cutoff'])
    for m in result['metrics']:
        for key in ['accuracy','precision','recall','f1','roc_auc']: assert 0<=m[key]<=1
    assert len(result['importance'])==4
    for i in result['importance']:
        assert -1<=i['delta_plus_0.5']<=1 and -1<=i['delta_minus_0.5']<=1


def test_model_unavailable_on_original_data(conn,monkeypatch):
    pytest.importorskip('sklearn')
    from analysis.model import evaluate
    monkeypatch.setenv('SURVEY_DATABASE_URL',os.environ['SURVEY_TEST_DATABASE_URL'])
    _,r,c=load_analysis(QualityConfig(),'existing',datetime(2026,11,23,tzinfo=UTC),include_participation=True)
    assert evaluate(r,c)['status']=='평가 불가'


