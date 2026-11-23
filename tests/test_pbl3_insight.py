"""Integration checks for the team's pbl3 dataset; requires a dedicated *_test DB."""
import os
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import psycopg
from psycopg.conninfo import conninfo_to_dict
import pytest

from analysis.db import QualityConfig, frame, load_analysis, sensitivity
from analysis.model import evaluate


ASOF = datetime(2026, 11, 23, 23, 59, 59, tzinfo=timezone.utc)


@pytest.fixture(scope='module')
def team():
    dsn = os.environ.get('SURVEY_TEST_DATABASE_URL')
    if not dsn:
        pytest.skip('SURVEY_TEST_DATABASE_URL not configured: real DB tests not run')
    assert conninfo_to_dict(dsn)['dbname'].endswith('_test')
    with pytest.MonkeyPatch.context() as patch:
        patch.setenv('SURVEY_DATABASE_URL', dsn)
        yield load_analysis(QualityConfig(), 'pbl3', ASOF, include_participation=True)


def test_team_response_selection_and_optional_text(conn, team):
    summary, responses, categories = team
    counts = conn.execute('''SELECT count(*) AS total,
        count(*) FILTER (WHERE is_completed) AS completed FROM pbl3.survey_response''').fetchone()
    assert len(responses) == counts['total'] > 0
    valid = responses[responses.is_latest & responses.is_valid]
    assert len(valid) == counts['completed'] == summary.response_count.sum()
    assert not valid.quality_score.isna().any()
    assert len(summary) == conn.execute('SELECT count(*) AS n FROM pbl3.program').fetchone()['n']
    assert set(categories.category_code) == {'CONTENT', 'INSTRUCTOR', 'OPERATION', 'FACILITY', 'SCHEDULE'}
    # Optional blank text must not invalidate a completed five-score response.
    blank_text = conn.execute('''SELECT r.response_id FROM pbl3.survey_response r
        WHERE r.is_completed AND NOT EXISTS (
            SELECT 1 FROM pbl3.survey_response_detail d
            JOIN pbl3.survey_question q USING(question_id)
            WHERE d.response_id=r.response_id AND q.question_type='TEXT') LIMIT 1''').fetchone()
    assert blank_text is not None
    assert responses.set_index('response_id').loc[blank_text['response_id'], 'is_valid']


def test_program_means_match_raw_answers(conn, team):
    summary, responses, _ = team
    raw = frame(conn, '''SELECT r.response_id, s.program_id, d.score
        FROM pbl3.survey_response r JOIN pbl3.survey s USING(survey_id)
        JOIN pbl3.survey_response_detail d USING(response_id)
        JOIN pbl3.survey_question q USING(question_id)
        WHERE r.is_completed AND q.question_type='SCALE' ''')
    quality = responses.set_index('response_id')
    raw['suspicious'] = raw.response_id.map(quality.is_suspicious)
    raw['weight'] = raw.response_id.map(quality.quality_score).fillna(100) / 100
    raw['weighted_score'] = raw.score * raw.weight
    for row in summary.itertuples():
        answers = raw[raw.program_id == row.program_id]
        if answers.empty:
            assert pd.isna(row.original_mean)
            continue
        assert row.original_mean == pytest.approx(answers.score.mean())
        assert row.filtered_mean == pytest.approx(answers.loc[~answers.suspicious, 'score'].mean())
        assert row.weighted_mean == pytest.approx(answers.weighted_score.sum() / answers.weight.sum())


def test_attendance_counts_students_once(conn, team):
    summary, _, _ = team
    actual = frame(conn, '''SELECT s.program_id, count(DISTINCT pp.student_no) AS n
        FROM pbl3.program_participant pp JOIN pbl3.program_session s USING(session_id)
        WHERE pp.attendance_status='ATTENDED' GROUP BY s.program_id''').set_index('program_id').n
    assert actual.sum() < conn.execute("SELECT count(*) AS n FROM pbl3.program_participant WHERE attendance_status='ATTENDED'").fetchone()['n']
    for row in summary.itertuples():
        assert row.attendance_count == actual.get(row.program_id, 0)


@pytest.mark.parametrize('include_same_program', [True, False])
def test_followup_matches_independent_event_windows(conn, team, include_same_program):
    _, responses, _ = team
    # Recompute the label directly from event rows, without the follow-up SQL CTE.
    events = frame(conn, '''SELECT student_no, program_id, attended,
        (session_date + start_time) AT TIME ZONE 'Asia/Seoul' AS scheduled_at
        FROM pbl3.mv_candidate WHERE session_status='COMPLETED' ''')
    groups = {student: group for student, group in events.groupby('student_no')}
    coverage = conn.execute("SELECT * FROM pbl3.participation_coverage WHERE data_source='pbl3'").fetchone()
    actual = frame(conn, 'SELECT * FROM pbl3.fn_survey_followup(%s,%s,%s)',
                   (ASOF, 'pbl3', include_same_program)).set_index('response_id')
    completed = responses[responses.is_latest & responses.is_valid]
    assert set(actual.index) == set(completed.response_id)
    for row in completed.itertuples():
        student_events = groups[row.student_no]
        horizon = row.submitted_at + pd.Timedelta(days=90)
        mask = ((student_events.scheduled_at > row.submitted_at)
                & (student_events.scheduled_at <= min(horizon, ASOF)))
        if not include_same_program:
            mask &= student_events.program_id != row.program_id
        opportunities = int(mask.sum())
        if row.submitted_at < coverage['observed_from']:
            state = '기록 범위 불명'
        elif min(coverage['observed_through'], ASOF) < horizon:
            state = '관찰 기간 부족'
        elif opportunities == 0:
            state = '후속 기회 없음'
        else:
            state = '관찰 완료'
        result = actual.loc[row.response_id]
        assert result.followup_status == state
        assert result.opportunity_count == opportunities
        if state == '관찰 완료':
            assert result.rejoined == bool(student_events.loc[mask, 'attended'].any())
        else:
            assert pd.isna(result.rejoined)


def test_sensitivity_preserves_original_means(team):
    summary, _, _ = team
    result = sensitivity(QualityConfig(), 'pbl3')
    assert len(result) == 12 * len(summary)
    baseline = summary.set_index('program_id').original_mean
    assert np.allclose(result.original_mean, result.program_id.map(baseline), equal_nan=True)
    absolute = result[result.speed_mode == 'absolute']
    counts = absolute.pivot(index='program_id', columns='absolute_seconds', values='suspicious_count')
    assert (counts[1.0] <= counts[2.0]).all() and (counts[2.0] <= counts[3.0]).all()


def test_reader_can_analyze_without_generator_truth(conn):
    conn.execute('SET LOCAL ROLE analytics_reader')
    assert conn.execute("SELECT count(*) AS n FROM pbl3.fn_survey_quality('{}','pbl3')").fetchone()['n'] > 0
    assert conn.execute('SELECT count(*) AS n FROM pbl3.fn_survey_followup(%s)', (ASOF,)).fetchone()['n'] > 0
    assert not conn.execute("SELECT has_schema_privilege(current_user,'pbl3_truth','USAGE') AS ok").fetchone()['ok']
    with conn.transaction(force_rollback=True):
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute('SELECT engagement FROM pbl3_truth.student_latent LIMIT 1')


def test_model_separates_students_and_mature_labels(team):
    _, responses, categories = team
    result = evaluate(responses, categories)
    assert result['status'] == 'evaluated'
    assert result['student_overlap'] == 0
    assert pd.Timestamp(result['latest_training_label_time']) <= pd.Timestamp(result['cutoff'])
    assert pd.Timestamp(result['earliest_test_time']) >= pd.Timestamp(result['cutoff'])
    assert {item['category_code'] for item in result['importance']} == set(categories.category_code)
    for metric in result['metrics']:
        assert metric['test_n'] == result['test_n']
        for name in ('accuracy', 'precision', 'recall', 'f1', 'roc_auc'):
            assert 0 <= metric[name] <= 1
    # Engagement can induce an operation association; zero is not a correctness target.
    operation = next(item for item in result['importance'] if item['category_code'] == 'OPERATION')
    assert np.isfinite(operation['standardized_coefficient'])


@pytest.mark.parametrize(('path', 'tabs'), [('analysis/app.py', 3), ('analysis/app_extended.py', 5)])
def test_team_dashboard_selection_and_controls(team, path, tabs):
    from streamlit.testing.v1 import AppTest
    app = AppTest.from_file(Path(__file__).resolve().parents[1] / path, default_timeout=60).run()
    assert not app.exception
    app.sidebar.selectbox[0].select('팀 공통 데이터 (pbl3)').run()
    assert not app.exception and not app.error and len(app.tabs) == tabs
    if path.endswith('app_extended.py'):
        app.date_input[0].set_value(ASOF.date()).run()
        assert any('적극성' in caption.value for caption in app.caption)
        assert any('같은 프로그램' in block.value for block in app.markdown)
        next(button for button in app.button if button.label == '전체 프로그램 모델 평가').click().run()
        assert not app.exception and not app.error
    app.sidebar.slider[0].set_value(1.0).run()
    assert not app.exception and not app.error
