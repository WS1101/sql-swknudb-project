"""Read-only dashboard access; all metrics are calculated by PostgreSQL."""
from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone

import pandas as pd
import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb


@dataclass(frozen=True)
class QualityConfig:
    absolute_seconds: float = 2.0
    relative_fraction: float = .25
    relative_percentile: float = .1
    min_cohort: int = 10
    min_questions: int = 4
    speed_mode: str = 'either'
    fast_penalty: int = 40
    straight_penalty: int = 15
    interaction_penalty: int = 20
    suspicious_below: int = 70


def connect(*, readonly=True):
    # DSN/password never appear in logs, UI, CLI arguments, or committed files.
    dsn = os.environ.get('SURVEY_DATABASE_URL')
    if not dsn:
        raise RuntimeError('SURVEY_DATABASE_URL 환경변수가 필요합니다.')
    conn = psycopg.connect(dsn, connect_timeout=5, row_factory=dict_row)
    conn.read_only = readonly
    return conn


def frame(conn, sql, params=()):
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        return pd.DataFrame(rows, columns=[c.name for c in cur.description])


def load_analysis(config: QualityConfig, source: str, asof: datetime | None = None,
                  *, include_participation=False):
    """Default path only reads survey objects. Optional linking is explicit."""
    cfg = Jsonb(asdict(config))
    with connect() as conn:
        # One repeatable snapshot for cards, details, category and follow-up.
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        conn.execute("SET LOCAL statement_timeout='30s'")
        summary = frame(conn, 'SELECT * FROM analytics.fn_survey_summary(%s,%s) ORDER BY program_id', (cfg, source))
        responses = frame(conn, 'SELECT * FROM analytics.fn_survey_quality(%s,%s)', (cfg, source))
        # Stable Python result shape for optional reports/models; never implies nonattendance.
        responses['followup_status'] = '출석 연계 대기'
        responses['rejoined'] = None
        responses['opportunity_count'] = None
        if include_participation:
            installed=conn.execute("SELECT to_regclass('analytics.survey_participation_setting') IS NOT NULL AS ok").fetchone()['ok']
            if installed:
                followup=frame(conn,'SELECT * FROM analytics.fn_survey_followup(%s,%s)',
                               (asof or datetime.now(timezone.utc),source))
                responses=responses.drop(columns=['followup_status','rejoined','opportunity_count']).merge(
                    followup,on='response_id',how='left',validate='one_to_one')
                attendance=frame(conn,'''SELECT program_id,attendance_count
                    FROM analytics.v_program_attendance_count WHERE data_source=%s''',(source,))
                summary=summary.drop(columns=['attendance_count']).merge(
                    attendance,on='program_id',how='left',validate='one_to_one')
        categories = frame(conn, '''SELECT * FROM analytics.v_survey_insight_category
            WHERE data_source=%s''', (source,))
    # Normalize PostgreSQL numeric columns for charts (Decimal -> float).
    for df in (summary, responses, categories):
        for col in df.columns:
            if col in {'score_sum', 'score_count', 'weighted_mean'}:
                df[col] = pd.to_numeric(df[col])
    return summary, responses, categories


def sensitivity(config, source):
    """Compare speed modes and penalties without persisting configuration."""
    rows = []
    with connect() as conn:
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        for seconds in (1.0, 2.0, 3.0):
            for mode in ('absolute', 'relative', 'either', 'both'):
                cfg = asdict(config) | {'absolute_seconds': seconds, 'speed_mode': mode}
                df = frame(conn, 'SELECT * FROM analytics.fn_survey_summary(%s,%s)', (Jsonb(cfg), source))
                df['absolute_seconds'], df['speed_mode'] = seconds, mode
                rows.append(df)
    return pd.concat(rows, ignore_index=True).sort_values(['absolute_seconds','speed_mode','program_id'])


def behavior_groups(df):
    """Response-level comparisons. Unknown/censored outcomes never enter rates."""
    masks = {
        '전체': pd.Series(True, index=df.index),
        '만족도 4점 이상': df.mean_score >= 4,
        '만족도 3점 미만': df.mean_score < 3,
        '품질 85점 이상': df.quality_score >= 85,
        '빠른 응답': df.is_fast,
        '동일 점수 반복': df.is_straight,
        '의심 응답 제외': ~df.is_suspicious,
    }
    rows = []
    for name, mask in masks.items():
        sub = df[mask]
        obs = sub[sub.followup_status == '관찰 완료']
        rows.append({'집단': name, '응답수': len(sub), '평균 만족도': sub.mean_score.mean(),
                     '관찰 완료': len(obs), '재참여율': obs.rejoined.astype(float).mean()})
    return pd.DataFrame(rows)


def satisfaction_behavior(df):
    rows=[]
    bands={'4점 이상':df.mean_score>=4,'3점 이상 4점 미만':(df.mean_score>=3)&(df.mean_score<4),'3점 미만':df.mean_score<3}
    for policy in ('원본','의심 응답 제외'):
        for band,mask in bands.items():
            sub=df[mask & (True if policy=='원본' else ~df.is_suspicious)]
            obs=sub[sub.followup_status=='관찰 완료']
            rows.append({'집계':policy,'만족도 구간':band,'응답수':len(sub),'관찰 완료':len(obs),
                         '재참여율':obs.rejoined.astype(float).mean()})
    return pd.DataFrame(rows)
