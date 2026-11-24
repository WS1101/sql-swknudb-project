# PBL3 시연 웹페이지 (`docs/`)

GitHub Pages로 띄우는 정적 페이지입니다. 서버나 DB 연결 없이, DB에서 내보낸 JSON을 읽어 화면을 그립니다.

```
DB (pbl3 테이블·모델 결과) ──export SQL──▶ docs/data/*.json ──▶ docs/tabs/*.js 가 화면으로 그림
```

## 로컬에서 보기

```bash
python3 -m http.server 8000 -d docs
# 브라우저에서 http://localhost:8000
```

`index.html`을 더블클릭해서 열면 JSON을 못 읽습니다. 꼭 위처럼 서버로 여세요.

## 구조와 담당

| 파일 | 담당 | 내용 |
|---|---|---|
| `index.html` | 공통 (고치지 않기) | 상단 탭, 탭 전환, JSON 불러오기 |
| `style.css` | 공통 | 색·글꼴·카드·경고·큰 숫자 등 공통 클래스 |
| `tabs/satisfaction.js` + `data/satisfaction.json` | 1번 | 만족도 진단 |
| `tabs/schedule.js` + `data/schedule.json` | 2번 (서우진) | 회차 일정 점검 |
| `tabs/budget.js` + `data/budget.json` | 3번 | 예산 효율 |
| `tabs/student.js` + `data/students.json` | 서우진 | 학생 활동 조회 (사업단 자문 요청) |

각자 자기 `tabs/*.js`와 `data/*.json`만 고치면 merge 충돌이 나지 않습니다.

## 내 탭 채우는 법

1. **데이터 내보내기 SQL 작성**: `pbl3/p2/export_schedule_json.sql`을 복사해서 자기 쿼리로 바꿉니다. `json_build_object`와 `json_agg`로 JSON 하나를 만들고 `\o docs/data/파일.json`으로 저장합니다.
   ```bash
   psql -d swknu_db -XAtq -f pbl3/export_xxx_json.sql
   ```
2. **탭 파일 수정**: `ready: true`, `data: 'data/파일.json'`으로 바꾸고 `render(root, data)` 안에 화면을 그립니다. `tabs/schedule.js`가 완성 예시입니다.
3. **공통 클래스 사용**: 색 값을 직접 쓰지 말고 `style.css`의 클래스와 `var(--토큰)`을 씁니다. 다크 모드도 자동으로 맞춰집니다.

| 클래스 | 용도 |
|---|---|
| `.card` | 흰 카드 |
| `.alert.crit` / `.warn` / `.ok` | 경고 문구 (빨강·주황·초록) |
| `.compare` + `.opt` (`.sel`) | 두 개 나란히 비교, 선택된 쪽 강조 |
| `.big` | 큰 숫자 (`<small>` 단위 포함) |
| `.factors` + `.f` | 가로 막대 목록 (`.gain`은 파랑) |
| `.chip.ok` / `.warn` / `.crit` | 작은 상태 표시 |
| `.note` | 회색 설명 문구 |

## GitHub Pages 켜기

저장소 **Settings → Pages → Build and deployment**에서 Branch를 `main`, 폴더를 `/docs`로 저장하면 몇 분 뒤 `https://<계정>.github.io/<저장소>/`에 올라갑니다. 무료 계정은 **공개 저장소**에서만 Pages를 쓸 수 있습니다.

데이터를 바꾸면 export SQL을 다시 실행하고 `docs/data/*.json`을 커밋하면 됩니다.
