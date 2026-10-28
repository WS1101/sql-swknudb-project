# SWKNU DB Programming — Team1
데이터베이스 프로그래밍 PBL 미션 2 (구현 및 SQL 검증)

- 팀장: 서우진 / 팀원: 김건희, 임영효
- DBMS: PostgreSQL 
- 실행 도구: **psql 필수** (`\ir`, `\if`, `\gset` 등 psql 명령 사용)

## Run

```bash
# 0. Windows PowerShell: 저장소 폴더로 이동, 인코딩·사용자 설정
cd 저장소경로              # 예) C:\work\sql-swknudb-project
$env:PGCLIENTENCODING = 'UTF8'
$env:PGUSER = 'postgres'

# 1. DB 생성 (최초 1회)
psql -U postgres -c "CREATE DATABASE swknu_db ENCODING 'UTF8';"

# 2. 초기화 + 생성 + 데이터 입력 + seed 검증 (재실행 시에도 동일)
psql -U postgres -d swknu_db -f reset.sql

# 3. 조회 전체 실행
psql -U postgres -d swknu_db -f 03_queries.sql

# 4. 검증 테스트 전체 / 하나씩
psql -U postgres -d swknu_db -f 04_tests.sql
psql -U postgres -d swknu_db -f tests/T06_mileage_approval.sql

# 5. 발표용 시연 (실행 SQL과 결과를 그대로 출력, ROLLBACK)
psql -U postgres -d swknu_db -f demo/D1_common_student.sql

# 6. 분석 차트
psql -U postgres -d swknu_db -c "\copy (SELECT * FROM analytics.v_student_features ORDER BY student_no) TO 'analysis/data/student_features.csv' CSV HEADER"
psql -U postgres -d swknu_db -c "\copy (SELECT * FROM analytics.v_satisfaction_summary) TO 'analysis/data/satisfaction_summary.csv' CSV HEADER"
pip install -r analysis/requirements.txt
python analysis/plot_analytics.py
```

- `reset.sql`이 끝나면 `Seed verification passed.`와 테이블별 건수가 출력된다.
- 테스트는 필요한 데이터를 스스로 만들고 `ROLLBACK`하므로 seed와 무관하게 몇 번이든 실행할 수 있다. 결과표에 `PASS` / `FAIL`과 실패 건수가 표시된다.
- 시연 스크립트도 `BEGIN … ROLLBACK`이라 seed를 바꾸지 않는다. 자동 번호만 증가하므로 ID를 비교할 땐 reset 후 쿼리를 먼저 실행한다.
- `seed_environment`는 생략하면 `development`로 동작하고, DB 이름에 `prod` / `production`이 있으면 실행을 거부한다.
- 분석 계정 시연(`demo/D4`, `tests/T13`)은 superuser로 실행한다.

### SQL 인코딩 (Windows psql)

- SQL 파일은 UTF-8이며, 실행 시 `$env:PGCLIENTENCODING = 'UTF8'`로 클라이언트 인코딩을 맞춘다.
- `UHC`에서 `UTF8`로 변환할 수 없다는 오류는 UTF-8 파일을 UHC(CP949)로 해석할 때 발생한다. DB의 `ENCODING 'UTF8'`과 클라이언트 인코딩은 별도 설정이다.

## File Architecture
```plain text
sql-swknudb-project/
├── schema/
│   ├── 00_init.sql       -- 확장 기능 (pgcrypto)
│   ├── 01_common.sql     -- app_user, admin, role, permission, user_role, role_permission, change_log
│   ├── 02_master.sql     -- college, campus, department, professor, budget_item, expenditure_subject_type, academic_term, program_type, survey_question_category
│   ├── 03_student.sql    -- student, student_info_change_request
│   ├── 04_topcit.sql     -- topcit_exam_round, topcit_score, topcit_mileage_criteria + 응시 시점 스냅샷 트리거
│   ├── 05_mileage.sql    -- program, mileage_criteria, mileage_application, attachment
│   ├── 06_budget.sql     -- budget_project, initial_budget, expenditure
│   ├── 07_survey.sql     -- survey, survey_question, survey_response, survey_response_detail + 응답 검증·스냅샷 트리거
│   ├── 08_procedures.sql -- 업무 함수: 공통(로그·권한) / 학생정보 / 마일리지 / 지출
│   └── 09_analytics.sql  -- analytics 스키마: 분석 뷰 3개, 분석 전용 계정
├── seed/
│   ├── 00_guard.sql ~ 07_survey.sql   -- 도메인별 정상 데이터 (상태 변경은 업무 함수로 생성)
│   ├── 08_verify.sql                   -- seed 무결성·집계 검증
│   └── README.md
├── queries/              -- Q01 ~ Q12
├── tests/                -- T01 ~ T13, _helpers.sql, _report.sql
├── demo/                 -- D1 ~ D4 발표용 시연, _setup.sql
├── analysis/             -- plot_analytics.py, requirements.txt, data/, charts/
├── docs/
│   ├── 설계보완.md
│   ├── 검증보고서.md
│   ├── erd_v2.dbml
│   └── screenshots/
├── 01_schema.sql         -- schema/ 순서대로 실행
├── 02_seed.sql           -- seed/ 순서대로 실행
├── 03_queries.sql        -- queries/ 순서대로 실행
├── 04_tests.sql          -- tests/ 순서대로 실행
├── reset.sql             -- analytics·public 삭제 → 생성 → 입력 → 검증
└── README.md
```

| Path | contents |
|---|---|
| `schema/` | 테이블·제약조건·트리거·업무 함수·분석 뷰. 번호 순서 = FK 의존 순서 |
| `seed/` | 정상 가상 데이터. 오류 데이터는 넣지 않음 |
| `queries/` | 필수 조회·집계 Q01~Q12. 머리말에 목적·입력·기준·예상 결과 |
| `tests/` | 오류 입력·상태 변경·권한·롤백 검증. 파일별 개별 실행 |
| `demo/` | 발표용 시연. 실행하는 SQL과 에러·결과를 그대로 출력 |
| `analysis/` | 분석 뷰 CSV로 차트 생성 |
| `docs/` | 설계 보완, 검증 보고서, ERD, 스크린샷 |

`reset.sql`은 public·analytics 스키마를 삭제하므로 로컬에서만 실행한다.

## Assignments
| 영역 | schema / seed | 08 함수 구역 | queries | tests | demo | 담당 |
|---|---|---|---|---|---|---|
| 공통·기준정보·학생 | 00~03 | 1 공통, 2 학생정보 | Q01, Q02, Q12 | T01, T02, T05, T10, T11 | D1 | 서우진 |
| TOPCIT·마일리지 | 04, 05 | 3 마일리지 | Q03~Q07 | T03, T04(점수), T06 | D2 | 김건희 |
| 예산·만족도 | 06, 07 | 4 지출 | Q08~Q11 | T04(지출), T07, T08, T09 | D3 | 임영효 |
| 분석 | 09, analysis/ | — | — | T13 | D4 | 서우진 |

## Status
| 항목 | 결과 |
|---|---|
| 테이블 32, 분석 뷰 3, FK 43 | 완료 |
| 업무 함수 15 | 완료 |
| Seed + 무결성 검증 | 통과 |
| Q01~Q12 | 완료 |
| 테스트 T01~T13 | 결과표 PASS 154 + NOTICE PASS 31, 실패 0 |
| 분석 뷰·분석 계정·차트 | 완료 |

예상값과 실제값 비교는 `docs/검증보고서.md`.

## Analytics

미션 요구사항 밖의 확장. 운영 데이터를 프로그램 개선·예산 판단에 쓰기 위해, 업무 테이블(public)과 분리된 분석 영역(analytics)을 둔다.

```
public (업무 테이블)
   │
   ▼
analytics (뷰, 개인정보 제외)
   v_survey_response_final   학생·조사별 최신 완료 응답
   v_satisfaction_summary    학기·유형·문항분류·학과·학년별 만족도 (합계·개수 포함)
   v_student_features        학생별 학과·학년·마일리지·TOPCIT·만족도
   │
   ├─▶ analysis/plot_analytics.py → 차트
   └─▶ (향후) 관리자 대시보드, 모델
```

- 뷰는 조회할 때마다 원본에서 계산 → 항상 최신, 같은 기준
- `analytics_reader` 계정은 analytics 뷰만 조회. public 스키마 사용 권한이 없어 연락처·계정·로그에 접근 불가 (T13, D4)
- 예측 모델 결과 테이블은 데이터 규모·학기 범위 한계로 이번 범위에서 제외

## Common rules
- main에 직접 push하지 않고 브랜치 → Pull Request → merge
- 브랜치 이름: `종류/작업내용` (영어 소문자, 하이픈)
  - `feat/` 기능, `fix/` 수정, `test/` 검증, `refactor/` 구조 정리, `docs/` 문서, `chore/` 정리
- 작업 시작 전 `git checkout main` → `git pull` → 새 브랜치 생성
- 내 브랜치에 main의 새 작업이 필요하면 `git pull origin main`
- merge 후 브랜치 삭제, 접속 비밀번호는 커밋하지 않음
- 1차 설계 대비 변경은 `docs/설계보완.md`에 기록
- PR 전 reset.sql 실행, 함수를 고쳤다면 해당 테스트도 실행 (PL/pgSQL 변수 오타는 reset에서 안 잡힘)
- merge 후 새 clone·새 DB에서 reset 확인 (로컬에만 남은 수정 방지)

### SQL rule
- 이름: 소문자 `snake_case`, 테이블명 단수형 (`USER`는 예약어라 `app_user`)
- 제약조건 이름: `pk_`, `fk_`, `uq_`, `ck_`, `ex_`, 인덱스 `ix_`
- 학번·교번·코드: `VARCHAR`
- 대리키: `INT/BIGINT GENERATED ALWAYS AS IDENTITY`
- 사용여부: `is_active BOOLEAN NOT NULL DEFAULT TRUE`, 코드표는 DELETE 대신 비활성화
- 일시 `TIMESTAMPTZ`, 금액 `BIGINT`
- 상태값: `VARCHAR + CHECK`, 승인 대상은 기본값 `'PENDING'`
- FK 컬럼에는 인덱스를 직접 생성, `ON DELETE CASCADE` 사용 금지
- 서브타입(student/admin): `(PK, user_type)` 복합 FK
- 상태 변경은 직접 UPDATE하지 않고 `08_procedures.sql` 업무 함수로
- 변경로그: `fn_write_change_log`로만 기록. CREATE는 행 전체, 그 외는 바뀐 항목만



## Not implemented
- 학생 연락처·이메일 암호화 (가상 데이터)
- 업무 조회의 학생 본인 범위 제한을 DB 권한·RLS로 차단 (쿼리 수준으로 구현, T10)
- 업무 테이블 직접 UPDATE 차단 (업무 함수를 거칠 때만 규칙 적용)
- 지출 취소 함수 (상태값만 존재)
- 교수 로그인 계정
- 프로그램 참여자 테이블 (참여는 마일리지 승인·설문 응답으로만 추정)
- 예측 모델과 결과 테이블
