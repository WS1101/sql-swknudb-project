# PBL 미션 3 — 팀 공통 가상 데이터 v1

기존 미션2 SQL을 수정하지 않고 새 `pbl3` 스키마에 회차·참여·시간표·시험기간 데이터를 추가한다.
분석용으로 설계한 **가상 데이터**이며, 실제 공주대 수업시간표/시험일정/학생 출석을 의미하지 않는다.

## 실행 순서

기존 `reset.sql`로 미션2 데이터가 채워진 **개인 개발용 DB**에서 실행한다.

```powershell
# 저장소 최상위 폴더에서 실행
$env:PGCLIENTENCODING = 'UTF8'
psql -U postgres -d swknu_demo -v ON_ERROR_STOP=1 -f pbl3/00_shared_schema.sql
psql -U postgres -d swknu_demo -v ON_ERROR_STOP=1 -f pbl3/01_shared_seed.sql
psql -U postgres -d swknu_demo -v ON_ERROR_STOP=1 -f pbl3/02_shared_check.sql
psql -U postgres -d swknu_demo -v ON_ERROR_STOP=1 -f pbl3/03_budget_example.sql
```

위 예시의 DB 명 `swknu_demo`는 팀원이 사용하는 DB 명으로 바꾸어도 된다. 동일 파일을 재실행해도 기본 행을 중복 생성하지 않는다.

### 데이터 공유 계약

| 테이블 | 키/의미 | 사용하는 파트 |
|---|---|---|
| `pbl3.program_session` | `session_id`, `program_id`, `session_no`; 회차·날짜·시간·장소 | 1,2,3 |
| `pbl3.program_participant` | `(session_id, student_no)`; 신청 학생의 실제 출석 상태 | 1,2,3 |
| `pbl3.course_timetable` | 학과·학년 그룹의 **가상** 주간 수업시간표 | 2 |
| `pbl3.academic_event` | **가상** 시험기간 및 학사 이벤트 | 2 |

`program_id`는 기존 `public.program.program_id`, `student_no`는 기존 `public.student.student_no`를 참조한다.
`attendance_status='ATTENDED'`인 사람만 출석자로 집계하고 `NO_SHOW`·`CANCELLED`는 제외한다.
같은 학생이 5개 회차에 참석해도 프로그램별 **고유 참여 학생 수**는 `COUNT(DISTINCT student_no)`를 사용한다.
프로그램 회차 5개의 참석 횟수(`COUNT(*)`)와 고유 참여 학생 수는 다른 지표다.

## 설계한 분석 신호

- 회차마다 요일·시간을 바꿔 수업 충돌에 차이가 생기도록 한다.
- 가상 시험기간 근처와 수업 충돌이 있는 경우 신청·출석 가능성을 낮추는 생성 규칙을 사용한다.
- 모든 값이 난수 시드 대신 학생번호/프로그램/회차를 조합한 해시로 생성되어 재실행 결과가 일정하다.
- 기존 완료 설문 응답이나 승인된 프로그램 마일리지 기록이 있는 학생은 본행사(5회차) 출석과 연결한다.

**해석 주의:** 생성 규칙에 영향을 심은 가상 데이터라 실제 대학에서 수업 충돌이 참여 저조의 원인이라는 증거는 아니다. 모델 정확도·기여도는 합성 데이터에서 생성 규칙의 패턴을 복원하는 시연이라는 점을 발표에 밝힌다. 또한 설문이 없는 프로그램의 만족도 비용 지표는 NULL이고, `expenditure.program_id IS NULL`인 공통 지출은 프로그램 비용에 배분하지 않는다.

## 팀원별 연결 가이드

- **건희(1)**: `analytics.v_survey_response_final`에서 응답자/문항별 점수를 가져와 `program_participant`와 `student_no`, `program_id`로 연결한다. 단, 설문 조사 이후의 프로그램 출석을 재참여로 정의해야 한다. 같은 프로그램 준비 회차 출석을 사후 재참여로 해석하면 안 된다.
- **우진(2)**: `program_session`의 날짜·시간과 `course_timetable`의 학과·학년·요일·시간대가 겹치는지를 계산한다. `academic_event`의 시험기간 근접도도 사용할 수 있다. 실제 과목별 개인 시간표가 아니라 그룹 대표 가상 시간표이다.
- **영효(3)**: `public.expenditure`에서 `APPROVED` 및 `program_id`가 있는 건을 합산한다. 출석 인원과 만족 응답자를 따로 집계한 뒤 조인해야 금액이 중복되지 않는다. `03_budget_example.sql` 참고.

## 추가·변경하기

- 새 시연 데이터는 각자 별도 파일(예: `pbl3/10_survey_extra.sql`)에 작성하고 공통 파일은 직접 덮어쓰지 않는다.
- 추가 컬럼이 필요하면 **먼저 팀원과 이름과 타입을 공유**한다. 특히 `program_id`, `session_id`, `student_no`, `attendance_status` 의미는 변경하지 않는다.
- 실제 시연 숫자는 각자 SQL 실행 결과로 확인한다. 임의의 예상 숫자를 발표 자료에 확정값처럼 넣지 않는다.
- `pbl3/02_shared_check.sql`로 건수·출석률·설문 연계 검증이 가능하다.

## 주의: reset.sql

기존 `reset.sql`은 public/analytics를 DROP 한다. PBL3 확장 테이블이 public을 참조하므로, **PBL3 도입 후 원본 reset.sql을 실행하면 확장 테이블의 FK 등이 CASCADE로 영향을 받을 수 있다.** 안전하게 다시 초기화하려면 반드시 아래 순서를 지킨다.

```powershell
psql -U postgres -d swknu_demo -f pbl3/99_drop_pbl3_only.sql
psql -U postgres -d swknu_demo -f reset.sql
psql -U postgres -d swknu_demo -f pbl3/00_shared_schema.sql
psql -U postgres -d swknu_demo -f pbl3/01_shared_seed.sql
```

미션2 데이터를 삭제하지 않고 PBL3만 제거하려면 `99_drop_pbl3_only.sql`만 실행한다.
