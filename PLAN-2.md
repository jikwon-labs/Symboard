STATUS: IN_PROGRESS

# Symboard 2차 진행표

명세: `~/Downloads/handoff/symboard-ref/GAPS.md` (절 A~S). 기준 커밋 `5823fa3`. 1차 테스트 수 37.
항목 옆 괄호는 비교할 원본 장면(`frames/` 기준). 스크린샷은 `docs/screens/v2/<항목번호>-<이름>.png`.
체크한 항목 아래에 "원본 / 내 스크린샷 / 남은 차이" 를 적는다.

## A. 화면 뼈대와 테마

- [ ] A1. 짙은 따뜻한 바탕·점 격자·주황빨강 강조색, 노드 얇은 강조 테두리·둥근 모서리 (agent3/diagrams-0.5.png, agent1/board-0.jpg)
- [ ] A2. 떠 있는 위쪽 왼쪽 바: 홈으로·프로젝트 드롭다운·작업공간 탭(강조 테두리·노드 수 배지·닫기)·+·닫기 (agent1/board-0.jpg)
- [ ] A3. 위쪽 오른쪽: N live 알약·사용량 재설정 알약·계정·설정·도구 메뉴 (agent1/resume-top.jpg)
- [ ] A4. 왼쪽 세로 도구 막대(선택·에이전트·복제·텍스트·펜·지우개·도형·다이어그램·웹·이미지) (agent3/diagrams-0.5.png)
- [ ] A5. 오른쪽 세로 막대(레이어·삽입·설정·스튜디오 입구·루프 배지) (board.jpg r2c1, agent1/resume-top.jpg)
- [ ] A6. 아래 명령 바: 알약 버튼 줄 + 둥근 명령 입력(@ 대상) + 제안 알약 (node-composer.jpg r1c1, board.jpg r2c2)
- [ ] A7. 아래 왼쪽 git 브랜치 칩 + 변경 수, 아래 오른쪽 배율 "− N% +" (board.jpg r3c2)
- [ ] A8. 에이전트 생성: 강조 버튼 → CLI 목록 팝오버 → 캔버스 클릭 → 점선 자리표시 → 노드 (agent1/board-0.jpg, board.jpg r1c1)
- [ ] A9. 캔버스 손글씨풍 큰 제목 텍스트 (board.jpg r1c1)
- [ ] A10. 선택 객체 옆 속성 팝오버(색·굵기·글꼴·레이어/복제/삭제) (agent2/k-shape.jpg)

## B. 터미널 노드와 그룹

- [ ] B1. 노드 헤더: CLI 글리프+꺾쇠·상태 점·짧은 이름(자동)·상태 알약(모노 대문자)·권한 배지·다시 시작·복제·닫기 (agent1/resume-mid.jpg)
- [ ] B2. 그룹 프레임: 색 점·이름·개수·"N running"·접기, 프레임째 이동 (agent1/board-0.jpg 오른쪽)
- [ ] B3. 곡선 연결선과 흐르는 점 (board.jpg r2c2, r3c1)
- [ ] B4. 여러 노드 닫기 전 확인 (voice.jpg r3c3)

## F. 이어하기

- [ ] F1. 재실행 시 오른쪽 위 토스트 "Resume all conversations?" Yes/No/× (agent1/resume-top.jpg)
- [ ] F2. 노드 헤더 "Resume last conversation?" 말풍선, Yes 후 복원 문구·차례 부팅·줌아웃 (node-resume.jpg)

## E. 컴포저

- [ ] E1. 캔버스 위 카드형 팝오버: 팀 이름·역할 칩·4열 타일·Fill all·스테퍼·Spawn N (node-composer.jpg, agent1/comp.jpg)
- [ ] E2. 결과: 그룹 프레임 생성 + 노드 차례 부팅 (node-composer.jpg r3)

## C. 오케스트레이터와 일괄 명령

- [ ] C1. Orchestrator 노드: 헤더·진행·"N agents · M groups"·Connect·빈 상태 (board.jpg r1c3)
- [ ] C2. Connect → 그룹 칩 → Done → 그룹으로 곡선 연결 (board.jpg r2c1~r2c3)
- [ ] C3. 그룹별 섹션·행(아이콘·이름·CLI·상태 알약)·마우스 올리면 펼치기/일시정지 (board.jpg r3c1)
- [ ] C4. 하단 "Command N agents · @ to direct" 일괄 입력, 아래 명령 바의 @ 대상 지정 (board.jpg r3c3)

## D. 미션 맵

- [ ] D1. 도구 메뉴에서 여는 큰 모달·부제·필터 칩·검색 (teams.jpg, agent1/teams-30.jpg)
- [ ] D2. 오케스트레이터→팀→콘솔 곡선 그래프 + 오른쪽 상세 + Go to 줌 (teams.jpg r2~r3)

## J. 루프

- [ ] J1. 템플릿 카드 시작 화면 + 처음부터 만들기 (node-loops.jpg r1)
- [ ] J2. 생성 모달: 템플릿 칩·이름·지시문·시작 조건 카드 3개·간격 칩·대상·멈춤 토글 3개·목표 판정·요약 문장 (agent2/l-mid.jpg)
- [ ] J3. 목록 행: 상태 점·횟수·요약·카운트다운·지금 실행·토글·메뉴, 오른쪽 막대 배지 (agent2/l-end.jpg)

## H·I. 칸반·스티키·체크리스트·캘린더·도형·펜

- [ ] H1. 칸반 4열·열 머리·No cards·Add card·+ Column·드래그 이동 (node-kanban.jpg, agent2/kanban-1~3.jpg)
- [ ] H2. 카드 추가 모달(제목·메모·마감 칩·우선순위)과 카드 모양 (agent2/k-newcard.jpg)
- [ ] H3. 오른쪽 막대 삽입 팝오버 Checklist/Board/Calendar, 체크리스트 원형 카운터 (node-kanban.jpg r1)
- [ ] H4. 캘린더 노드: 월 격자·오늘·이벤트 팝오버·칩 (node-kanban.jpg r3)
- [ ] H5. 스티키: 헤더 없는 종이·손글씨체·접힌 모서리·종이 색 8개 팝오버 (node-kanban.jpg)
- [ ] H6. 도형(사각·원·마름모·화살표)·속성 팝오버·도형 안 텍스트·스케치풍 (agent2/k-shape.jpg)
- [ ] I1. 펜 팝오버(색 9+사용자·굵기 5)·스무딩 곡선·십자 커서·지우개, 이미지 헤더 없음 (node-ink.jpg)

## L·M·N.

- [ ] L1. git 카드 헤더·변경 목록 체크·None·메시지 생성·Commit & Push·완료 상태·히스토리 (node-git.jpg, agent2/g-end.jpg)
- [ ] M1. 웹 타일 탭·뒤/앞/새로고침·주소줄·시작 화면 포트 칩 (node-webtiles.jpg, agent2/w-open.jpg)
- [ ] M2. 표시 크기 프리셋·기기 배지·인스펙터 별도 타일+연결선 (agent2/w-end.jpg)
- [ ] N1. 사용량 팝오버: 링·주간 막대·히트맵·통계·토큰 상세 (node-usage.jpg, agent2/u-1.jpg)

## O·P·Q. 스튜디오

- [ ] O1. 보드 위 둥근 패널·어두운 뒤·왼쪽 열·닫으면 카드 노드·현재 프로젝트 자동 연결 (agent3/code-16.png, studio-code.jpg r3c3)
- [ ] P1. 코드 스튜디오: 트리·브레드크럼·언어 배지·줄/바이트·편집·줄 번호·Saved·Insert 코드 카드 (agent3/code-16.png)
- [ ] Q1. 마크다운: 검색·트리·words/min·Reading/Source/Graph·Export PDF (agent3/markdown-0.8.png)
- [ ] Q2. 링크 그래프 힘 기반 배치·강조·클릭 이동 (agent3/md-graph.png)

## K·R·S. 에이전트 생성

- [ ] K1. 메모리 모달·레포 필터·편집 화면·보드에 카드로 놓기 (node-memory.jpg, agent2/m-edit.jpg)
- [ ] K2. 레포 스캔(CLI 백그라운드)·단계 표시·제안 검토 (agent2/m-review.jpg)
- [ ] R1. 문서 스튜디오 왼쪽(CLI·깊이·템플릿)·빈 상태 (agent3/documents-2.6.png)
- [ ] R2. 생성 중 칩·Stop·실시간 종이·결과 종이·보드 문서 카드 (agent3/doc-gen.png, documents-19.png)
- [ ] S1. 다이어그램 팝오버(CLI·스타일·유형 6·자유 설명·시작 도형) (agent3/diag-pop-1.2.png)
- [ ] S2. 생성 중 칩·자리표시→등장·결과 보드 직접 손그림·서식 팝오버 (agent3/diagrams-2.5.png, diagrams-12.5.png)

## G. 계정 프로필

- [ ] G1. 위쪽 아이콘 팝오버: CLI 탭·노란 안내·ACTIVE 행·저장 계정 행·현재 로그인 저장·Connect (node-accounts.jpg)

## 마무리

- [ ] Z1. 1차 완료 기준 재확인(터미널 3 → vim → claude → 종료 → 재실행, 토스트 거쳐), release 빌드, README·REPORT-2

## 메모

## 막힌 것
