STATUS: IN_PROGRESS

# Symboard 2차 진행표

명세: `~/Downloads/handoff/symboard-ref/GAPS.md` (절 A~S). 기준 커밋 `5823fa3`. 1차 테스트 수 37.
항목 옆 괄호는 비교할 원본 장면(`frames/` 기준). 스크린샷은 `docs/screens/v2/<항목번호>-<이름>.png`.
체크한 항목 아래에 "원본 / 내 스크린샷 / 남은 차이" 를 적는다.

## A. 화면 뼈대와 테마

- [x] A1. 짙은 따뜻한 바탕·점 격자·주황빨강 강조색, 노드 얇은 강조 테두리·둥근 모서리 (agent3/diagrams-0.5.png, agent1/board-0.jpg)
- [x] A2. 떠 있는 위쪽 왼쪽 바: 홈으로·프로젝트 드롭다운·작업공간 탭(강조 테두리·노드 수 배지·닫기)·+·닫기 (agent1/board-0.jpg)
- [x] A3. 위쪽 오른쪽: N live 알약·사용량 재설정 알약·계정·설정·도구 메뉴 (agent1/resume-top.jpg)
- [x] A4. 왼쪽 세로 도구 막대(선택·에이전트·복제·텍스트·펜·지우개·도형·다이어그램·웹·이미지) (agent3/diagrams-0.5.png)
- [x] A5. 오른쪽 세로 막대(레이어·삽입·설정·스튜디오 입구·루프 배지) (board.jpg r2c1, agent1/resume-top.jpg)
- [x] A6. 아래 명령 바: 알약 버튼 줄 + 둥근 명령 입력(@ 대상) + 제안 알약 (node-composer.jpg r1c1, board.jpg r2c2)
- [x] A7. 아래 왼쪽 git 브랜치 칩 + 변경 수, 아래 오른쪽 배율 "− N% +" (board.jpg r3c2)
- [x] A8. 에이전트 생성: 강조 버튼 → CLI 목록 팝오버 → 캔버스 클릭 → 점선 자리표시 → 노드 (agent1/board-0.jpg, board.jpg r1c1)
- [x] A9. 캔버스 손글씨풍 큰 제목 텍스트 (board.jpg r1c1)
- [x] A10. 선택 객체 옆 속성 팝오버(색·굵기·글꼴·레이어/복제/삭제) (agent2/k-shape.jpg)

## B. 터미널 노드와 그룹

- [x] B1. 노드 헤더: CLI 글리프+꺾쇠·상태 점·짧은 이름(자동)·상태 알약(모노 대문자)·권한 배지·다시 시작·복제·닫기 (agent1/resume-mid.jpg)
- [x] B2. 그룹 프레임: 색 점·이름·개수·"N running"·접기, 프레임째 이동 (agent1/board-0.jpg 오른쪽)
- [x] B3. 곡선 연결선과 흐르는 점 (board.jpg r2c2, r3c1)
- [x] B4. 여러 노드 닫기 전 확인 (voice.jpg r3c3)

## F. 이어하기

- [x] F1. 재실행 시 오른쪽 위 토스트 "Resume all conversations?" Yes/No/× (agent1/resume-top.jpg)
- [x] F2. 노드 헤더 "Resume last conversation?" 말풍선, Yes 후 복원 문구·차례 부팅·줌아웃 (node-resume.jpg)

## E. 컴포저

- [x] E1. 캔버스 위 카드형 팝오버: 팀 이름·역할 칩·4열 타일·Fill all·스테퍼·Spawn N (node-composer.jpg, agent1/comp.jpg)
- [x] E2. 결과: 그룹 프레임 생성 + 노드 차례 부팅 (node-composer.jpg r3)

## C. 오케스트레이터와 일괄 명령

- [x] C1. Orchestrator 노드: 헤더·진행·"N agents · M groups"·Connect·빈 상태 (board.jpg r1c3)
- [x] C2. Connect → 그룹 칩 → Done → 그룹으로 곡선 연결 (board.jpg r2c1~r2c3)
- [x] C3. 그룹별 섹션·행(아이콘·이름·CLI·상태 알약)·마우스 올리면 펼치기/일시정지 (board.jpg r3c1)
- [x] C4. 하단 "Command N agents · @ to direct" 일괄 입력, 아래 명령 바의 @ 대상 지정 (board.jpg r3c3)

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

- A1~A7 (2026-10-18): 원본 agent1/board-0.jpg, agent1/resume-top.jpg, agent3/diagrams-0.5.png, board.jpg r2c2·r3c2 / 내 것 `v2/A1-A7-board-chrome.png`, `v2/A2-home.png`. 창 전체가 캔버스, 위쪽 바·좌우 세로 막대·아래 명령 바·브랜치 칩·배율이 떠 있다. 프로젝트(폴더)마다 작업공간 묶음, 홈은 프로젝트 카드 목록. 아래 명령 바 `@all echo` 가 셸 2개에 들어간 것 확인.
  - 남은 차이: 설정 버튼은 아직 안내 문구만(설정 화면 없음). 사용량 알약은 재설정 시각 대신 "usage"(N 에서). 도형·다이어그램 버튼은 H6·S 전까지 임시 동작. 오른쪽 막대 스튜디오 입구는 O 전까지 별도 창. 원본 마이크 자리는 보내기 버튼으로 바꿈.
- A8: 원본 agent1/board-0.jpg, board.jpg r1c1 / 내 것 `v2/A8-spawn-menu.png`, `v2/A8-drop-placeholder.png`. CLI 목록(로그인 셸 command -v 로 설치 확인, All agents 로 전체), 고르면 점선 자리표시가 마우스를 따라오고 누른 자리에 노드. 남은 차이: 로고 대신 글자 배지.
- A9·A10: 원본 board.jpg r1c1, node-kanban.mp4 40초(속성 패널은 왼쪽 막대 옆에 붙음) / 내 것 `v2/A9-A10-title-text-panel.png`, `v2/A10-sticky-panel.png`. 글자·스티키·이미지는 헤더 없음, 몸통 끌어 이동, 두 번 눌러 편집, Delete 로 삭제. 패널: 색 6+사용자 색, 글꼴 4, S/M/L/XL, 정렬, 불투명도, 앞으로/뒤로/복제/삭제. 1차 확인: vim 열고 닫기, sleep 에 Ctrl-C 정상.
- B1: 원본 agent1/resume-mid.jpg / 내 것 `v2/B1-node-headers.png`. 글자 배지+꺾쇠(메뉴), 상태 점, 짧은 이름(Ada, Pip... 자동, 이름 두 번 눌러 바꿈, 1차 "프로그램 - 폴더" 이름은 시작할 때 바꿈), 역할은 이름 옆 흐린 글씨, 모노 대문자 상태 알약(READY/RUNNING/NEEDS YOU/EXITED, 일시정지면 PAUSED), 권한 배지(실행 인자에 자동 승인 옵션이 있으면 AUTO), 다시 시작·복제·닫기. 남은 차이: 원본 글리프는 CLI 로고, 여기는 글자 배지.
- B2·B3: 원본 agent1/board-0.jpg 오른쪽, voice.jpg r3c3, board.jpg r2c2 / 내 것 `v2/B2-B3-group-frame-links.png`, `v2/B2-group-collapsed.png`. 팀마다 둥근 프레임(색 점·이름·개수·"N running"/idle·꺾쇠), 머리를 끌면 멤버가 함께 이동(디버그 dragGroup 로 4개 노드 frame 이 +1100 이동 확인), 꺾쇠로 접기, 오른쪽 클릭 메뉴(이름 바꾸기·풀기·모두 닫기). 노드 메뉴 Link To 로 노드·그룹 사이 곡선, 선 위로 점이 흐름(CAKeyframeAnimation). 남은 차이: 연결선은 메뉴로만 만든다(원본은 오케스트레이터 Connect 로 생김, C 에서).
- B4: 원본 voice.jpg r3c3 / 내 것 `v2/B4-close-confirm.png`. `/close @backend` 또는 그룹 메뉴 → 아래 바 위에 "이름들: about to close 4 consoles" + Close 4 / Cancel. 고친 것: 숨긴 홈 화면 호스팅 뷰가 클릭을 가로채던 문제(숨겨지면 hitTest nil).
- F1·F2: 원본 agent1/resume-top.jpg, node-resume.jpg / 내 것 `v2/F1-F2-resume-toast.png`, `v2/F2-resumed.png`. 한 번 실행됐고 세션 id 가 있는 claude·codex 콘솔은 다시 열 때 띄우지 않고 기다린다(헤더 ON HOLD, 본문 위 "Resume last conversation? Yes/No" 말풍선). 오른쪽 위 토스트 Yes → 0.35초 간격으로 차례로 "Restored - picking up the last conversation..." 을 찍고 이어 띄운 뒤 전체 보기, No → 세션 id 를 지우고 새로 시작, × → 토스트만 닫고 노드별로 답. 확인은 /tmp/symsample 에 claude 노드 2개(세션 id 만 넣고 대화는 보내지 않음)로 했다: 대기 2 → Yes → 대기 0, 두 노드 claude 실행. 남은 차이: 원본은 기다리는 동안에도 CLI 가 새로 떠 있다가 Yes 에 이어 가지만, 여기는 답할 때까지 띄우지 않는다(같은 대화가 두 번 열리지 않게).
- E1·E2: 원본 node-composer.jpg, agent1/comp.jpg / 내 것 `v2/E1-composer-card.png`, `v2/E2-composer-booting.png`, `v2/E2-composer-group.png`. 아래 바 Group → 바 위 카드 팝오버: 편집 가능한 팀 이름, 역할 칩 8개(고르면 팀 이름·Spawn 색이 역할 색), 4열 타일(누르면 그 타일만 다음 CLI), Fill all(설치된 CLI 배지), − N + (1~12, 타일 즉시 늘고 줆), Spawn N. 결과는 역할 색 그룹 프레임 + 0.18초 간격으로 노드가 차례로 생김, 비어 있는 자리(기존 노드 오른쪽)에 놓고 전체 보기. 6개 셸로 확인. 남은 차이: 원본 Fill all 줄에는 CLI 가 더 많다(여기는 이 맥에 깔린 것만).
- C1~C4: 원본 board.jpg r1c3~r3c3, board.mp4 7~16초 / 내 것 `v2/C1-orchestrator-empty.png`, `v2/C2-orchestrator-connect.png`, `v2/C2-orchestrator-wired-links.png`, `v2/C3-C4-orchestrator-rows.png`. 오른쪽 막대 삽입 메뉴 Orchestrator → 캔버스에 놓기. 빈 상태 "No agents wired"+Spawn agent, Connect → 그룹 칩(누르면 강조색)·콘솔 칩, 보드의 콘솔을 누르면 연결/해제, Done. 연결은 작업공간 links 에 저장되고 그룹 프레임·콘솔로 점 흐르는 곡선. 행: 배지·이름·CLI·상태 알약, 마우스를 올리면 보드에서 보기·일시정지. 아래 "Command N agents · @ to direct": 그룹 2개+콘솔 1개 연결 후 전체 11개 전송, "@testers ..." 는 6개만. 재실행 후에도 연결 유지.
  - 고친 것: 같은 콘솔에 연달아 보내면 앞의 Enter 전에 다음 글이 섞였다 → 콘솔마다 보내기를 줄 세움("echo one"/"echo two" 따로 실행 확인). 그룹 프레임 hitTest 가 프레임 밖(왼쪽·위)의 클릭까지 가로채던 문제.
  - 남은 차이: 원본은 오케스트레이터를 어디서 만드는지 영상에 안 나와 삽입 메뉴에 넣었다. 진행 표시는 READY 수/전체.

## 막힌 것
