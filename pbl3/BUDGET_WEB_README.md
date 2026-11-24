# 3번 예산 효율 웹 탭

기존 1번/2번 화면이나 미션 2 데이터베이스 코드는 변경하지 않았습니다.

## 추가·수정 파일

- `docs/tabs/budget.js`: 프로그램 선택, KPI, 유형별 비교, 효율 해석, 참여 증가 가정 시뮬레이션
- `docs/tabs/budget.css`: 3번 탭에만 적용하는 디자인
- `docs/data/budget.json`: **현재는 발표 화면 확인용 예시값(실제 DB 결과 아님)**
- `pbl3/export_budget_json.sql`: 현재 DB의 `pbl3.v_program_cost`에서 예산 효율 데이터를 JSON으로 출력

## 실제 가상 DB 결과로 교체하기 (필수)

1. 기존 팀원 데이터베이스에서 `pbl3/reset_pbl3.sql` 등 공통 데이터를 먼저 준비합니다.
2. 저장소 최상위 폴더에서 다음 명령어 실행:

```powershell
psql -U postgres -d swknu_demo -X -Atq -f pbl3/export_budget_json.sql
```

> DB 이름은 팀원 PC에서 실제 사용하는 이름으로 변경하세요. 현재 저장소 README는 `swknu_db`를 예시로 씁니다.

3. `docs/data/budget.json`을 열어 `"mode": "database"`가 보이는지 확인합니다.
4. 웹 미리보기:

```powershell
python -m http.server 8000 -d docs
```

5. `http://localhost:8000/#budget`에서 **가상 DB 조회 결과** 문구를 확인하고 원본 시드와 수치 대조 후 Git에 반영합니다.

## 지표 정의

- 연결 승인 지출 = `pbl3.expenditure`에서 상태 `APPROVED`인 프로그램별 금액 합계
- 고유 출석자 = 해당 프로그램에 1회 이상 실제 출석한 고유 학생 수
- 만족 출석자 = 출석자 중 완료 응답·일괄 응답 제외 후 CONTENT 평균 4점 이상인 고유 학생 수
- 재참여자 = 같은 프로그램의 회차에 2회 이상 출석한 학생 수
- 비용 단가 = 연결 승인 지출 ÷ 각 학생 수. 분모가 0이면 비교 불가.
- 유형 내 중앙값은 만족 출석자 5명 이상인 프로그램 기준.
- 참여 개선 슬라이더는 **추가 비용 0원**을 가정한 산술 시뮬레이션이며, 예측 모델 결과가 아닙니다.

## 주의

이 JSON은 공개되는 GitHub Pages의 정적 데이터입니다. 학생 이름·학번 같은 식별 정보는 넣지 않습니다. 실제 서비스에 사용한다면 비식별 집계만 게시하고, 접근 권한을 별도로 설계해야 합니다.
