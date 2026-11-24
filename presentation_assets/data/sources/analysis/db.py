"""Read-only dashboard access; all metrics are calculated by PostgreSQL."""
from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone

import pandas as pd
import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb


DATA_SOURCES = {
    '기존 DB 데이터': 'existing',
    '팀 공통 데이터 (pbl3)': 'pbl3',
    '합성 시연 데이터': 'synthetic',
}
PBL3_FOLLOWUP_DEFINITION = '설문 제출 이후 90일 이내의 후속 회차 출석이며, 같은 프로그램의 다음 회차도 포함합니다.'
PBL3_INTERPRETATION_NOTE = (
    '팀 공통 합성 데이터에서는 학생 적극성이 모든 문항분류 점수와 신청·출석에 함께 반영됩니다. '
    '생성기의 운영 직접효과가 0이어도 모델의 운영 계수는 0이 아닐 수 있습니다(예: 0.09). '
    '이는 적극성 등 공통 요인의 영향을 포함한 예측 연관성이며 운영 개선의 인과효과가 아닙니다.'
)


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


def schema_for(source: str) -> str:
    """Use the matching pbl3 functions for the team-provided dataset."""
    return 'pbl3' if source == 'pbl3' else 'analytics'


def load_analysis(config: QualityConfig, source: str, asof: datetime | None = None,
                  *, include_participation=False):
    """Default path only reads survey objects. Optional linking is explicit."""
    cfg = Jsonb(asdict(config))
    s = schema_for(source)
    with connect() as conn:
        # One repeatable snapshot for cards, details, category and follow-up.
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        conn.execute("SET LOCAL statement_timeout='30s'")
        summary = frame(conn, f'SELECT * FROM {s}.fn_survey_summary(%s,%s) ORDER BY program_id', (cfg, source))
        responses = frame(conn, f'SELECT * FROM {s}.fn_survey_quality(%s,%s)', (cfg, source))
        # Stable Python result shape for optional reports/models; never implies nonattendance.
        responses['followup_status'] = '출석 연계 대기'
        responses['rejoined'] = None
        responses['opportunity_count'] = None
        if include_participation:
            installed=conn.execute(f"SELECT to_regclass('{s}.survey_participation_setting') IS NOT NULL AS ok").fetchone()['ok']
            if installed:
                followup=frame(conn,f'SELECT * FROM {s}.fn_survey_followup(%s,%s)',
                               (asof or datetime.now(timezone.utc),source))
                responses=responses.drop(columns=['followup_status','rejoined','opportunity_count']).merge(
                    followup,on='response_id',how='left',validate='one_to_one')
                attendance=frame(conn,f'''SELECT program_id,attendance_count
                    FROM {s}.v_program_attendance_count WHERE data_source=%s''',(source,))
                summary=summary.drop(columns=['attendance_count']).merge(
                    attendance,on='program_id',how='left',validate='one_to_one')
        categories = frame(conn, f'''SELECT * FROM {s}.v_survey_insight_category
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
                df = frame(conn, f'SELECT * FROM {schema_for(source)}.fn_survey_summary(%s,%s)', (Jsonb(cfg), source))
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
