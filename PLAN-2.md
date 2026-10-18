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

- [x] D1. 도구 메뉴에서 여는 큰 모달·부제·필터 칩·검색 (teams.jpg, agent1/teams-30.jpg)
- [x] D2. 오케스트레이터→팀→콘솔 곡선 그래프 + 오른쪽 상세 + Go to 줌 (teams.jpg r2~r3)

## J. 루프

- [x] J1. 템플릿 카드 시작 화면 + 처음부터 만들기 (node-loops.jpg r1)
- [x] J2. 생성 모달: 템플릿 칩·이름·지시문·시작 조건 카드 3개·간격 칩·대상·멈춤 토글 3개·목표 판정·요약 문장 (agent2/l-mid.jpg)
- [x] J3. 목록 행: 상태 점·횟수·요약·카운트다운·지금 실행·토글·메뉴, 오른쪽 막대 배지 (agent2/l-end.jpg)

## H·I. 칸반·스티키·체크리스트·캘린더·도형·펜

- [x] H1. 칸반 4열·열 머리·No cards·Add card·+ Column·드래그 이동 (node-kanban.jpg, agent2/kanban-1~3.jpg)
- [x] H2. 카드 추가 모달(제목·메모·마감 칩·우선순위)과 카드 모양 (agent2/k-newcard.jpg)
- [x] H3. 오른쪽 막대 삽입 팝오버 Checklist/Board/Calendar, 체크리스트 원형 카운터 (node-kanban.jpg r1)
- [x] H4. 캘린더 노드: 월 격자·오늘·이벤트 팝오버·칩 (node-kanban.jpg r3)
- [x] H5. 스티키: 헤더 없는 종이·손글씨체·접힌 모서리·종이 색 8개 팝오버 (node-kanban.jpg)
- [x] H6. 도형(사각·원·마름모·화살표)·속성 팝오버·도형 안 텍스트·스케치풍 (agent2/k-shape.jpg)
- [x] I1. 펜 팝오버(색 9+사용자·굵기 5)·스무딩 곡선·십자 커서·지우개, 이미지 헤더 없음 (node-ink.jpg)

## L·M·N.

- [x] L1. git 카드 헤더·변경 목록 체크·None·메시지 생성·Commit & Push·완료 상태·히스토리 (node-git.jpg, agent2/g-end.jpg)
- [x] M1. 웹 타일 탭·뒤/앞/새로고침·주소줄·시작 화면 포트 칩 (node-webtiles.jpg, agent2/w-open.jpg)
- [x] M2. 표시 크기 프리셋·기기 배지·인스펙터 별도 타일+연결선 (agent2/w-end.jpg)
- [x] N1. 사용량 팝오버: 링·주간 막대·히트맵·통계·토큰 상세 (node-usage.jpg, agent2/u-1.jpg)

## O·P·Q. 스튜디오

- [x] O1. 보드 위 둥근 패널·어두운 뒤·왼쪽 열·닫으면 카드 노드·현재 프로젝트 자동 연결 (agent3/code-16.png, studio-code.jpg r3c3)
- [x] P1. 코드 스튜디오: 트리·브레드크럼·언어 배지·줄/바이트·편집·줄 번호·Saved·Insert 코드 카드 (agent3/code-16.png)
- [x] Q1. 마크다운: 검색·트리·words/min·Reading/Source/Graph·Export PDF (agent3/markdown-0.8.png)
- [x] Q2. 링크 그래프 힘 기반 배치·강조·클릭 이동 (agent3/md-graph.png)

## K·R·S. 에이전트 생성

- [x] K1. 메모리 모달·레포 필터·편집 화면·보드에 카드로 놓기 (node-memory.jpg, agent2/m-edit.jpg)
- [x] K2. 레포 스캔(CLI 백그라운드)·단계 표시·제안 검토 (agent2/m-review.jpg)
- [x] R1. 문서 스튜디오 왼쪽(CLI·깊이·템플릿)·빈 상태 (agent3/documents-2.6.png)
- [x] R2. 생성 중 칩·Stop·실시간 종이·결과 종이·보드 문서 카드 (agent3/doc-gen.png, documents-19.png)
- [x] S1. 다이어그램 팝오버(CLI·스타일·유형 6·자유 설명·시작 도형) (agent3/diag-pop-1.2.png)
- [x] S2. 생성 중 칩·자리표시→등장·결과 보드 직접 손그림·서식 팝오버 (agent3/diagrams-2.5.png, diagrams-12.5.png)

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
- D1·D2: 원본 teams.jpg, agent1/teams-30.jpg / 내 것 `v2/D1-mission-map.png`, `v2/D2-mission-console-detail.png`, `v2/D2-mission-team-detail.png`. 위쪽 도구 메뉴 Mission Map → 보드 위 큰 모달(뒤 어둡게). 부제 "N orchestrator · N teams · N consoles · N working", 필터 칩 All/Working/Needs you/Idle/Done(개수), 검색, 왼쪽 열 Command center·오케스트레이터 → 가운데 팀 → 오른쪽 콘솔 곡선(오케스트레이터에 안 닿는 콘솔은 Command center 에서 점선), 아래 범례. 오른쪽 상세: 선택 없음=상태별 개수와 구조 요약, 팀=Show this team on the board, 콘솔=Go to the console·Pause·Kill·지금 상태와 그 상태로 지난 시간·소속(그룹/오케스트레이터/Command center). 한 번 누르면 보기, 두 번 누르면 모달 닫고 그 노드로 이동.
  - 고친 것: 고정 크기 모달이 창 크기를 줄여 버렸다(NSHostingView 크기 제약) → 최대 크기로 바꾸고 호스팅 뷰 sizingOptions 를 비움. 시험 중 실수로 `yes` 를 백그라운드로 띄워 바로 pkill 로 끔.
  - 확인: 모달 뒤 왼쪽 위에 보이던 "ready" 알약들은 그리기 흠이 아니라 창 왼쪽 밖으로 걸친 오케스트레이터 노드의 오른쪽 끝이었다(이름 쪽은 창 밖).
- J1~J3: 원본 node-loops.jpg, agent2/l-mid.jpg, agent2/l-end.jpg / 내 것 `v2/J1-loops-templates.png`, `v2/J2-loop-form.png`, `v2/J3-loop-list.png`. 오른쪽 막대 루프 버튼 → 모달. 루프가 없으면 틀 카드 7개(이름·설명·지시문은 직접 씀) + Start from scratch. 양식: 틀 칩 줄, 이름, 지시문, 시작 조건 카드 3개(타이머 5m~2h 칩+스테퍼 / 조용해지면 초 / 출력 문구), 대상(모든 콘솔·나중 것 포함 / 골라서), 멈춤 토글 3개(횟수·시간·목표: 출력 문구 / 명령 성공 / 에이전트 판단+CLI), 다른 작업공간에서도 계속 토글, 아래 요약 문장과 시간당 횟수(SymboardCore LoopSummary, 단위 테스트). 목록 줄: 상태 점·이름·횟수·요약·지시문·카운트다운·지금 실행·토글·메뉴(고치기·삭제), 오른쪽 막대 배지.
  - 실행 확인: Kai 셸에 "조용해지면 4초, echo nudge, 목표=`test -f /tmp/symsample/DONE`" 루프 → 3회 보냄 → DONE 파일을 만들자 다음 확인에서 "goal met" 으로 꺼짐(4 runs). 에이전트 판단은 claude -p(도구 없음)에 YES/NO 를 묻는 방식으로 만들었고 응답 해석은 단위 테스트로만 봤다(실제 호출은 사용량 때문에 아직 안 함).
  - 남은 차이: 원본의 "Typed into each targeted console" 아래 미리보기 문구 위치 등 작은 배치. 1차의 노드 하나 대상 규칙은 그대로 동작(대상 목록이 없으면 nodeID).
- H1·H2: 원본 node-kanban.jpg, agent2/k-shape.jpg(보드), agent2/k-newcard.jpg / 내 것 `v2/H1-kanban.png`, `v2/H2-new-card.png`. 기본 4열 BACKLOG/TO DO/IN PROGRESS/DONE, 열 머리(색 점·제목·개수·⋯ 이름 바꾸기/지우기), 빈 열 "No cards", 열 아래 + Add card, 오른쪽 + Column. 카드: 완료 원·제목·마감 칩(Today/Tomorrow/날짜)·우선순위 칩·왼쪽 색 띠, 누르면 고치기. 카드 모달: 제목·메모·마감(Today/Tomorrow/Next week, 지우기)·우선순위 None/Low/Med/High, 고칠 때 삭제. 1차 글자 카드는 처음 옮기거나 고칠 때 새 카드 형식으로 바뀐다(Board.move, 단위 테스트).
  - 카드 끌어 옮기기는 SwiftUI draggable/dropDestination 으로 만들었고 자동 확인은 모델 이동(디버그 kanbanMove)까지만 했다. 실제 마우스 끌기는 확인하지 못했다.
  - 고친 것: 창이 뒤에 있을 때 캔버스 첫 클릭이 창 활성화로만 쓰여 놓기가 안 되던 문제(acceptsFirstMouse).
- H3·H4: 원본 agent2/k-shape.jpg(체크리스트·캘린더), node-kanban.mp4 20~28초(일정 팝오버) / 내 것 `v2/H3-insert-menu-checklist.png`, `v2/H4-calendar.png`, `v2/H4-calendar-event.png`. 오른쪽 막대 삽입 팝오버: Checklist/Board/Calendar(+ 스티키·오케스트레이터). 체크리스트: 남은 수 원형 카운터(진행 링), 빈 상태 "No objectives / Add one to begin" + 흐린 자리 줄, 아래 + Add an objective. 캘린더 노드: 월 이름·+ New·Today·위/아래, 월요일 시작 6주 격자(Board.monthGrid 단위 테스트), 오늘 강조색 원, 날짜 누르면 일정 팝오버(제목·날짜·종일·색 6개·메모·Cancel/Add event), 일정 칩 누르면 고치기·삭제. 재실행 후 일정 유지 확인. 노드 안 날짜 글은 영어 로캘로 고정.
- H5: 원본 node-kanban.mp4 40·44초, agent2/k-shape.jpg / 내 것 `v2/H5-sticky-paper.png`. 헤더 없는 머스터드 종이(기본 #C9A227), 옅은 줄무늬, 오른쪽 아래 접힌 모서리, 그림자, 손글씨 흰 글씨. 고르면 왼쪽 막대 옆 PAPER 색 8개+사용자 색, 앞으로/뒤로/복제/삭제(A10 과 같은 패널). 두 번 눌러 편집. 남은 차이: 원본 선택 표시는 종이 모양을 따라가지만 여기는 노드 사각형 테두리.
- H6: 원본 agent2/k-shape.jpg(화살표), GAPS H 도형 설명, studio-diagrams 의 손그림 상자 / 내 것 `v2/H6-shapes-panel.png`. 왼쪽 막대 도형 버튼 → 사각형·원·마름모·화살표 팝오버 → 캔버스 클릭으로 놓기. 헤더 없는 노드, 선은 노드마다 고정 씨앗으로 두 번 겹쳐 흔든 손그림(Neat/Sketch/Rough), 도형 안 글자 바로 편집(두 번 눌러). 속성 패널: 선 색·배경 색(없음 포함)·굵기 S/M/L·실선/파선/점선·거칠기·모서리(사각형)·글자 크기·글꼴·불투명도·레이어/복제/삭제.
  - 남은 차이: 원본은 끌어서 크기를 정하며 그리지만 여기는 클릭으로 기본 크기를 놓고 손잡이로 키운다. 둥근 사각형의 손그림 모서리는 깎은 팔각형으로 흉내 냈다.
- I1: 원본 node-ink.jpg / 내 것 `v2/I1-pen-panel-ink.png`. 펜을 켜면 왼쪽 막대 옆 COLOR 9개+사용자 색, WIDTH 5단계. 획은 모든 노드 위의 벡터 층(획마다 CAShapeLayer)에 그려서 이미지 위에서 시작해 보드까지 이어진다. 점 줄이기+Catmull-Rom 베지어로 부드럽게(Ink, 단위 테스트), 십자 커서. 지우개: 누르거나 끌면 가까운 획을 지운다(선분 거리, 단위 테스트; 5→4 확인). 이미지 노드는 헤더 없이 사진만.
  - 남은 차이: 1차에서 이미지 노드 안에 저장된 표시는 그대로 이미지에 그려지고, 새 획은 보드 층에 저장된다.
- L1: 원본 node-git.jpg, agent2/g-end.jpg / 내 것 `v2/L1-git-card-changes.png`, `v2/L1-git-card-pushed.png`. 원본처럼 아래 왼쪽 브랜치 칩을 누르면 카드가 뜬다(보드의 git 노드도 같은 카드). 헤더: 레포 이름·브랜치·synced/↑↓/local, 히스토리·Finder 열기·새로고침·닫기 원형 버튼. CHANGES 고른 수/전체 +더한 줄 −뺀 줄, 파일마다 체크·상태 글자(M/U/A/D/R)·폴더, None/All. 메시지 칸(비우면 "Add 2 files, update 1 file" 같은 기본 메시지) + 반짝이 버튼(claude -p 로 한 줄 메시지, 도구 없음). "Commit & Push N files" 하나 → Committing... → Pushing... → "Committed 3 files · pushed". RECENT 3개(상대 시간), 히스토리(제목·짧은 해시·작성자·시간). 파싱·기본 메시지·상대 시간 단위 테스트(GitInfo).
  - 실행 확인: /tmp/symsample 에 /tmp/symsample-remote.git(bare)을 origin 으로 두고 4개 변경 중 3개만 골라 커밋 → bare 레포 main 이 같은 커밋으로 올라감, 뺀 파일은 그대로 남음. add -A 대신 고른 경로만 add·commit(pathspec).
  - 남은 차이: 메시지 생성 버튼은 실제 CLI 호출 확인을 아직 하지 않았다(사용량 아끼려고 R·S 시험 때 함께 보기로). 새 파일 줄 수는 +/− 에 들어가지 않는다.
- M1·M2: 원본 node-webtiles.jpg, agent2/w-open.jpg, agent2/w-end.jpg / 내 것 `v2/M1-web-start-page.png`, `v2/M2-web-device-inspector.png`. 탭 줄(탭마다 WKWebView, 제목, 닫기, +), 뒤로·앞으로·새로고침, 주소줄(":3000"·"5173" 처럼 포트만 써도 localhost, WebAddress 단위 테스트). 빈 탭은 시작 화면: localhost 입력 + 포트 칩 :3000/:3001/:4200/:5173/:8000/:8080 + 빠른 열기 카드 3개. 표시 크기 메뉴: Fit to tile + 모니터 24/27/32" 4K·노트북·휴대폰·태블릿 → 그 해상도로 배치하고 pageZoom 으로 타일에 맞춤(인스펙터로 본 본문 폭 1918px), 위에 기기 배지 "24\" 4K 1920 × 1080". 탭·고른 탭·크기는 저장되어 재실행 후 유지.
  - 인스펙터: 별도 타일로 뜨고 웹 타일과 점 흐르는 연결선으로 이어짐. WKWebView 내장 인스펙터를 타일에 넣는 공개 API 가 없어서 페이지에 JS 를 돌려 직접 만들었다: Elements(DOM 나무, 누르면 페이지에 강조 테두리 + 상자 모델·margin/padding/display), Console(console.log/warn/error 와 오류를 메시지 처리기로 받아 표시, 아래 입력으로 식 실행). /tmp/symweb 를 python http.server 8765 로 띄워 확인("page ready 8765", "demo warning" 수집).
  - 남은 차이: 원본 인스펙터는 Safari 웹 인스펙터 전체(Network·Sources·Timelines 등)이고 여기는 Elements·Console 두 가지뿐이다.
- N1: 원본 node-usage.jpg, agent2/u-1.jpg / 내 것 `v2/N1-usage-overview.png`, `v2/N1-usage-tokens.png`. 위쪽 알약 "resets 5:00pm"(지금 5시간 묶음 끝 추정) → 팝오버. CLI 탭(Claude/Codex), 링(한도 % 는 "?"), 현재 세션 토큰·재설정 시각(추정), 최근 7일, 지난 12개월 활동 칸, 통계(자주 쓴 모델·총 토큰·세션·활동일·가장 활발한 날·가장 긴 세션·연속일 최장/지금), 최근 30일 150k 넘는 문맥 비율·4개 이상 동시 세션 비율. 막대 버튼 → tokens: 30일 합계·가장 바쁜 날·상위 에이전트, All tokens/In + out/Output 막대 그래프(날짜 라벨 겹치지 않게 7일 간격), 에이전트별 비율(최근 30일/전체), 읽는 중이면 "Reading local session logs". 통계 계산은 SymboardCore UsageStats(단위 테스트: 묶음 시작 정시 내림·연속일·세션 수·문맥 비율).
  - 이 맥 로그 898개를 15~17초에 읽음(백그라운드). 숫자는 3.2K/1.9B 처럼 줄여 표시.
  - 남은 차이: 원본의 한도 %(현재 세션·주간 모델별)는 로그에 없어 표시하지 못한다. CLI 의 /usage 화면을 숨은 터미널로 긁는 방법은 시도하지 않았다(사용 중인 세션 화면을 건드릴 위험). 주간 막대는 한도 대신 최근 7일 토큰.
  - 고친 것: 콘솔이 하나도 없으면 1초 상태 틱이 돌지 않아 알약·루프가 멈추던 문제(시작할 때 세션 관리자 생성). 날짜 표시를 영어 형식으로 고정.
- O1·P1: 원본 agent3/code-16.png, studio-code.jpg r3c3 / 내 것 `v2/O1-P1-code-studio.png`, `v2/O1-P1-board-cards.png`. 별도 창 대신 보드 위 둥근 패널(뒤 어둡게, 위쪽·아래 막대와 좌우 막대는 그대로 위에 보임), 오른쪽 막대 코드·마크다운·문서 버튼으로 진입, 지금 프로젝트 폴더에 자동 연결. 왼쪽 열: 강조색 배지·스튜디오 이름·프로젝트 이름·+ (폴더 더하기), 종류별 아이콘 나무(선택 줄 강조). 코드: 브레드크럼·언어 배지·"8 lines · 187 B"·• Edited/Saved, 줄 번호 막대와 입력 중 구문 색이 있는 편집기, Add folder·Save(⌘S)·Insert(줄 번호 코드 카드). 닫으면 고친 내용을 저장하고 열었던 파일을 보드에 작은 카드로 남긴다(카드의 ↗ 로 다시 열기). 디버그로 hello.py 를 고쳐 Save 후 디스크 내용 확인.
- Q1·Q2: 원본 agent3/markdown-0.8.png, agent3/md-graph.png / 내 것 `v2/Q1-markdown-reading.png`, `v2/Q1-markdown-source.png`, `v2/Q2-link-graph.png`. 파일 검색, .md 확장자 숨긴 나무, 위쪽 "README.md 57 words · ~1 min", Reading/Source/Graph, Add to Board, Export PDF(macOS 저장 시트, 디버그로 /tmp 에 27KB PDF 생성 확인). Reading: 제목 아래 짧은 강조색 밑줄, 강조색 모노 인라인 코드, 둥근 카드형 표, NOTE/TIP 콜아웃(Markdown.html 단위 테스트). Source: 줄 번호+마크다운 색. Graph: "Link graph · N notes", 힘 기반 배치(ForceLayout, 같은 입력이면 같은 결과, 단위 테스트), 현재 문서 강조색, 마우스를 올리면 이웃과 선 강조, 누르면 그 문서를 Reading 으로 연다.
  - 남은 차이: 원본은 닫을 때 카드로 줄어드는 움직임이 있는데 여기는 움직임 없이 카드가 생긴다. 새 카드 자리가 기존 노드와 겹칠 수 있다.
- K1·K2: 원본 node-memory.jpg, agent2/m-review.jpg, agent2/m-edit.jpg / 내 것 `v2/K1-memory-empty.png`, `v2/K1-memory-list.png`, `v2/K1-memory-edit.png`, `v2/K1-memory-card.png`, `v2/K2-scan-pick.png`, `v2/K2-scanning.png`, `v2/K2-review-real-scan.png`. 아래 바 Memory → 모달. 헤더 Scan repo / New memory, 레포 칩(이 레포 N / 모든 레포 N), 빈 상태(같은 두 버튼), 목록(분류 태그·제목·본문·연필), 편집(분류 탭 6개·제목·본문·Rewrite·적용 범위 이 레포/모든 레포·Delete/Cancel/Save memory), "Place card on board" → 메모리 카드(고른 메모를 고른 콘솔에, Enter 여부 선택, Send 를 눌렀을 때만).
  - 레포 스캔: CLI 고르기(Claude/Codex) → `claude -p --output-format stream-json --verbose --include-partial-messages --no-session-persistence --permission-mode dontAsk --tools Read,Glob,Grep` 를 레포 폴더에서 백그라운드로 실행, 단계 표시(Launch → Read the repo(도구 사용 이벤트) → Write facts(글 조각)), 한 줄 JSON 사실을 FactStream(단위 테스트)으로 꺼내 실시간으로 늘린다. 검토: "8 of 8 selected", 체크·분류·제목·본문·연필, Discard / Add N to memory.
  - 실제 호출: /tmp/symsample 에서 claude 로 2회. 1회째는 앱이 죽었다(내 보조 함수 이름 tag(_:) 가 SwiftUI View.tag 와 겹쳐 모달이 자기 안에 끝없이 들어감 → categoryTag 로 바꿔 해결, 가짜 제안으로 재현·확인). 2회째 약 25초에 사실 8개(실제 경로·명령 인용) → 모두 추가해 state.json 에 분류와 함께 저장 확인.
  - 남은 차이: 이번 실행에서는 에이전트가 사실을 마지막에 한꺼번에 써서 목록이 끝에 한 번에 찼다(조각 단위 표시 자체는 단위 테스트로만 확인). 메모리 카드의 Send, Rewrite 버튼은 자동 확인하지 않았다(Rewrite 는 사용량 때문에 실행하지 않음).
- R1·R2: 원본 studio-documents.jpg, agent3/documents-2.6.png, agent3/doc-gen.png, agent3/documents-19.png / 내 것 `v2/R1-documents-empty.png`, `v2/R2-documents-writing.png`, `v2/R2-documents-result-real.png`, `v2/R2-document-card.png`. 오른쪽 막대 문서 버튼 → 패널. 왼쪽: 부제, CLI 배지 줄(Claude/Codex), Quick/Balanced/Thorough 와 지난 소요 시간("0:17"/"not timed"), 문서 종류 7개(이름·설명은 직접 씀: Overview, Getting started, Architecture, README, API guide, Data model, Security notes) + 다 되면 초록 체크·생성 중 점, 아래 자유 요청 입력. 빈 상태: 아이콘·제목·설명·"Generate with <CLI>"·라이브러리 저장 안내. 생성 중: "Writing with Claude Code · 15s" 칩, Stop, 흰 종이 카드에 스켈레톤 줄 → 본문이 0.25초마다 바뀌어 들어감(innerHTML 교체), 종이 아래 CLI 상태줄. 결과: 흰 종이+그림자, 강조색 밑줄 제목, 강조색 인라인 코드, NOTE/TIP 콜아웃, 카드형 표, "331 words · ~2 min read"·종이/원문 보기·재생성·보드로 보내기·Export PDF(저장 시트). 보드 카드: DOCUMENT 라벨+CLI 배지+제목+단어 수+종이 미리보기. 라이브러리는 ~/Library/Application Support/Symboard/docs/<레포>-<해시>/<종류>.md (사용자 레포에 파일을 만들지 않음).
  - 실제 호출: /tmp/symsample 에서 claude Quick Overview 1회, 17초, 331낱말 문서 저장, PDF 76KB 생성 확인. `v2/R2-documents-writing.png` 는 글이 3초 안에 다 들어와 중간 화면을 잡지 못해 디버그로 앞부분 글을 넣어 찍은 것이다(그리는 경로는 같음).
  - 남은 차이: 원본은 종이 아래에 CLI 터미널 화면이 비치지만 여기는 진행 한 줄만 보인다. CLI 배지 옆 "+"(다른 CLI 추가)는 없다.
- S1·S2: 원본 studio-diagrams.jpg, agent3/diag-pop-1.2.png, agent3/diagrams-2.5.png, agent3/diagrams-12.5.png / 내 것 `v2/S1-diagram-popover.png`, `v2/S2-claude-is-drawing.png`, `v2/S2-diagram-real-ink.png`, `v2/S2-diagram-colorful-bands.png`, `v2/S2-diagram-node-format.png`. 왼쪽 막대 다이어그램 버튼 → 팝오버: MODEL(Claude/Codex), STYLE Ink/Colorful, FROM YOUR PROJECT 6개(Architecture, User flow, Data flow, Components, Request lifecycle, State flow), Describe + Generate, STARTER SHAPES(Flow/Steps/Branch/Mind map, 에이전트 없이 바로 놓음). 생성: 위쪽 "Claude Code is drawing ×" 칩 + 흐린 빈 상자·화살표 자리표시 → 에이전트가 낸 JSON(제목·그룹·노드·간선, DiagramSpec 파서·층 배치 단위 테스트) → 자리표시를 지우고 그룹 상자 → 제목 → 노드 → 화살표 순서로 0.09초 간격 등장 → 전체 보기. 결과는 보드의 진짜 객체: 손그림 둥근 사각형(제목+부제), 바깥 요소는 타원, 점선 그룹 상자+라벨, 라벨 달린 손그림 화살표(도형 위 층), 손글씨 제목. 노드를 고르면 H6 서식 패널(선·배경·굵기·선 모양·거칠기·모서리·글자 크기·글꼴·불투명도·레이어/복제/삭제).
  - 실제 호출: /tmp/symsample 에서 claude Architecture 1회(약 40초), 노드 9·그룹 3·간선 9 의 다이어그램이 그려짐(`v2/S2-diagram-real-ink.png`). 그때 그룹 상자끼리 겹치고 일부 글이 잘려서, 그룹마다 세로 띠를 주는 배치로 고치고(단위 테스트 groupBoxesDoNotOverlap) 같은 내용을 손으로 옮긴 JSON 으로 다시 그려 확인(`v2/S2-diagram-colorful-bands.png`, 추가 CLI 호출 없음). 색 채움 그룹 아래에 화살표가 묻혀서 화살표를 도형 위 층으로 옮김.
  - 남은 차이: 원본 서식 패널은 글꼴 8종, 여기는 4종. 원본은 노드가 나타난 뒤 층 배치로 미끄러지듯 정리되는 움직임이 있는데 여기는 처음부터 제자리에 나타난다.

## 막힌 것
