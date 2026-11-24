#!/usr/bin/env bash
# 2번 참여 분석 전체 실행: 모델 학습 → 결과 저장(pbl3.p2_*) → 차트
#   사용법 (저장소 루트에서):  bash pbl3/p2/run_participation.sh [DB이름]
#   먼저 psql -d swknu_db -f pbl3/reset_pbl3.sql 을 실행해 두어야 한다.
#   필요한 파이썬 패키지: pandas numpy scikit-learn matplotlib
set -euo pipefail
DB="${1:-${PBL3_DB:-swknu_db}}"
DIR="$(cd "$(dirname "$0")" && pwd)"
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -c "SELECT 1 FROM pbl3.mv_p2_whatif LIMIT 1" >/dev/null \
  || { echo "pbl3/reset_pbl3.sql 을 먼저 실행하세요"; exit 1; }
python3 "$DIR/participation_model.py" --db "$DB"
python3 "$DIR/make_charts.py" --db "$DB"
