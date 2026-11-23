import os
from pathlib import Path

import pytest


def test_dashboard_controls_and_all_tabs(monkeypatch):
    dsn=os.environ.get('SURVEY_TEST_DATABASE_URL')
    if not dsn: pytest.skip('real PostgreSQL test URL required')
    from psycopg.conninfo import conninfo_to_dict
    assert conninfo_to_dict(dsn)['dbname'].endswith('_test')
    from streamlit.testing.v1 import AppTest
    monkeypatch.setenv('SURVEY_DATABASE_URL',dsn)
    app=AppTest.from_file(str(Path('analysis/app.py')),default_timeout=60).run()
    assert not app.exception
    assert len(app.tabs)==3
    assert not app.date_input
    # Original seed program #7 has no survey. Empty charts/metrics must still render.
    next(w for w in app.selectbox if w.label=='프로그램').select(7).run()
    assert not app.exception
    app.sidebar.selectbox[0].select('합성 시연 데이터').run()
    assert not app.exception
    assert len(app.metric)>=4
    app.sidebar.slider[0].set_value(1.0).run()
    assert not app.exception
    next(w for w in app.selectbox if w.label=='근거를 확인할 응답 유형').select('빠른 응답 + 동일 점수 반복').run()
    assert not app.exception
    next(w for w in app.button if w.label=='임계값 민감도 계산').click().run(timeout=120)
    assert not app.exception


def test_missing_database_shows_safe_error(monkeypatch):
    from streamlit.testing.v1 import AppTest
    monkeypatch.delenv('SURVEY_DATABASE_URL',raising=False)
    app=AppTest.from_file('analysis/app.py').run()
    assert not app.exception and len(app.error)==1
