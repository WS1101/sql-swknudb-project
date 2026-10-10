# SWKNU DB 프로그래밍 PBL — Team1
데이터베이스 프로그래밍 PBL 미션 2 (구현 및 SQL 검증)

- 팀장: 서우진 / 팀원: 김건희, 임영효
- DBMS: PostgreSQL (버전: TODO)

## Run
 
```bash
# 1. DB 생성 (최초 1회)
psql -U postgres -c "CREATE DATABASE pbl_db ENCODING 'UTF8';"
 
# 2. 초기화 + 생성 + 데이터 입력 (재실행 시에도 동일)
psql -U postgres -d pbl_db -f reset.sql
 
# 3. 조회 전체 실행
psql -U postgres -d pbl_db -f 03_queries.sql
 
# 4. 검증 테스트 (파일 하나씩)
psql -U postgres -d pbl_db -f tests/T01_duplicate_key.sql
```

## File Architecture
``` plain Text
sql-swknudb-project/
├── schema/
│   ├── 00_init.sql       -- 확장 기능 (pgcrypto 등)
│   ├── 01_common.sql     -- 사용자·권한·변경로그
│   ├── 02_master.sql     -- 기준정보 (대학·캠퍼스·학과·교수·예산항목 등)
│   ├── 03_student.sql    -- 학생 인적사항
│   ├── 04_topcit.sql     -- TOPCIT
│   ├── 05_mileage.sql    -- 프로그램·마일리지
│   ├── 06_budget.sql     -- 예산·지출
│   ├── 07_survey.sql     -- 만족도
│   └── 08_procedures.sql    -- 승인 처리 함수·트리거 (추가)
├── seed/
│   ├── 01_common_master.sql ~ 07_survey.sql   -- 도메인별로 분리
├── queries/
│   └── Q01_student_info.sql ~ Q12_change_log.sql
├── tests/
│   └── T01_duplicate_student.sql ...           -- 시나리오별 1파일
├── docs/
│   ├── 설계보완.md      -- mission1에서 바뀐 내용
│   ├── 검증보고서.md     -- requirements에 포한되는 것. 정리 후 추후 pdf로 다시 정리
│   └── screenshots/
├── 01_schema.sql   - schema/ 파일들을 순서대로 불러오는 입구 파일
├── 02_seed.sql     - seed/ 파일들을 불러오는 입구 파일
├── 03_queries.sql
├── reset.sql
└── README.md
```
| Path | contents |
|---|---|
| `schema/` | 테이블·제약조건 생성. 번호 순서 = FK 의존 순서 |
| `seed/` | 정상 가상 데이터. 오류 데이터는 넣지 않음 |
| `queries/` | 필수 조회·집계 Q01~Q12 |
| `tests/` | 오류 입력·상태 변경·롤백 검증. 파일별 개별 실행 |
| `docs/` | 설계 보완 기록, 검증 보고서, 스크린샷 |
| `01_schema.sql` | `schema/` 전체를 순서대로 실행 |
| `02_seed.sql` | `seed/` 전체를 순서대로 실행 |
| `03_queries.sql` | `queries/` 전체를 순서대로 실행 |
| `reset.sql` | DB 초기화 후 스키마 생성 + 데이터 입력 |

`reset.sql`은 public 스키마를 통째로 삭제하므로 로컬에서만 실행한다.

## Assignments
| 영역 | schema / seed | queries | 담당 |
|---|---|---|---|
| 공통·기준정보·학생 | 00~03 | Q01, Q02, Q12 | 서우진 |
| TOPCIT·마일리지 | 04, 05 | Q03~Q07 | 김건희 |
| 예산·만족도 | 06, 07 | Q08~Q11 | 임영효 |
 
`schema/08_procedures.sql`은 각자 도메인의 승인 처리 로직을 추가한다.

01·02는 모두가 참조하므로 가장 먼저 merge.

## Common rules
- - main에 직접 push하지 않고 브랜치 → Pull Request → merge
- 브랜치 이름: `종류/작업내용` (영어 소문자, 하이픈)
  - `feat/` 기능 추가, `fix/` 수정, `docs/` 문서, `chore/` 정리
  - 예: `feat/topcit-schema`, `fix/survey-score-check`
- 작업 시작 전 `git checkout main` → `git pull` → 새 브랜치 생성
- merge 후 브랜치 삭제
- 접속 비밀번호 등은 커밋하지 않는다
### Implements rule
- 이름: 소문자 `snake_case`, 테이블명 단수형 (`USER`는 예약어라 `app_user`)
- 제약조건 이름: `pk_테이블`, `fk_테이블_대상`, `uq_테이블_컬럼`, `ck_테이블_컬럼`, 인덱스 `ix_테이블_컬럼`
- 학번·교번·코드: `VARCHAR` (숫자형 금지 — 앞자리 0, 포맷 변경 대비)
- 대리키: `INT/BIGINT GENERATED ALWAYS AS IDENTITY`
- 사용여부: `is_active BOOLEAN NOT NULL DEFAULT TRUE` (Y/N 문자 대신 BOOLEAN)
- 일시: `TIMESTAMPTZ`, 등록일시는 `DEFAULT now()` / 날짜만이면 `DATE`
- 금액: `BIGINT` (원 단위). FLOAT·REAL 금지
- 상태값: `VARCHAR + CHECK (... IN (...))`, 기본값 `'PENDING'`
- 처리자·등록자 컬럼: `VARCHAR(20)` FK → `app_user(user_id)`
- FK 삭제 옵션: 기본(NO ACTION). `ON DELETE CASCADE` 사용 금지 — 논리삭제 원칙
- 서브타입(student/admin): `(PK, user_type)` 복합 FK → `app_user(user_id, user_type)`
- 변경로그: `change_log`에 INSERT만. `target_type`은 소문자 테이블명 그대로

## non-decisions
- [ ] 휴대폰번호·이메일 암호화 방식 (pgcrypto vs 애플리케이션)
- [ ] 예산항목 7개 실제 명칭
