# SWKNU DB Programming — Team1
데이터베이스 프로그래밍 PBL 미션 2 (구현 및 SQL 검증)

- 팀장: 서우진 / 팀원: 김건희, 임영효
- DBMS: PostgreSQL (버전: TODO)

## Run
 
```bash
# 1. DB 생성 (최초 1회)
psql -U postgres -c "CREATE DATABASE swknu_db ENCODING 'UTF8';"
 
# 2. 초기화 + 생성 + 데이터 입력 + seed 검증 (재실행 시에도 동일)
psql -U postgres -d swknu_db -f reset.sql
 
# 3. 조회 전체 실행
psql -U postgres -d swknu_db -f 03_queries.sql
 
# 4. 검증 테스트 (파일 하나씩)
psql -U postgres -d swknu_db -f tests/T06_mileage_approval.sql
```

- `reset.sql`이 끝나면 마지막에 `Seed verification passed.`와 테이블별 건수가 출력된다.
- 각 테스트 파일은 필요한 데이터를 스스로 만들고 마지막에 `ROLLBACK`하므로 seed와 무관하게 몇 번이든 실행할 수 있다. 결과는 `PASS` / `FAIL`로 출력되고 마지막 줄에 실패 건수가 표시된다.
- 실행 환경 변수 `seed_environment`는 생략하면 `development`로 동작한다. DB 이름에 `prod` / `production`이 들어가면 실행을 거부한다.

## File Architecture
``` plain Text
sql-swknudb-project/
├── schema/
│   ├── 00_init.sql       -- 확장 기능 (pgcrypto 등)
│   ├── 01_common.sql     -- app_user, admin, role, permission, user_role, role_permission, change_log
│   ├── 02_master.sql     -- college, campus, department, professor, budget_item, expenditure_subject_type, academic_term, program_type, survey_question_category
│   ├── 03_student.sql    -- student, student_info_change_request
│   ├── 04_topcit.sql     -- topcit_exam_round, topcit_score, topcit_mileage_criteria + 응시 시점 스냅샷 트리거
│   ├── 05_mileage.sql    -- program, mileage_criteria, mileage_application, attachment
│   ├── 06_budget.sql     -- budget_project, initial_budget, expenditure
│   ├── 07_survey.sql     -- survey, survey_question, survey_response, survey_response_detail + 응답 검증·스냅샷 트리거
│   ├── 08_procedures.sql -- 업무 함수: 공통(로그·권한) / 학생정보 / 마일리지 / 지출 승인 처리
│   └── 09_analytics.sql  -- (예정) analytics 스키마: 분석 뷰, 모델 결과 테이블, 분석용 DB 역할
├── seed/
│   ├── 00_guard.sql ~ 07_survey.sql   -- 도메인별 정상 데이터 (상태 변경은 업무 함수로 생성)
│   ├── 08_verify.sql                   -- seed 무결성·집계 검증
│   └── README.md                       -- seed 구성·건수·검증 항목
├── queries/
│   └── Q01_student_info.sql ~ Q12_change_log.sql
├── tests/
│   └── T01_duplicate_key.sql ~ T12_seed_integrity.sql   -- 시나리오별 1파일
├── docs/
│   ├── 설계보완.md      -- mission1에서 바뀐 내용, 구현 정책, 구현 수준 구분
│   ├── erd_v2.dbml      -- 최종 ERD (dbdiagram.io)
│   ├── 검증보고서.md     -- 쿼리·테스트별 예상값 vs 실제값. 정리 후 추후 pdf로 다시 정리
│   └── screenshots/
├── analysis/           -- (예정) 만족도 그래프·예측 모델
├── 01_schema.sql   - schema/ 파일들을 순서대로 불러오는 입구 파일
├── 02_seed.sql     - seed/ 파일들을 불러오는 입구 파일
├── 03_queries.sql
├── reset.sql
└── README.md
```
| Path | contents |
|---|---|
| `schema/` | 테이블·제약조건·트리거·업무 함수 생성. 번호 순서 = FK 의존 순서 |
| `seed/` | 정상 가상 데이터. 오류 데이터는 넣지 않음 |
| `queries/` | 필수 조회·집계 Q01~Q12 |
| `tests/` | 오류 입력·상태 변경·롤백 검증. 파일별 개별 실행 |
| `analysis/` | (예정) 만족도 그래프·예측 모델 (Python) |
| `docs/` | 설계 보완 기록, ERD, 검증 보고서, 스크린샷·그래프 |
| `01_schema.sql` | `schema/` 전체를 순서대로 실행 |
| `02_seed.sql` | `seed/` 전체를 순서대로 실행 |
| `03_queries.sql` | `queries/` 전체를 순서대로 실행 |
| `reset.sql` | DB 초기화 후 스키마 생성 + 데이터 입력 + seed 검증 |

`reset.sql`은 public 스키마를 통째로 삭제하므로 로컬에서만 실행한다.

## Assignments
| 영역 | schema / seed | 08 함수 구역 | queries | tests | 담당 |
|---|---|---|---|---|---|
| 공통·기준정보·학생 | 00~03 | 1 공통, 2 학생정보 | Q01, Q02, Q12 | T01, T02, T05, T10, T11 | 서우진 |
| TOPCIT·마일리지 | 04, 05 | 3 마일리지 | Q03~Q07 | T03, T04(점수), T06 | 김건희 |
| 예산·만족도 | 06, 07 | 4 지출 | Q08~Q11 | T04(지출), T07, T08, T09 | 임영효 |
| 분석 | 09, analysis/ | — | — | — | 미정 |
 
`schema/08_procedures.sql`은 구역별로 나뉘어 있으며, 각자 자기 구역 안에서만 작성한다. 승인 함수는 공통 함수(`fn_assert_admin`, `fn_assert_permission`, `fn_write_change_log`)를 사용한다.

## Status
| 항목 | 상태 |
|---|---|
| 테이블 32개, FK 43개 | 완료 |
| 업무 함수 15개 | 완료 |
| Seed + 무결성 검증 (T12) | 완료 |
| T06 마일리지, T07 지출 | 완료 (실패 0) |
| Q01~Q12 | 진행 중 |
| T01~T05, T08~T11 | 진행 중 |
| 분석 확장 | 예정 |

예상값과 실제값 비교는 `docs/검증보고서.md`에 기록한다.

## 분석 확장 구조 (예정)
 
미션 요구사항 밖의 확장으로, 만족도 데이터를 그래프와 예측에 활용한다. 업무 테이블(public)과 분석 객체(analytics)를 스키마로 분리한다. 미션 필수 항목 완료 후 진행한다.
 
```
public (업무 테이블)
   │
   ▼
analytics (분석 뷰)
   v_survey_response_final   학생·조사별 최신 완료 응답
   v_satisfaction_summary    학기·프로그램유형·학과·학년별 평균, 응답 수
   v_student_features        학생별 특성 (모델 입력)
   │
   ├─▶ 그래프 (analysis/)
   └─▶ 모델 (analysis/) ─▶ analytics 결과 테이블
                              model_run
                              program_forecast
                              student_recommendation
                                 │
                                 ▼
                           v_forecast_vs_actual (예측 vs 실제)
```
 
분석 단계:
 
1. 그래프: 학기·유형·학과·학년별 만족도 추이 (메인)
2. 기준선 예측: 과거 학기 유형별 평균을 다음 학기 예상치로 사용 (SQL)
3. 모델: 여러 변수를 반영한 예측, 기준선과 비교 (시연)

테스트 데이터 규모가 작아 예측 정확도보다 데이터 흐름(DB → 모델 → DB → 계획)을 보여주는 데 목적을 둔다.
 
분석 실행:
 
```bash
cd analysis
pip install -r requirements.txt
python plot_satisfaction.py
```

## Common rules
- main에 직접 push하지 않고 브랜치 → Pull Request → merge
- 브랜치 이름: `종류/작업내용` (영어 소문자, 하이픈)
  - `feat/` 기능 추가, `fix/` 수정, `test/` 검증, `refactor/` 구조 정리, `docs/` 문서, `chore/` 정리
  - 예: `feat/topcit-schema`, `fix/survey-score-check`, `test/student-tests`
- 작업 시작 전 `git checkout main` → `git pull` → 새 브랜치 생성
- 내 브랜치에 main의 새 작업이 필요하면 `git pull origin main`
- merge 후 브랜치 삭제
- 접속 비밀번호 등은 커밋하지 않는다
- 1차 설계 대비 변경은 `docs/설계보완.md`에 바로 기록한다
- PR 전 reset.sql 실행 확인, 함수를 고쳤다면 해당 테스트도 실행 (PL/pgSQL 변수 오타는 reset에서 안 잡힘)
- merge 후 main에서 reset.sql 한 번 더 확인 (충돌 없이 합쳐져도 실행이 깨질 수 있음)
### SQL rule
- 이름: 소문자 `snake_case`, 테이블명 단수형 (`USER`는 예약어라 `app_user`)
- 제약조건 이름: `pk_테이블`, `fk_테이블_대상`, `uq_테이블_컬럼`, `ck_테이블_컬럼`, `ex_테이블_내용`, 인덱스 `ix_테이블_컬럼`
- 학번·교번·코드: `VARCHAR` (숫자형 금지 — 앞자리 0, 포맷 변경 대비)
- 대리키: `INT/BIGINT GENERATED ALWAYS AS IDENTITY`
- 사용여부: `is_active BOOLEAN NOT NULL DEFAULT TRUE` (Y/N 문자 대신 BOOLEAN)
- 일시: `TIMESTAMPTZ`, 등록일시는 `DEFAULT now()` / 날짜만이면 `DATE`
- 금액: `BIGINT` (원 단위). FLOAT·REAL 금지
- 상태값: `VARCHAR + CHECK (... IN (...))`, 승인 대상은 기본값 `'PENDING'`
- 처리자·등록자 컬럼: `VARCHAR(20)` FK → `app_user(user_id)`
- FK 컬럼에는 인덱스를 직접 만든다 (PostgreSQL은 자동 생성하지 않음)
- FK 삭제 옵션: 기본(NO ACTION). `ON DELETE CASCADE` 사용 금지 — 논리삭제 원칙
- 서브타입(student/admin): `(PK, user_type)` 복합 FK → `app_user(user_id, user_type)`
- 상태 변경(승인·반려·취소·회수)은 직접 UPDATE하지 않고 `08_procedures.sql`의 업무 함수로
- 변경로그: `change_log`에 INSERT만, `fn_write_change_log`로 기록. `target_type`은 소문자 테이블명 그대로
  - CREATE: before = NULL, after = 생성된 행 전체
  - 그 외: before / after = 바뀐 항목만

## Decisions
- [x] 휴대폰번호·이메일 암호화 방식
      - 가상 데이터 사용으로 미구현. 평문 VARCHAR로 저장
- [x] 예산항목 7개 명칭
      - 인건비, 학생인건비, 연구장비시설비, 연구활동비, 연구재료비, 연구수당, 간접비
- [x] 학년 범위: 1~4 (초과학기 학생도 4)
- [x] 마일리지 기준 적용 시점: 신청 시점
- [x] 마일리지 중복: 학생·프로그램별 활성(대기·승인) 1건, 반려·취소·회수 후 재신청 허용
- [x] 지출한도 ≤ 최초예산, 한도 초과 승인 차단, 90% 이상 경고
- [x] 만족도 중복 응답 허용, 최신 완료 응답만 집계

정책 전체와 근거는 `docs/설계보완.md` 참고.

## Not implemented
- 학생 연락처·이메일 암호화 (가상 데이터)
- 학생 본인 데이터 접근 통제를 DB 권한·뷰로 차단하는 것 (역할·권한 데이터와 조회 범위 검증 SQL로 대체)
- 업무 테이블 직접 UPDATE 차단 (업무 함수를 거칠 때만 규칙 적용)
- 지출 취소 함수 (상태값만 존재)
- 교수 로그인 계정 (교수는 독립 기준정보)
- 프로그램 참여자 테이블 (만족도 응답 자격을 FK로 검증하지 않음)
- 분석 확장 (09_analytics, analysis/)
