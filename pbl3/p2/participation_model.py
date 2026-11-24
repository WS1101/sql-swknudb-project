"""2번 참여 저조 원인 분해와 시간대 추천 (서우진)

흐름
  1. pbl3.mv_candidate(회차 × 대상 학생)를 psql로 CSV 추출
  2. 신청 확률 / 출석 확률 로지스틱 회귀 학습
       - 검증: 2026-09-01 이전 회차로 학습 → 이후 회차의 신청 예측 (시간 분리)
       - 최종: 진행된 전체 회차로 다시 학습해 효과·분해·추천에 사용
  3. 회차별 요인 분해: "이 요인만 없었다면 신청이 몇 명 늘었을까"
  4. 후보 시간대(pbl3.mv_p2_whatif)별 예상 신청·출석 → 시간대 추천
  5. 결과를 pbl3.p2_* 테이블에 저장 (psql 사용, 파이썬 DB 드라이버 불필요)

실행:  bash pbl3/p2/run_participation.sh            (기본 DB: swknu_db)
       PBL3_DB=다른DB bash pbl3/p2/run_participation.sh

해석 주의: 계수는 "같은 조건에서 비교한 연관"이다. 가상 데이터에서는 생성기 정답
(pbl3_truth.coef)과 비교해 방법이 효과를 얼마나 복원하는지 확인한다.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score

TRAIN_UNTIL = '2026-09-01'

# 요인 이름 → 발표용 한글 이름
LABELS = {
    'class_conflict': '전공 수업 시간 겹침',
    'near_exam': '시험기간(±3일)',
    'vacation': '방학 중 진행',
    'fatigue': '회차 누적(회당)',
    'cross_campus': '다른 캠퍼스에서 진행',
    'is_online': '온라인 진행',
    'friday': '금요일',
    'weekend': '주말',
    'evening': '18시 이후 시작',
    'morning': '12시 이전 시작',
    'mileage': '마일리지(1점당)',
    'prev_attended': '직전 회차 출석',
    'prev_own_content_c': '직전 회차 본인 내용 만족도(3점 기준 1점당)',
    'prev_avg_content_c': '직전 회차 평균 내용 만족도(3.5점 기준 1점당)',
    'log_past_attended': '과거 참여 횟수(log)',
    'past_no_show_rate': '과거 노쇼 비율',
    'sms_opt_out': 'SMS 수신 거부',
}

# 요인 분해에 쓰는 "없앴을 때" 조작. 시간·일정으로 바꿀 수 있는 요인 위주
FACTORS = {
    'class_conflict': ('전공 수업 시간 겹침', lambda d: d.assign(class_conflict=0)),
    'near_exam':      ('시험기간',           lambda d: d.assign(near_exam=0)),
    'cross_campus':   ('다른 캠퍼스',         lambda d: d.assign(cross_campus=0)),
    'time_of_day':    ('요일·시간대',         lambda d: d.assign(friday=0, weekend=0, evening=0, morning=0)),
    'vacation':       ('방학',               lambda d: d.assign(vacation=0)),
    'fatigue':        ('회차 누적 피로',      lambda d: d.assign(fatigue=0)),
    'word_of_mouth':  ('직전 회차 평가(입소문)', lambda d: d.assign(prev_avg_content_c=0.0)),
}


# ---------------------------------------------------------------------------
# DB 입출력 (psql)
# ---------------------------------------------------------------------------
def psql(db: str, *args: str, input_text: str | None = None) -> str:
    cmd = ['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', db, *args]
    r = subprocess.run(cmd, input=input_text, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f'psql 실패: {" ".join(args)[:120]}\n{r.stderr}')
    return r.stdout


def export(db: str, sql: str, path: Path) -> pd.DataFrame:
    psql(db, '-c', f"\\copy ({sql}) TO '{path}' CSV HEADER")
    return pd.read_csv(path)


def sql_value(v) -> str:
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return 'NULL'
    if isinstance(v, (bool, np.bool_)):
        return 'TRUE' if v else 'FALSE'
    if isinstance(v, (int, np.integer)):
        return str(int(v))
    if isinstance(v, (float, np.floating)):
        return repr(round(float(v), 4))
    return "'" + str(v).replace("'", "''") + "'"


def insert_rows(table: str, cols: list[str], rows: list[tuple]) -> str:
    if not rows:
        return ''
    body = ',\n'.join('(' + ','.join(sql_value(v) for v in r) + ')' for r in rows)
    return f'INSERT INTO {table} ({",".join(cols)}) VALUES\n{body};\n'


# ---------------------------------------------------------------------------
# 특성 만들기
# ---------------------------------------------------------------------------
BOOL_COLS = ['registered', 'attended', 'class_conflict', 'cross_campus', 'near_exam', 'in_semester',
             'is_online', 'prev_attended', 'sms_opt_in_at', 'is_current',
             'actual_registered', 'actual_attended']


def to_bool(df: pd.DataFrame) -> pd.DataFrame:
    for c in BOOL_COLS:
        if c in df.columns:
            df[c] = df[c].map({'t': 1, 'f': 0, True: 1, False: 0})
    return df


def features(df: pd.DataFrame) -> pd.DataFrame:
    x = pd.DataFrame(index=df.index)
    x['class_conflict'] = df.class_conflict
    x['near_exam'] = df.near_exam
    x['vacation'] = 1 - df.in_semester
    x['fatigue'] = df.session_no - 1
    x['cross_campus'] = df.cross_campus
    x['is_online'] = df.is_online
    x['friday'] = (df.weekday_iso == 5).astype(int)
    x['weekend'] = (df.weekday_iso >= 6).astype(int)
    x['evening'] = (df.start_hour >= 18).astype(int)
    x['morning'] = (df.start_hour < 12).astype(int)
    x['mileage'] = df.mileage
    x['prev_attended'] = df.prev_attended
    # 직전 회차 응답이 있으면 본인 내용 점수, 없으면 0 (응답 안 한 출석자는 별도 표시)
    x['prev_own_content_c'] = (df.prev_own_content - 3).where(df.prev_attended == 1, 0).fillna(0)
    x['prev_attended_no_resp'] = ((df.prev_attended == 1) & df.prev_own_content.isna()).astype(int)
    x['prev_avg_content_c'] = (df.prev_session_avg_content - 3.5).fillna(0)
    x['log_past_attended'] = np.log1p(df.past_attended)
    x['past_no_show_rate'] = (df.past_no_show / df.past_registered.replace(0, np.nan)).fillna(0)
    x['no_history'] = (df.past_registered == 0).astype(int)
    x['sms_opt_out'] = 1 - df.sms_opt_in_at
    # 학생 집단·프로그램 고정효과 (원-핫)
    x = x.join(pd.get_dummies(df.grade_at.astype(int), prefix='grade', drop_first=True, dtype=int))
    x = x.join(pd.get_dummies(df.track_type + '_' + df.admission_type, prefix='grp', drop_first=True, dtype=int))
    x = x.join(pd.get_dummies(df.program_type_code + '_g' + df.grade_at.astype(int).astype(str),
                              prefix='tg', dtype=int))
    # 프로그램 고정효과: 주제 매력·홍보처럼 프로그램마다 다른 수준을 흡수
    #   (같은 시리즈라도 해마다 매력이 달라 시리즈 고정효과는 과적합됨 → 검증 오차 24명 vs 13명)
    x = x.join(pd.get_dummies(df.program_id, prefix='prog', dtype=int))
    return x.astype(float)


def align(x: pd.DataFrame, columns: list[str]) -> pd.DataFrame:
    return x.reindex(columns=columns, fill_value=0.0)


def fit(x: pd.DataFrame, y: pd.Series) -> LogisticRegression:
    m = LogisticRegression(C=5.0, max_iter=5000)
    m.fit(x, y)
    return m


# ---------------------------------------------------------------------------
def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--db', default='swknu_db')
    ap.add_argument('--workdir', type=Path, default=Path(__file__).resolve().parent / 'out')
    ap.add_argument('--train-until', default=TRAIN_UNTIL)
    a = ap.parse_args()
    a.workdir.mkdir(parents=True, exist_ok=True)

    print('[1/5] 데이터 추출')
    cand = to_bool(export(a.db, "SELECT * FROM pbl3.mv_candidate WHERE session_status = 'COMPLETED'",
                          a.workdir / 'candidate.csv'))
    cand['session_date'] = pd.to_datetime(cand.session_date)
    whatif = to_bool(export(a.db, '''SELECT w.*, p.series_key, s.session_date AS orig_date
                                       FROM pbl3.mv_p2_whatif w
                                       JOIN pbl3.program p USING (program_id)
                                       JOIN pbl3.program_session s USING (session_id)''',
                            a.workdir / 'whatif.csv'))
    print(f'      회차×학생 {len(cand):,}행, 시간대 후보 {len(whatif):,}행')

    X = features(cand)
    cols = list(X.columns)
    y_reg = cand.registered

    # ---- 2. 시간 분리 검증 ----------------------------------------------------
    print('[2/5] 시간 분리 검증 (학습 < %s <= 평가)' % a.train_until)
    tr = cand.session_date < a.train_until
    te = ~tr
    m_val = fit(X[tr], y_reg[tr])
    p_te = m_val.predict_proba(X[te])[:, 1]
    auc = roc_auc_score(y_reg[te], p_te)
    sess = pd.DataFrame({'session_id': cand.session_id[te], 'pred': p_te, 'act': y_reg[te]}) \
        .groupby('session_id').sum()
    mae = (sess.pred - sess.act).abs().mean()
    mape = ((sess.pred - sess.act).abs() / sess.act.clip(lower=1)).mean()
    base_rate = y_reg[tr].mean()
    base_mae = (base_rate * cand[te].groupby('session_id').size() - sess.act).abs().mean()
    print(f'      학생 단위 AUC {auc:.3f} | 회차별 신청 인원 오차 평균 {mae:.1f}명 '
          f'(평균 신청률만 쓰면 {base_mae:.1f}명)')

    # ---- 3. 최종 모델 --------------------------------------------------------
    print('[3/5] 최종 모델 학습 (진행된 전체 회차)')
    m_reg = fit(X, y_reg)
    reg_mask = cand.registered == 1
    att_cols = ['class_conflict', 'near_exam', 'is_online', 'cross_campus', 'evening',
                'log_past_attended', 'past_no_show_rate', 'no_history']
    m_att = fit(X.loc[reg_mask, att_cols], cand.attended[reg_mask])

    coef = dict(zip(cols, m_reg.coef_[0]))
    effects = [(k, LABELS[k], coef[k], float(np.exp(coef[k]))) for k in LABELS if k in coef]

    # ---- 4. 회차별 요인 분해 --------------------------------------------------
    print('[4/5] 회차별 요인 분해')
    p_now = m_reg.predict_proba(X)[:, 1]
    factor_rows = []
    base = pd.DataFrame({'session_id': cand.session_id, 'p_now': p_now})
    for key, (label, change) in FACTORS.items():
        x2 = change(X.copy())
        p_wo = m_reg.predict_proba(x2)[:, 1]
        affected = (X.values != x2.values).any(axis=1)
        g = base.assign(p_wo=p_wo, aff=affected).groupby('session_id').agg(
            now=('p_now', 'sum'), wo=('p_wo', 'sum'), aff=('aff', 'sum'))
        for sid, r in g.iterrows():
            factor_rows.append((sid, key, label, int(r.aff), r.now, r.wo, r.wo - r.now))

    # ---- 5. 시간대 시뮬레이션 -------------------------------------------------
    print('[5/5] 후보 시간대별 예상 인원')
    whatif = whatif.rename(columns={'slot_date': 'slot_date_'})
    w = whatif.assign(registered=0, attended=0)
    Xw = align(features(w), cols)
    pr = m_reg.predict_proba(Xw)[:, 1]
    pa = m_att.predict_proba(Xw[att_cols])[:, 1]
    w = whatif.assign(pr=pr, pa=pr * pa)
    slots = w.groupby(['session_id', 'weekday_iso', 'start_time']).agg(
        slot_date=('slot_date_', 'first'), is_current=('is_current', 'max'),
        eligible=('student_no', 'size'), conflict_rate=('class_conflict', 'mean'),
        near_exam=('near_exam', 'max'), reg=('pr', 'sum'), att=('pa', 'sum')).reset_index()

    # 예정 회차도 현재 일정 기준 요인 분해 (아직 결과가 없으므로 후보 시간대 중 현재 칸 사용)
    sched_ids = set(whatif.loc[whatif.actual_registered.isna(), 'session_id'])
    cur = (whatif.is_current == 1) & whatif.session_id.isin(sched_ids)
    if cur.any():
        Xc = Xw[cur.values]
        pc = m_reg.predict_proba(Xc)[:, 1]
        bc = pd.DataFrame({'session_id': whatif.session_id[cur].values, 'p_now': pc})
        for key, (label, change) in FACTORS.items():
            x2 = change(Xc.copy())
            p_wo = m_reg.predict_proba(x2)[:, 1]
            affected = (Xc.values != x2.values).any(axis=1)
            g = bc.assign(p_wo=p_wo, aff=affected).groupby('session_id').agg(
                now=('p_now', 'sum'), wo=('p_wo', 'sum'), aff=('aff', 'sum'))
            for sid, r in g.iterrows():
                factor_rows.append((sid, key, label, int(r.aff), r.now, r.wo, r.wo - r.now))

    # ---- 저장 ----------------------------------------------------------------
    note = (f'신청 logit 로지스틱 회귀(L2, C=5). 특성 {len(cols)}개(학년·집단·유형×학년·프로그램 고정효과 포함). '
            f'검증: {a.train_until} 이전 학습 → 이후 회차 평가. 평균 신청률 기준선 오차 {base_mae:.1f}명')
    sql = ['BEGIN;',
           insert_rows('pbl3.p2_model_run',
                       ['model_name', 'train_until', 'n_train', 'n_test', 'test_auc',
                        'test_session_mae', 'test_session_mape', 'note'],
                       [('logistic_registration_v1', a.train_until, int(tr.sum()), int(te.sum()),
                         auc, mae, mape, note)]),
           "CREATE TEMP TABLE _run ON COMMIT DROP AS SELECT max(run_id) AS run_id FROM pbl3.p2_model_run;"]
    sql.append(insert_rows('_eff', ['feature', 'label', 'coef', 'odds_ratio'], effects)
               .replace('INSERT INTO _eff', 'CREATE TEMP TABLE _eff (feature text, label text, coef numeric, odds_ratio numeric) ON COMMIT DROP;\nINSERT INTO _eff'))
    sql.append('INSERT INTO pbl3.p2_effect SELECT r.run_id, e.* FROM _eff e CROSS JOIN _run r;')
    sql.append('CREATE TEMP TABLE _fac (session_id int, factor text, label text, affected int, now numeric, wo numeric, lost numeric) ON COMMIT DROP;')
    sql.append(insert_rows('_fac', ['session_id', 'factor', 'label', 'affected', 'now', 'wo', 'lost'], factor_rows))
    sql.append('INSERT INTO pbl3.p2_session_factor SELECT r.run_id, f.* FROM _fac f CROSS JOIN _run r;')
    sql.append('CREATE TEMP TABLE _slot (session_id int, weekday_iso smallint, start_time time, slot_date date, '
               'is_current boolean, eligible int, conflict_rate numeric, near_exam boolean, reg numeric, att numeric) ON COMMIT DROP;')
    sql.append(insert_rows('_slot', ['session_id', 'weekday_iso', 'start_time', 'slot_date', 'is_current',
                                     'eligible', 'conflict_rate', 'near_exam', 'reg', 'att'],
                           [(int(r.session_id), int(r.weekday_iso), r.start_time, r.slot_date,
                             bool(r.is_current), int(r.eligible), float(r.conflict_rate), bool(r.near_exam),
                             float(r.reg), float(r.att)) for r in slots.itertuples()]))
    sql.append('INSERT INTO pbl3.p2_slot_forecast SELECT r.run_id, s.* FROM _slot s CROSS JOIN _run r;')
    sql.append('COMMIT;')
    sql_path = a.workdir / 'load_results.sql'
    sql_path.write_text('\n'.join(sql), encoding='utf8')
    psql(a.db, '-f', str(sql_path))
    print(f'      저장 완료: pbl3.p2_model_run / p2_effect / p2_session_factor / p2_slot_forecast')

    # ---- 요약 출력 -----------------------------------------------------------
    print('\n===== 주요 효과 (승산비: 1보다 작으면 신청 확률 감소) =====')
    for k, label, c, orr in effects[:12]:
        print(f'  {label:34s} 계수 {c:+.2f}  승산비 {orr:.2f}')
    print('\n===== 시간대 추천 (pbl3.v_p2_recommendation) =====')
    print(psql(a.db, '-P', 'pager=off', '-c',
               '''SELECT program_name, session_no AS n, cur_weekday AS cur_wd, cur_time AS cur_t,
                         cur_pred_attended AS cur_att, actual_attended AS act_att,
                         best_weekday AS best_wd, best_time AS best_t, best_pred_attended AS best_att, gain_attended AS gain
                    FROM pbl3.v_p2_recommendation ORDER BY program_name, session_no'''))


if __name__ == '__main__':
    main()
