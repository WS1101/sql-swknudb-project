# SWKNU DB 프로그래밍 PBL — Team1

## Run
```bash
psql -U postgres -d pbl_db -f reset.sql   # 로컬 전용! 공용 DB 금지
```
DB 생성 시: `CREATE DATABASE pbl_db ENCODING 'UTF8';`
타임존: `ALTER DATABASE pbl_db SET timezone TO 'Asia/Seoul';`

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


## Assignments
| 파일 | 담당 |
|---|---|
| 01_common, 02_master, 03_student | 서우진 |
(확정 아님)
| 04_topcit, 05_mileage | 김건희 |
| 06_budget, 07_survey | 임영효 |

01·02는 모두가 참조하므로 가장 먼저 merge.

## Common rules
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
