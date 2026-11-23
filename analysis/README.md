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

## 설문 전용 합성 시연

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
