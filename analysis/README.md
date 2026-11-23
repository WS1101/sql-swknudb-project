# Survey Insight — 기본판 실행 안내

기본판은 **설문 시간·응답 품질·만족도 비교**만 담당한다. 우진이가 만드는 참여자·회차·시간표 테이블 없이 실행할 수 있다.

## 파일과 수정 범위

| 파일 | 담당 범위 | 실행 시점 |
|---|---|---|
| `05_survey_insight.sql` → `schema/10_survey_insight.sql` | 시작 시각, 품질 판정, 원본/제외/가중 평균 | 기본 필수 |
| `analysis/app.py` | 만족도 현황 / 응답 품질 / 응답 시간 | 기본 화면 |
| `06_survey_participation.sql` → `schema/11_survey_participation_link.sql` | 출석 연결 VIEW, 관찰 범위, 90일 재참여 | 구조 확정 후 선택 |
| `analysis/app_extended.py` | 재참여·모델을 포함한 이전 확장 화면 | 선택 |
| `analysis/model.py`, `requirements-ml.txt` | 재참여 예측 모델 | 선택 |

`10`에는 공통 public 참여 테이블 생성문이 없다. 기존 버전이 이미 만든 테이블·함수·데이터는 삭제하지 않는다. 기본판은 그것을 조회하지 않는다. `attendance_count` 반환 컬럼은 기존 DB에 안전하게 재적용하기 위한 호환 자리이며 기본 SQL에서는 NULL이다. 기본 화면에는 표시하지 않는다.

## 설치 및 기본 실행

저장소 루트에서 실행한다. PostgreSQL 16, Python 3.11 이상을 권장하며 이번 검증 환경은 PostgreSQL 16.15/Python 3.14.6이다. PowerShell 활성화 스크립트 없이 가상환경 Python을 직접 사용한다.

```powershell
python -m venv .venv
$surveyPython = Join-Path (Get-Location) '.venv\Scripts\python.exe'
& $surveyPython -m pip install -r analysis/requirements.txt
$env:PGCLIENTENCODING = 'UTF8'

# 기존 미션 2 DB에 기본 확장만 적용. reset.sql은 필요 없다.
psql -U postgres -d swknu_db -v ON_ERROR_STOP=1 -f 05_survey_insight.sql

# 비밀번호는 저장소 밖의 pgpass 또는 별도 PGPASSFILE에서 관리
$env:SURVEY_DATABASE_URL = 'host=127.0.0.1 port=5432 dbname=swknu_db user=survey_dashboard'
& $surveyPython -m streamlit run analysis/app.py --server.address 127.0.0.1 --server.headless true
```

브라우저: `http://127.0.0.1:8501`. 기본 화면에는 재참여 기준일·출석 인원·모델 버튼이 없다. 민감도와 추가 검토는 만족도 현황 탭 안에 접어 두었다. 앱은 READ ONLY + REPEATABLE READ 트랜잭션으로 같은 SQL 결과를 읽는다.

서비스 계정이 없다면 관리자가 psql에서 한 번 생성한다. Windows libpq 비밀번호 파일은 `%APPDATA%\postgresql\pgpass.conf`이며 비밀번호를 코드나 커밋에 넣지 않는다.

```sql
CREATE ROLE survey_dashboard LOGIN;
GRANT analytics_reader TO survey_dashboard;
\password survey_dashboard
```

이번 작업의 `.local` 시연 DB가 남아 있는 환경은 `python -m analysis.run_local_demo`로 기본 세 화면을 다시 시작할 수 있다. 새 clone은 아래 시연 DB 준비 절차를 따른다. Ctrl+C로 앱을 종료하고 `python -m analysis.local_test_db stop`으로 독립 PostgreSQL을 종료한다.

## 팀 공통 pbl3 데이터로 실행·검증

현재 팀 데이터는 `origin/main`의 `d11b078`에서 가져온 `pbl3/` SQL을 사용한다. 학생 1,596명·프로그램 35개·회차 184개·설문 응답 3,921건이며 `analysis.generate_demo`를 사용하지 않는다. 모델·두 대시보드·리포트 모두 `pbl3`를 선택할 수 있다.

이번 검증은 인증 정보가 없는 기존 5432 DB 대신, `.local/pgdata`의 독립 PostgreSQL(127.0.0.1:55439)에 팀 SQL을 재현해 진행했다. DB는 `survey_insight_test`이며 접속 문자열은 Git에서 제외된 `.local/test_dsn.txt`에만 저장했다. 이 작업 폴더에서 다시 실행하려면 다음을 사용한다.

```powershell
$surveyPython = Join-Path (Get-Location) '.venv\Scripts\python.exe'
$env:SURVEY_DATABASE_URL = (Get-Content -LiteralPath '.local\test_dsn.txt' -Raw).Trim()
$env:SURVEY_TEST_DATABASE_URL = $env:SURVEY_DATABASE_URL
& $surveyPython -m pytest tests/test_pbl3_insight.py tests/test_survey_dashboard.py::test_missing_database_shows_safe_error -q
& $surveyPython -m analysis.model --source pbl3 --asof 2026-11-23 --output analysis/reports/pbl3_model.json
& $surveyPython -m analysis.export_report --source pbl3 --asof 2026-11-23 --with-participation
& $surveyPython -m streamlit run analysis/app_extended.py --server.address 127.0.0.1
```

대시보드에서는 **팀 공통 데이터 (pbl3)**를 선택한다. PC를 재시작했거나 독립 DB를 종료한 경우 먼저 `& $surveyPython -m analysis.local_test_db start`를 실행한다. 서버 종료는 `& $surveyPython -m analysis.local_test_db stop`이다. 현재 작업 폴더의 패치는 이미 적용되어 있으므로 다시 적용하지 않는다.

새 환경은 `analysis/requirements-ml.txt` 설치 후 **신규 전용 테스트 DB**에 팀 데이터를 준비한다. 비밀번호는 pgpass 또는 PGPASSFILE로 설정한다.

```powershell
psql -U postgres -d postgres -c "CREATE DATABASE survey_pbl3_test ENCODING 'UTF8';"
psql -U postgres -d survey_pbl3_test -v ON_ERROR_STOP=1 -f pbl3/reset_pbl3.sql
$env:SURVEY_DATABASE_URL = 'host=127.0.0.1 port=5432 dbname=survey_pbl3_test user=postgres'
$env:SURVEY_TEST_DATABASE_URL = $env:SURVEY_DATABASE_URL
& $surveyPython -m analysis.model --source pbl3 --asof 2026-11-23 --output analysis/reports/pbl3_model.json
& $surveyPython -m pytest tests/test_pbl3_insight.py -q
```

`reset_pbl3.sql`은 `pbl3`·`pbl3_truth`를 삭제하고 재생성한다. 데이터가 이미 준비된 DB에서 재테스트할 때는 reset 없이 모델과 pytest 명령만 실행한다. 함수만 연결할 때는 `pbl3/14_pbl3_survey_insight.sql`을 적용한다.

재참여 정의는 **설문 제출 이후 90일 이내의 후속 회차 출석**이며 같은 프로그램의 다음 회차를 포함한다. 예정 회차는 제외하고, 수집 범위·90일 관찰·실제 후속 기회가 확인되는 응답만 평가한다. 모델 학습은 문항분류 점수 5개만 사용하며 `pbl3_truth`의 적극성·정답 계수는 읽지 않는다.

학생 적극성이 모든 분류 점수와 신청·출석에 공통으로 반영되므로 생성기의 운영 직접효과가 0이어도 모델의 운영 표준화 계수는 0이 아닐 수 있다. 이번 결과는 **0.09118**이다. 이를 운영 개선의 인과효과나 모델 오류로 해석하지 않는다. 모델 JSON·확장 화면·HTML 리포트에 이 해석 주의를 함께 표시한다.

이번 pbl3 통합·화면 테스트와 DB 미설정 오류 검증은 **11 passed**이다. 원본 답변과 평균 비교, 고유 출석 인원, 같은 프로그램 포함/제외의 전체 재참여 라벨, 관찰 부족 처리, 민감도, 정답지 접근 차단, 학생·시간 분리, 두 화면의 데이터 전환과 모델 버튼을 검증한다. 기존 미션 2 SQL 검증도 별도로 PASS 154 + NOTICE PASS 31, FAIL 0을 확인했다.

재참여 SQL은 `ev AS NOT MATERIALIZED`로 학생 조건이 기존 인덱스까지 전달되게 했다. 전체 후보를 응답마다 반복 탐색해 30초 제한에 걸리던 문제를 해결하며, 두 가지 재참여 정의의 결과를 독립 이벤트 계산과 비교했다. [모델 결과](reports/pbl3_model.json), [집계·해석 설정](reports/pbl3_extended_metadata.json), [차트](reports/pbl3_extended_overview.png), [테스트 결과](reports/pbl3_tests.xml)를 확인할 수 있다.

## 이전 설문 전용 합성 시연

별도 새 DB에서 준비한다. 생성기는 기존 원본을 삭제/덮어쓰지 않는다.

```powershell
psql -U postgres -d postgres -c "CREATE DATABASE swknu_insight_demo ENCODING 'UTF8';"
psql -U postgres -d swknu_insight_demo -v ON_ERROR_STOP=1 -f 01_schema.sql
psql -U postgres -d swknu_insight_demo -v ON_ERROR_STOP=1 -f 02_seed.sql
psql -U postgres -d swknu_insight_demo -v ON_ERROR_STOP=1 -f 05_survey_insight.sql
$env:SURVEY_DATABASE_URL = 'host=127.0.0.1 port=5432 dbname=swknu_insight_demo user=postgres'
& $surveyPython -m analysis.generate_demo --allow-synthetic
$env:SURVEY_DATABASE_URL = 'host=127.0.0.1 port=5432 dbname=swknu_insight_demo user=survey_dashboard'
& $surveyPython -m streamlit run analysis/app.py --server.address 127.0.0.1
```

화면에서 **합성 시연 데이터**를 선택한다. 학생 360명·프로그램 24개·설문 2,377건 중 유효 응답은 2,241건이다. 기본 시드는 출석/참여 기회 테이블을 만들거나 기록하지 않는다. 난수 시드는 20261123이다. 이미 합성 프로그램이 있으면 재실행을 거부하며, 오류 시 전체 트랜잭션을 롤백한다.

## 기본 규칙

| 항목 | 기본값/정의 |
|---|---|
| 응답 선택 | 학생·조사별 최신 완료. 시각 동률은 큰 response_id |
| 절대 빠름 | 총 시간 / 점수 문항 수 < 2초 |
| 상대 빠름 | 시간 표본 10건 이상, 시간 백분위 ≤ .1, 중앙 시간 × .25 미만 |
| 반복 | 점수 문항 4개 이상, 전체 점수 동일 |
| 지표 | max(0,100 − 빠름×40 − 반복×15 − 동시발생×20) |
| 의심 제외 | 지표 70 미만. 정보 부족은 지표 NULL |
| 평균 | 점수 합 / 점수 개수. 분모 0이면 NULL |
| 보조 가중 평균 | Σ(점수 합×w)/Σ(문항 수×w), w=지표/100. 정보 부족은 중립 유지 정책으로 w=1 |

느린 5점 반복은 85점으로 유지하고 빠른 5점 반복은 25점으로 구분한다. 기준·감점은 화면에서 변경한다. 지표는 성실할 확률이 아니며 빠름/반복 자체는 불성실함의 증거가 아니다. 과거 시작 시각은 소급 생성하지 않고 주관식 길이/공란으로 감점하지 않는다.

## 우진이 구조가 정해진 뒤

1. [참여 데이터 연결 계약](../docs/참여데이터_연결계약.md)의 키·출석 정의를 합의한다.
2. `06_survey_participation.sql`을 적용한다. 빈 VIEW와 FALSE 연결 플래그가 만들어진다.
3. `analytics.v_attendance_event`의 SELECT를 실제 참여자·회차 JOIN으로 교체한다. 기본 설문 SQL은 수정하지 않는다.
4. 실제 참여 기회 VIEW와 수집 범위까지 확인되면 재참여율을 활성화한다. 출석만 연결된 단계는 참여 기회 연계 대기이다.
5. 필요할 때 `analysis/app_extended.py`를 실행한다.

`06` 재적용은 작성한 매핑과 연결 플래그를 초기화하지 않는다. 공통 public 참여 테이블은 생성·변경하지 않는다. 현재 알 수 없는 컬럼명을 추정해 넣지 않았다. 이전 출석 데이터도 의미를 확인하지 않고 자동 복사하지 않는다.

확장만 별도로 시연하려면 **아직 합성 시드를 넣지 않은 별도 DB**에서 다음을 실행한다.

```powershell
psql -U postgres -d swknu_insight_demo -v ON_ERROR_STOP=1 -f 06_survey_participation.sql
& $surveyPython -m analysis.generate_demo --allow-synthetic --with-participation
& $surveyPython -m streamlit run analysis/app_extended.py --server.address 127.0.0.1
```

선택 시드는 `analytics.survey_demo_attendance`, `analytics.survey_demo_opportunity`에만 가상 참여를 저장한다. 이미 연결된 팀 매핑은 덮어쓰지 않는다.

## 리포트·모델·테스트

```powershell
# 기본 리포트: 출석 조회 없음
& $surveyPython -m analysis.export_report --source synthetic --asof 2026-11-23
# 선택 리포트/모델: 연결 완료 후
& $surveyPython -m analysis.export_report --source synthetic --asof 2026-11-23 --with-participation
& $surveyPython -m pip install -r analysis/requirements-ml.txt
& $surveyPython -m analysis.model --source synthetic --asof 2026-11-23
```

기본 출력은 `analysis/reports/synthetic_*`, 선택 출력은 `synthetic_extended_*`이다. PNG/SVG/오프라인 HTML·집계 CSV·설정 JSON을 제공한다. 개인정보는 내보내지 않는다. `reports/archive/`는 분리 전 결과이며 현재 기본판의 재참여 결과가 아니다.

```powershell
# 미션 2 + 05 + 기본 합성 시드가 있는 전용 *_test DB
$env:SURVEY_TEST_DATABASE_URL = 'host=127.0.0.1 port=5432 dbname=survey_core_v2_test user=postgres'
& $surveyPython -m pytest tests/test_survey_insight.py tests/test_survey_dashboard.py -q
# 미션 2 + 05 + 06 + --with-participation 시드가 있는 별도 DB
$env:SURVEY_TEST_DATABASE_URL = 'host=127.0.0.1 port=5432 dbname=survey_link_v2_test user=postgres'
& $surveyPython -m pytest tests/test_survey_participation.py -q
```

기본 22개·선택 확장 7개 통과. 기본/선택 각각 미션 2 검증도 PASS 154 + NOTICE PASS 31, FAIL 0이다. 기존 검증은 합성 시드를 넣기 **전** 별도 DB에서 실행한다. 새 fixture는 롤백하고 `_test` DB만 허용한다. URL이 없으면 SKIP하며 DB 테스트를 수행했다고 해석하면 안 된다.

SQL은 품질·시간·평균을 계산하고 Python은 연결·시각화를 담당한다. 선택 모델은 시간/학생 분리와 라벨 성숙을 고려하며 합성 성능을 실제 학생 정확도/인과효과로 설명하지 않는다. 자세한 현재 범위는 [기본판 보고서](../docs/미션3_Survey_Insight.md)를 참고한다.
