"""Real PostgreSQL integration tests. Never run against an unmarked database.

Set SURVEY_TEST_DATABASE_URL to a separate *_test DB with mission 2 + extension + demo seed.
"""
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pandas as pd
import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
import pytest

from analysis.db import QualityConfig, behavior_groups, load_analysis

UTC=timezone.utc
AT=datetime(2025,10,1,6,tzinfo=UTC)
NORMAL=[5,4,3,4,5,2,4,3,5,4]


def quality(conn,config=None):
    return {r['response_id']:r for r in conn.execute('SELECT * FROM analytics.fn_survey_quality(%s)',(Jsonb(config or {}),))}


def summary(conn,pid,config=None):
    return conn.execute('SELECT * FROM analytics.fn_survey_summary(%s) WHERE program_id=%s',(Jsonb(config or {}),pid)).fetchone()


def test_fast_slow_varied_missing(conn,sample):
    q=quality(conn); fast,slow,normal,missing=[q[i] for i in sample['ids']]
    assert fast['response_type']=='빠른 응답 + 동일 점수 반복'
    assert fast['quality_score']==25 and fast['is_suspicious']
    assert slow['response_type']=='동일 점수 반복 의심'
    assert slow['quality_score']==85 and not slow['is_suspicious']
    assert normal['response_type']=='정상 범위 응답' and normal['quality_score']==100
    assert normal['score_variance']>0 and fast['score_variance']==0
    assert missing['response_type']=='분석 정보 부족' and missing['quality_score'] is None
    assert '실제 만족일 수 있음' in slow['reasons']
    assert fast['seconds_per_question']==.5
    assert fast['survey_median_seconds']==65
    assert fast['survey_mean_seconds']==55
    assert fast['time_percentile']==0 and slow['time_percentile']==1


def test_latest_completed_and_manual_means(conn,sample):
    q=quality(conn)
    assert not q[sample['draft']]['is_valid']
    assert not q[sample['old']]['is_latest']
    assert q[sample['ids'][0]]['is_latest']
    s=summary(conn,sample['pid'])
    assert s['response_count']==4 and s['suspicious_count']==1 and s['unknown_count']==1
    assert s['original_mean']==pytest.approx(4.475)
    assert s['filtered_mean']==pytest.approx(4.3)
    assert s['weighted_mean']==pytest.approx(13.4/3.1)


def test_small_cohort_relative_not_forced(conn,sample):
    fast=quality(conn,{'speed_mode':'relative'})[sample['ids'][0]]
    assert not fast['relative_fast'] and fast['quality_score'] is None
    assert fast['response_type']=='분석 정보 부족'
    assert '표본 부족' in fast['reasons']


def test_relative_speed_and_ties(conn,sample):
    for i in range(4,14): sample['respond'](i,NORMAL,100)
    first=quality(conn,{'speed_mode':'relative'})[sample['ids'][0]]
    assert first['relative_fast'] and first['is_suspicious']
    assert first['cohort_count']==13
    tied=[r['time_percentile'] for r in quality(conn).values() if r['survey_id']==sample['sid'] and r['duration_seconds']==100]
    assert len(set(tied))==1


def test_sensitivity_and_no_suspects(conn,sample):
    s=summary(conn,sample['pid'],{'suspicious_below':0})
    assert s['suspicious_count']==0 and s['filtered_mean']==s['original_mean']
    slow=quality(conn,{'straight_penalty':40})[sample['ids'][1]]
    assert slow['quality_score']==60 and slow['is_suspicious']
    fast=quality(conn,{'absolute_seconds':.4})[sample['ids'][0]]
    assert not fast['is_fast'] and fast['quality_score']==85


def test_fast_varied_score(conn,sample):
    rid=sample['respond'](5,NORMAL,3)
    q=quality(conn)[rid]
    assert q['quality_score']==60 and q['response_type']=='빠른 응답 의심'


def test_all_excluded_and_zero_weight_are_null(conn,sample):
    pid=sample['program']('all excluded')
    sid=conn.execute("INSERT INTO survey(program_id,survey_name,start_date,end_date) VALUES (%s,'only fast',%s,%s) RETURNING survey_id",(pid,AT.date(),AT.date())).fetchone()['survey_id']
    conn.execute('''INSERT INTO survey_question(survey_id,category_code,display_order,question_text,question_type,scale_max)
        SELECT %s,category_code,display_order,question_text,question_type,scale_max
        FROM survey_question WHERE survey_id=%s''',(sid,sample['sid']))
    rid=conn.execute('INSERT INTO survey_response(survey_id,student_no,responded_at) VALUES (%s,%s,%s) RETURNING response_id',(sid,sample['students'][0],AT)).fetchone()['response_id']
    conn.execute('INSERT INTO survey_response_detail SELECT %s,question_id,5,NULL FROM survey_question WHERE survey_id=%s',(rid,sid))
    conn.execute('INSERT INTO analytics.survey_response_observation VALUES (%s,%s,NULL)',(rid,AT-timedelta(seconds=1)))
    conn.execute('UPDATE survey_response SET is_completed=true WHERE response_id=%s',(rid,))
    s=summary(conn,pid,{'fast_penalty':100})
    assert s['original_mean']==5 and s['response_count']==1
    assert s['filtered_mean'] is None and s['weighted_mean'] is None


def test_empty_program_and_too_few_questions(conn,sample):
    pid=sample['program']('empty')
    s=summary(conn,pid)
    assert s['response_count']==0 and s['original_mean'] is None and s['filtered_mean'] is None
    r=quality(conn,{'min_questions':11})[sample['ids'][0]]
    assert r['response_type']=='분석 정보 부족' and not r['is_straight']


@pytest.mark.parametrize('config',[{'absolute_seconds':0},{'relative_fraction':2},{'speed_mode':'garbage'},
    {'fast_penalty':-1},{'min_questions':1},{'suspicious_below':None},{'typo_seconds':1}])
def test_invalid_config_rejected(conn,config):
    with pytest.raises(psycopg.errors.InvalidParameterValue): quality(conn,config)


def test_timing_both_write_directions(conn,sample):
    rid=sample['ids'][0]
    with conn.transaction(force_rollback=True):
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute('UPDATE analytics.survey_response_observation SET started_at=%s WHERE response_id=%s',(AT+timedelta(seconds=1),rid))
    with conn.transaction(force_rollback=True):
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute('UPDATE survey_response SET responded_at=%s WHERE response_id=%s',(AT-timedelta(seconds=6),rid))




def test_dashboard_db_aggregate_consistency(conn,monkeypatch):
    monkeypatch.setenv('SURVEY_DATABASE_URL',os.environ['SURVEY_TEST_DATABASE_URL'])
    s,r,_=load_analysis(QualityConfig(),'synthetic',datetime(2026,11,23,tzinfo=UTC))
    valid=r[r.is_latest & r.is_valid]
    assert not valid.empty
    assert s.response_count.sum()==len(valid)
    for row in s.itertuples():
        sub=valid[valid.program_id==row.program_id]
        if sub.empty: continue
        assert row.original_mean==pytest.approx(sub.score_sum.sum()/sub.score_count.sum())
        assert row.suspicious_count==sub.is_suspicious.sum()
        kept=sub[~sub.is_suspicious]
        if not kept.empty: assert row.filtered_mean==pytest.approx(kept.score_sum.sum()/kept.score_count.sum())
    groups=behavior_groups(valid)
    assert groups.iloc[0]['관찰 완료']==valid.rejoined.notna().sum()


def test_core_loader_does_not_use_optional_extension(conn,monkeypatch):
    monkeypatch.setenv('SURVEY_DATABASE_URL',os.environ['SURVEY_TEST_DATABASE_URL'])
    s,r,_=load_analysis(QualityConfig(),'synthetic')
    assert s.attendance_count.isna().all()
    assert r.rejoined.isna().all()
    assert set(r.followup_status)=={'출석 연계 대기'}
    # Core SQL definitions have no direct references to the shared attendance structures.
    definition=conn.execute("SELECT pg_get_viewdef('analytics.v_survey_insight_program'::regclass) AS sql").fetchone()['sql']
    assert 'program_attendance' not in definition and 'v_attendance_event' not in definition


def test_reader_permissions(conn):
    conn.execute('SET LOCAL ROLE analytics_reader')
    assert conn.execute("SELECT count(*) AS n FROM analytics.fn_survey_quality('{}','synthetic')").fetchone()['n']>0
    assert conn.execute("SELECT count(*) AS n FROM analytics.fn_survey_summary('{}','synthetic')").fetchone()['n']==24
    assert conn.execute("SELECT count(*) AS n FROM analytics.v_survey_insight_category").fetchone()['n']>0
    for table in ['public.student','analytics.survey_response_observation','analytics.survey_insight_setting']:
        assert not conn.execute('SELECT has_table_privilege(current_user,%s,\'SELECT\') AS ok',(table,)).fetchone()['ok']


def test_original_seed_results_preserved(conn):
    r=conn.execute("SELECT count(*) AS n FROM analytics.v_survey_response_final f JOIN survey s USING(survey_id) WHERE s.survey_name LIKE 'SEED %'").fetchone()
    assert r['n']==128
    assert conn.execute('''SELECT count(*) AS n FROM analytics.survey_response_observation o
       JOIN survey_response r USING(response_id) JOIN survey s USING(survey_id)
       WHERE s.survey_name LIKE 'SEED %' ''').fetchone()['n']==0




