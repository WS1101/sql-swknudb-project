"""2번 발표용 차트 (PNG). participation_model.py 실행 후 사용.

  bash pbl3/p2/run_participation.sh 가 모델 → 차트 순서로 함께 실행한다.
  출력: pbl3/p2/charts/*.png
"""
from __future__ import annotations

import argparse
import io
import subprocess
import sys
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
import numpy as np
import pandas as pd

# 색: 기준 팔레트 (categorical slot 1·2, 중립 텍스트, 순차 파랑)
SURFACE = '#fcfcfb'
INK = '#0b0b0b'
INK2 = '#52514e'
GRID = '#e4e3df'
BLUE = '#2a78d6'
ORANGE = '#eb6834'
SEQ = ['#cde2fb', '#b7d3f6', '#9ec5f4', '#86b6ef', '#6da7ec', '#5598e7', '#3987e5',
       '#2a78d6', '#256abf', '#1c5cab', '#184f95', '#104281', '#0d366b']
WD = {1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일'}


def setup_font() -> None:
    have = {f.name for f in font_manager.fontManager.ttflist}
    for name in ('Noto Sans CJK KR', 'NanumGothic', 'NanumBarunGothic', 'Malgun Gothic', 'AppleGothic'):
        if name in have:
            plt.rcParams['font.family'] = name
            break
    else:
        print('경고: 한글 글꼴이 없어 글자가 깨질 수 있습니다. (Ubuntu: sudo apt install fonts-nanum)')
    plt.rcParams.update({'axes.unicode_minus': False, 'figure.facecolor': SURFACE, 'axes.facecolor': SURFACE,
                         'axes.edgecolor': GRID, 'axes.labelcolor': INK2, 'xtick.color': INK2,
                         'ytick.color': INK2, 'text.color': INK, 'font.size': 11})


def q(db: str, sql: str, allow_fail: bool = False) -> pd.DataFrame | None:
    r = subprocess.run(['psql', '-X', '-q', '-d', db, '-c', f'COPY ({sql}) TO STDOUT CSV HEADER'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        if allow_fail:
            return None
        sys.exit(r.stderr)
    return pd.read_csv(io.StringIO(r.stdout))


def clean(ax, grid_axis='y') -> None:
    for s in ('top', 'right', 'left'):
        ax.spines[s].set_visible(False)
    ax.spines['bottom'].set_color(GRID)
    ax.grid(axis=grid_axis, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(length=0)


# ---------------------------------------------------------------------------
def chart_algo(db: str, out: Path) -> None:
    """알고리즘 특강: 실제 신청 + 수업 충돌로 잃은 신청"""
    d = q(db, '''SELECT o.session_no, o.weekday_iso, to_char(o.start_time,'HH24:MI') AS t, o.registered,
                        round(o.conflict_rate*100) AS conflict_pct,
                        greatest(f.lost_registrations, 0) AS lost
                   FROM pbl3.v_session_overview o
                   JOIN pbl3.p2_session_factor f ON f.session_id = o.session_id AND f.factor = 'class_conflict'
                    AND f.run_id = (SELECT max(run_id) FROM pbl3.p2_model_run)
                  WHERE o.series_key = 'ALGO_CT' ORDER BY o.session_no''')
    fig, ax = plt.subplots(figsize=(10, 5.2))
    x = np.arange(len(d))
    ax.bar(x, d.registered, width=0.62, color=BLUE, label='실제 신청 인원', edgecolor=SURFACE, linewidth=2)
    ax.bar(x, d.lost, bottom=d.registered, width=0.62, color=ORANGE, label='수업 충돌로 잃은 신청 (모델 추정)',
           edgecolor=SURFACE, linewidth=2)
    for i, r in d.iterrows():
        ax.text(i, r.registered / 2, f'{r.registered}', ha='center', va='center', color='white', fontsize=10)
        if r.lost >= 3:
            ax.text(i, r.registered + r.lost + 2, f'+{r.lost:.0f}', ha='center', va='bottom', color=INK, fontsize=10)
    ax.set_xticks(x, [f'{r.session_no}회\n{WD[r.weekday_iso]} {r.t}\n충돌 {r.conflict_pct:.0f}%' for r in d.itertuples()])
    top = (d.registered + d.lost).max()
    ax.set_ylim(0, top * 1.25)
    ax.axvline(2.5, color=INK2, linestyle=(0, (3, 3)), linewidth=1)
    ax.text(2.45, top * 1.2, '4회차부터 수요일 13:00로 변경 →', color=INK2, fontsize=10, va='top', ha='right')
    ax.set_ylabel('신청 인원(명)')
    ax.set_title('코딩테스트 대비 알고리즘 특강 2026: 시간 변경 후 수업 충돌로 신청 감소', loc='left', fontsize=13, pad=14)
    clean(ax)
    ax.legend(frameon=False, loc='upper right', bbox_to_anchor=(1, 1.02))
    fig.tight_layout()
    fig.savefig(out / '01_algo_conflict.png', dpi=200)
    plt.close(fig)


def chart_slots(db: str, out: Path, program_like: str, session_no: int, fname: str) -> None:
    """후보 시간대 히트맵: 예상 출석 인원"""
    d = q(db, f'''SELECT f.weekday_iso, to_char(f.start_time,'HH24:MI') AS t, f.is_current,
                         least(f.predicted_registered, p.capacity) * f.predicted_attended
                           / NULLIF(f.predicted_registered,0) AS att,
                         f.conflict_rate, f.near_exam, p.program_name, s.session_date
                    FROM pbl3.p2_slot_forecast f
                    JOIN pbl3.program_session s USING (session_id)
                    JOIN pbl3.program p USING (program_id)
                   WHERE f.run_id = (SELECT max(run_id) FROM pbl3.p2_model_run)
                     AND p.program_name LIKE '{program_like}' AND s.session_no = {session_no}''')
    if d is None or d.empty:
        return
    times = sorted(d.t.unique())
    grid = d.pivot(index='weekday_iso', columns='t', values='att').reindex(columns=times)
    conf = d.pivot(index='weekday_iso', columns='t', values='conflict_rate').reindex(columns=times)
    cur = d[d.is_current == 't'].iloc[0] if (d.is_current == 't').any() else d[d.is_current == True].iloc[0]
    best = d.loc[d.att.idxmax()]
    cmap = matplotlib.colors.LinearSegmentedColormap.from_list('seq', SEQ)
    fig, ax = plt.subplots(figsize=(9, 5))
    im = ax.imshow(grid.values, cmap=cmap, aspect='auto')
    vmin, vmax = np.nanmin(grid.values), np.nanmax(grid.values)
    for i, wd in enumerate(grid.index):
        for j, t in enumerate(times):
            v = grid.loc[wd, t]
            # 진한 칸(순차 팔레트 뒤쪽 절반)만 흰 글씨
            color = 'white' if (v - vmin) / max(vmax - vmin, 1e-9) > 0.55 else INK
            ax.text(j, i - 0.12, f'{v:.0f}명', ha='center', va='center', color=color, fontsize=11)
            ax.text(j, i + 0.22, f'충돌 {conf.loc[wd, t]*100:.0f}%', ha='center', va='center', color=color, fontsize=8)
    for row, label, ls in ((cur, '현재', '-'), (best, '추천', '-')):
        i = list(grid.index).index(row.weekday_iso)
        j = times.index(row.t)
        ax.add_patch(plt.Rectangle((j - 0.48, i - 0.48), 0.96, 0.96, fill=False,
                                   edgecolor=ORANGE if label == '추천' else INK, linewidth=2.5, linestyle=ls))
        ax.text(j + 0.44, i - 0.44, label, ha='right', va='top', fontsize=8,
                color=ORANGE if label == '추천' else INK, fontweight='bold')
    ax.set_xticks(range(len(times)), times)
    ax.set_yticks(range(len(grid.index)), [WD[w] for w in grid.index])
    ax.tick_params(length=0)
    for s in ax.spines.values():
        s.set_visible(False)
    gain = best.att - cur.att
    ties = d[(d.att >= best.att - 0.5)]
    best_label = (f'{WD[best.weekday_iso]} {best.t}' if len(ties) == 1 else
                  f'{best.t} ({",".join(WD[w] for w in sorted(ties.weekday_iso))} 비슷)' if ties.t.nunique() == 1 else
                  f'{WD[best.weekday_iso]} {best.t} 등')
    ax.set_title(f'{d.program_name.iloc[0]} {session_no}회차 ({pd.to_datetime(d.session_date.iloc[0]):%m/%d} 주): '
                 f'시간대별 예상 출석\n현재 {WD[cur.weekday_iso]} {cur.t} {cur.att:.0f}명 → '
                 f'추천 {best_label} {best.att:.0f}명 (+{gain:.0f}명)',
                 loc='left', fontsize=12, pad=12)
    cb = fig.colorbar(im, ax=ax, fraction=0.035, pad=0.02)
    cb.outline.set_visible(False)
    cb.set_label('예상 출석(명)', color=INK2)
    fig.tight_layout()
    fig.savefig(out / fname, dpi=200)
    plt.close(fig)


def chart_recovery(db: str, out: Path) -> None:
    """심어둔 정답 vs 모델 추정 (pbl3_truth 접근 가능할 때만)"""
    d = q(db, 'SELECT * FROM pbl3_truth.v_p2_recovery', allow_fail=True)
    if d is None or d.empty:
        print('  정답 복원 차트 생략 (pbl3_truth 조회 권한 없음)')
        return
    keep = ['class_conflict', 'cross_campus', 'near_exam', 'prev_own_content_c', 'prev_avg_content_c',
            'evening', 'fatigue', 'is_online', 'friday', 'vacation']
    d = d[d.feature.isin(keep)].copy()
    d['order'] = d.feature.map({k: i for i, k in enumerate(keep)})
    d = d.sort_values('order', ascending=False).reset_index(drop=True)
    short = {'class_conflict': '전공 수업 시간 겹침', 'cross_campus': '다른 캠퍼스', 'near_exam': '시험기간',
             'prev_own_content_c': '직전 회차 본인 만족도(1점당)', 'prev_avg_content_c': '직전 회차 평균 만족도(1점당)',
             'evening': '18시 이후', 'fatigue': '회차 누적(회당)', 'is_online': '온라인', 'friday': '금요일',
             'vacation': '방학 *'}
    fig, ax = plt.subplots(figsize=(9, 5.4))
    y = np.arange(len(d))
    ax.hlines(y, d.truth_coef, d.estimated_coef, color=GRID, linewidth=2)
    ax.scatter(d.truth_coef, y, s=70, facecolor=SURFACE, edgecolor=INK2, linewidth=2, label='생성기에 심은 정답', zorder=3)
    ax.scatter(d.estimated_coef, y, s=70, color=BLUE, edgecolor=SURFACE, linewidth=2, label='모델 추정', zorder=4)
    ax.axvline(0, color=INK2, linewidth=0.8)
    ax.set_yticks(y, [short[f] for f in d.feature])
    ax.set_xlabel('신청 확률에 대한 효과 (로지스틱 계수, 0보다 작으면 감소)')
    ax.set_title('모델은 숨겨둔 효과를 얼마나 복원했나', loc='left', fontsize=13, pad=12)
    clean(ax, grid_axis='x')
    ax.legend(frameon=False, loc='lower right')
    fig.text(0.01, 0.01, '* 방학 프로그램이 모두 캠프·해커톤이라 방학 효과와 프로그램 효과를 분리할 수 없음 → 수집 설계 개선 과제',
             fontsize=8.5, color=INK2)
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    fig.savefig(out / '03_effect_recovery.png', dpi=200)
    plt.close(fig)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default='swknu_db')
    ap.add_argument('--out', type=Path, default=Path(__file__).resolve().parent / 'charts')
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    setup_font()
    chart_algo(a.db, a.out)
    chart_slots(a.db, a.out, 'MLOps%', 2, '02_mlops_slot.png')
    chart_slots(a.db, a.out, '코딩테스트%', 4, '04_algo_slot_s4.png')
    chart_recovery(a.db, a.out)
    print(f'  차트 저장: {a.out}')


if __name__ == '__main__':
    main()
