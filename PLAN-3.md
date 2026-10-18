STATUS: DONE

# Symboard 3차 진행표

기준 커밋 `d5d1f37` (2차 완료본). 2차 테스트 수 72.
확인은 `orca computer`(`/Applications/Orca.app/Contents/Resources/bin/orca`) 실제 클릭·키 입력으로 한다. DebugBridge(`scripts/drive.sh`)는 상태를 깔아 두는 데만 쓴다.
스크린샷은 `docs/screens/v3/<항목번호>-<이름>.png`. 체크한 항목 아래에 "재현 방법 / 고친 원인 / 확인한 실제 입력" 을 적는다.

## 고칠 것

- [x] 1. 칸반 "+ Add card" 등 터미널이 아닌 모든 노드 안쪽 버튼이 실제 클릭(배율 100%·50%)에 반응
  - 재현: 51% 에서 TO DO "Add card" 실제 클릭 두 번 → 반응 없음. 같은 자리 100% 는 됨. SwiftUI 탭 위치를 찍어 보니 실제 (911,272) 대신 (465,139) = 정확히 ×0.51.
  - 원인: NSHostingView 가 조상 NSScrollView 의 배율을 빼지 않고 마우스 위치를 계산한다. 노드 본문 호스팅 뷰를 `CanvasHostingView`(이벤트 위치를 배율 보정해 넘김)로 바꿨다. 덧붙여 `.plain` 단추는 글자·아이콘 픽셀만 눌려 50% 의 캘린더 "+ New" 가 빗나가서, 라벨 사각형 전체가 눌리는 `.plainHit` 로 모두 바꿨다. 시작할 때 복원된 오케스트레이터는 창 컨트롤러를 못 잡아 Connect 가 죽어 있어서 `MainWindowController.current` 로 고쳤다.
  - 확인(실제 클릭, 50%): 칸반 Add card → 모달 → 제목 입력 → Add card 저장, 카드 동그라미 완료 토글, + Column 입력창, 열 메뉴 · 체크리스트 항목 토글, Add an objective 입력·저장 · 캘린더 다음 달, + New, 날짜 칸, 일정 제목 입력·Add event 저장 · 스티키·도형 두 번 눌러 편집·입력 · git 파일 체크 토글 · 웹 탭 +, 포트 칩 :3000, 표시 크기 메뉴, 인스펙터 열기·Console 탭 · 코드 파일 Open in studio · 오케스트레이터 Connect/Done. 100%: 칸반 Add card·제목 입력, 캘린더 + New, git 체크, 웹 탭 +, Connect/Done, Open in studio. 문서 카드는 안쪽 단추가 없다.
- [x] 2. 모달을 Esc 로 닫은 직후 오른쪽 막대 버튼 첫 클릭이 무시됨
  - 재현: 오른쪽 막대 루프 → Esc → 체크리스트 아이콘 실제 클릭 → 반응 없음, 다시 누르면 열림. 화면을 찍어 보니 Esc 뒤에도 루프 모달이 그대로 열려 있었다.
  - 원인: 루프·메모리·스튜디오·미션 맵 모달에 Esc 처리가 없었다. 첫 클릭은 모달의 어두운 배경을 눌러 모달을 닫는 데 쓰였다. 키 감시에서 Esc 가 오면 맨 위 모달을 닫고 보드에 초점을 돌리게 했다(`closeTopOverlay`).
  - 확인(실제 입력): 루프 아이콘 클릭 → Esc 키 → 모달 닫힘(화면) → 체크리스트 아이콘 한 번 클릭 → 팝오버 열림. 코드 스튜디오 열기 → Esc → 체크리스트 한 번 클릭 → 열림.
- [x] 3. 컴포저 카드가 아래로 자라 아래 버튼 줄·명령 입력을 가림 → 위로 자라고 화면 안에 머묾
  - 재현: Group → + 실제 클릭 → 타일 줄이 늘며 카드가 아래로 커져 New console 줄과 명령 입력을 덮고, 화살표가 Group 아래로 내려감.
  - 원인: SwiftUI `.popover` 가 내용이 커질 때 위쪽을 고정했다. 컴포저를 Group 단추에 붙인 AppKit `NSPopover`(preferredContentSize 로 크기 따라감)로 바꿔 단추 쪽을 고정했다.
  - 확인(실제 클릭): Group → + 를 같은 자리에서 8번 → 매번 "+" 가 커서 밑에 그대로 있고 카드가 위로 자람, 12개에서도 화면 안. Esc 로 닫힘.
- [x] 4. 컴포저 개수 늘리면 새 타일이 Fill all 값이 아니라 Claude 로 생김
  - 재현: 새 타일은 "바로 앞 타일 값" 을 따랐다. 타일 하나를 따로 Claude 로 돌린 뒤 늘리면 Claude 가 생겼다(Fill all 값이 무시됨).
  - 원인: 컴포저가 마지막 Fill all 값을 기억하지 않았다. `fillChoice` 를 두고 `Composer.resize`(단위 테스트 3개)가 Fill all → 앞 타일 → 기본 CLI 순으로 고른다.
  - 확인(실제 클릭): Fill all Shell → 다섯째 타일을 눌러 Claude 로 → + 두 번 → 새 타일 둘 다 Shell. Fill all Claude → + → Claude.
- [x] 5. 새로 띄운 셸이 첫 명령 전까지 RUNNING 으로 보임 → READY
  - 재현: 이 환경에서는 New console 셸이 3초 뒤 READY 로 바뀌어 그대로 재현되지 않았다. 판정이 "마지막 출력 3초 안이면 RUNNING" 이라, 프롬프트를 다시 그리는 셸 설정(시계·비동기 git 상태 등)이면 입력을 기다리는 동안에도 RUNNING 이 된다는 것을 코드에서 확인했다.
  - 원인/고침: 일반 셸은 출력 시각 대신 터미널의 앞 프로세스 그룹(`tcgetpgrp`)이 셸 자신인지로 판정한다. 셸이 앞에 있으면 READY, 명령이 돌면 출력이 없어도 RUNNING. 첫 출력 전 3초는 STARTING. 단위 테스트 4개.
  - 확인(실제 입력): New console 클릭 → 3초 뒤 READY(첫 명령 전) → 명령 입력에 `sleep 6` + Return → 2초 뒤 RUNNING → 9초 뒤 READY.
- [x] 6. 캔버스 가장자리에 놓은 노드가 왼쪽 막대·아래 버튼 줄 밑으로 들어감
  - 재현: 체크리스트 아이콘 → Board → 캔버스 왼쪽 끝 클릭 → 칸반 왼쪽이 왼쪽 막대 밑으로 들어감(1번 재현 때 같이 봄).
  - 원인: 놓기는 누른 점을 중심으로 그대로 놓았다. 위 70·좌우 80·아래 110 포인트를 뺀 보이는 영역 안으로 옮기고(`CanvasLayout.fit`, 단위 테스트 3개), 영역보다 크면 들어오게 축소한다.
  - 확인(실제 클릭, 100%): Board 를 왼쪽 막대 바로 옆(x 110) 클릭 → 막대 오른쪽·버튼 줄 위로 놓임. 별 → Shell → 오른쪽 아래 구석 클릭 → 오른쪽 막대 왼쪽·버튼 줄 위로 놓임.
- [x] 7. `SYMBOARD_HOME` 을 새 폴더로 줘도 이전 프로젝트(symclaude)로 열림 → 모든 상태를 SYMBOARD_HOME 아래로, 없으면 홈 화면
  - 재현: 빈 `/tmp/symv3` 로 띄우자 위쪽 프로젝트가 symclaude. `defaults read local.symboard.app` 에 `lastCwd = /tmp/symclaude` 가 남아 있었고, 빈 작업공간이 이 값을 프로젝트로 받았다.
  - 원인/고침: lastCwd·lastAgentChoice·docTiming·창 위치를 UserDefaults 대신 상태 폴더의 `prefs.json`(`Prefs`, 단위 테스트 1개)에 둔다. 빈 작업공간에는 프로젝트를 추측해 붙이지 않고, 노드가 하나도 없으면 홈 화면으로 시작한다. 폴더를 열면 처음 생긴 빈 작업공간에 붙인다.
  - 확인(실제 입력): 빈 `/tmp/symv3h` 로 실행 → Projects 화면(Open folder 만) → Open folder 클릭 → 열기 창에서 Cmd+Shift+G, `/tmp/symsample` 입력, Return, Return → 보드가 symsample 로 열림, `prefs.json` 에 lastCwd. Cmd+Q 후 다시 실행 → symsample 로 열림.
- [x] 8. 사용량 알약 글자가 "usage" 와 "resets 5:00pm" 사이를 오감
  - 재현: 재실행할 때마다 처음 몇 초는 "usage", 로그 훑기가 끝나면 "resets 5:00pm"(이번 시험에서 두 가지를 모두 봄). 훑기가 실행 3초 뒤 시작해 12초쯤 걸린다.
  - 원인/고침: 값이 없을 때 다른 낱말("usage")을 보였다. 늘 "resets …" 꼴로 보이고 모르면 `resets –:––` 자리표시(`UsagePill`, 단위 테스트 3개). 마지막으로 구한 묶음 끝을 prefs.json 에 두어 재실행 직후에도 같은 값을 보이고, 훑기는 바로 시작하며 5분마다 다시 한다.
  - 확인(실제 입력): Cmd+Q·재실행을 3번, 각각 2초·17초에 화면 → 여섯 번 모두 "resets 5:00pm". 캐시가 없던 첫 실행들은 여섯 번 모두 "resets –:––" 로 같았다.
- [x] 9. 이름 없는 접근성 button 40개 이상 → 모든 아이콘 버튼에 accessibilityLabel
  - 재현: 노드 10개 보드에서 orca 접근성 트리에 이름 없는 `button` 86개.
  - 원인: 아이콘 단추에 이름이 없었고(.help 는 이름이 아님), 더해서 orca 는 SwiftUI 단추 이름을 아예 읽지 못했다(accessibilityLabel·Button("글자")·.borderless 모두 실험해 봄). 단추마다 `.tip("…")`(설명+이름) 또는 `.axName("…")`(글자 단추)을 달고, 그 안에서 이름 붙은 투명 AppKit 대역을 겹쳤다(DECISIONS.md). 대역은 클릭을 통과시키고 접근성 누르기를 실제 클릭으로 바꾼다.
  - 확인(실제 입력): 같은 보드 트리에서 이름 없는 단추 86 → 0(이름 있는 단추 144, `9-ax-tree.txt`). 칸반 카드 모달·컴포저 팝오버를 연 상태도 0. 대역 위 실제 클릭: 배율 −, 칸반 Add card, 체크리스트 토글, 별 메뉴 Shell 행 → 모두 동작. orca 의 접근성 누르기(element-index)로 "Zoom in" → 40%→50%. SwiftUI 팝오버 창(별 메뉴 등)은 orca 스냅샷에 들어오지 않아 그 안 이름은 트리로 확인하지 못했다(코드로만 달았음).
- [x] 10. 루프 템플릿 7개 이름·설명 다시 쓰기 (원본과 같은 "Commit checkpoint" 등)
  - 고침: Pulse check · Nudge when quiet · Red-line fixer · Suite watchdog · Save point · Second look · Three-line hour 로 이름과 설명을 새로 썼다. 시작 조건·간격·지시문(역할)은 그대로. 이름 입력란 예시도 바꿨다.
  - 확인(실제 클릭): 오른쪽 막대 루프 아이콘 → 시작 화면에 새 이름 7개, 설명이 잘리지 않음.
- [x] 11. 루프 시작 화면 모달 아래 절반이 빔 → 내용 높이에 맞춤
  - 재현: 루프 아이콘 클릭 → 템플릿 카드 아래로 모달 높이 720 까지 빈 칸(10번 화면에서도 보임).
  - 원인: 높이 상한 `.frame(maxHeight: 720)` 을 배경보다 먼저 달았고, 시작 화면·목록이 늘 늘어나는 ScrollView 였다. 배경을 먼저 달고 상한을 뒤로, 시작 화면·목록은 `ViewThatFits`(들어가면 스크롤 없이, 넘치면 스크롤)로 바꿨다. 양식(form)은 길어서 그대로 스크롤.
  - 확인(실제 클릭): 루프 아이콘 → 모달이 Start from scratch 아래에서 끝남. 템플릿 클릭 → 양식이 스크롤과 함께 정상.
- [x] 12. "Try @all git status" 안내 알약이 팝오버 뒤로 비침
  - 재현: 코드 스튜디오·루프 모달을 열면 알약이 모달 위에 그대로 보임(1·11번 화면).
  - 고침: 모달·팝오버(별 메뉴·삽입·도형·git·사용량·계정·미션 맵·루프·컴포저·스튜디오·메모리·다이어그램·설정 패널)가 하나라도 열리면 `chrome.overlayOpen` 이 켜지고 알약을 숨긴다.
  - 확인(실제 입력): 접근성 트리의 "Try …" 단추 수 — 처음 1 → 삽입 팝오버 클릭 0 → Esc 1 → 루프 모달 0 → Esc 1.
- [x] 13. 2차에서 자동 확인 못 한 것 실제 입력 확인: 칸반 카드 끌어 옮기기, 메모리 카드 Send, git 메시지 생성, 메모리 Rewrite, 에이전트 판단 루프 목표
  - [x] 13b 메모리 카드 Send: Memory → Write memory → Commands·제목·본문 입력 → Save memory → Place card on board → 카드의 "Pick a console" 메뉴에서 Maya → Send 1 → 카드에 "Sent 1 to Maya", Maya 프롬프트에 메모 본문이 붙여넣어짐(Enter 끔이라 실행 안 됨). 모두 실제 클릭·타이핑.
  - [x] 13d 메모리 Rewrite(실제 CLI 1회, /tmp/symsample): 편집 화면에서 Rewrite 클릭 → 스피너 → 약 2~3분 뒤 본문이 "# Run the sample / From the repo root: ```sh python3 src/hello.py``` / Expected output …" 로 바뀜.
  - [x] 13c git 메시지 생성(실제 CLI 1회, /tmp/symsample): git 카드 메시지 칸의 반짝이 단추 클릭 → 약 12초 뒤 "Expand README and add greet function to hello.py". 커밋은 하지 않았다.
  - [x] 13e 에이전트 판단 루프 목표(/tmp/symsample): 루프 → Nudge when quiet → 지시문 `echo still here` → Pick consoles·Maya → (스크롤해서) When a goal is met → An agent judges·Claude, 목표 "the console has printed hello, world" → Create loop. 판정이 NO 인 동안 지시문이 4번 들어갔고, 명령 입력으로 `@Maya python3 src/hello.py` 를 보내자 다음 판정에서 "goal met at 15:33:36" 으로 루프가 꺼졌다. 판정 CLI 는 "1회" 가 아니라 5번 불렸다(조용해질 때마다 판정하는 설계라서). 이때 orca 의 스크롤도 창 없이 와서, 창 없는 스크롤을 그 자리 뷰로 넘기도록 고쳤다.
  - [x] 13a 칸반 카드 끌기: orca drag 로 카드·노드 머리를 끌어도 아무 일이 없었다. 이벤트를 찍어 보니 orca 의 끌기 이벤트는 창 없이(화면 좌표) 온다. 창 없는 마우스 이벤트를 그 자리의 우리 창으로 다시 겨누는 감시를 넣었다(실제 마우스는 늘 창이 있어 영향 없음). 또 카드 끌기를 시스템 끌어 놓기(.draggable, 실제 커서만 따라감) 대신 SwiftUI DragGesture + 열·카드 자리 계산(`Board.dropTarget`, 단위 테스트 4개)으로 바꿨다. 확인(실제 끌기): 100% 에서 DOING 의 Write tests → DONE, 50% 에서 DONE → DOING, 노드 머리 끌기로 칸반 이동.

## 실제 입력으로 다시 확인할 흐름

- [x] F1. 별 → Shell → 캔버스 클릭 → 아래 입력 `echo hi` + Return → 출력 — 새 상태 폴더 /tmp/symv3f, 홈 화면에서 Open folder 로 /tmp/symv3repo. "Sent to 1 console", Ada 에 hi, READY.
- [x] F2. Group → Testers → 개수 5 → Fill all Shell → Spawn → TESTERS 프레임 → `@all echo ok` → "Sent to 6 consoles" — 6개 모두 ok 출력, 모두 READY. (처음 한 번은 Spawn 아래 가장자리를 눌러 팝오버만 닫혔다. 내 좌표 실수.)
- [x] F3. Cmd+Q → 다시 실행 → 노드·그룹 같은 자리 — state.json 의 노드 이름·좌표·팀 비교가 같음, 화면에 TESTERS 프레임 그대로.
- [x] F4. 오케스트레이터 → Connect → 그룹 → Done → 연결선 → 오케스트레이터 입력으로 명령 — 삽입 메뉴 Orchestrator → 캔버스 클릭 → Connect → Testers 행 → Done → 그룹까지 곡선, 입력에 `echo from orch` → "Sent to 5 agents", 5개 모두 출력.
- [x] F5. 미션 맵 → 콘솔 고르기 → Go to → 이동 — 도구 메뉴 Mission Map → Maya 행 → 오른쪽 Go to the console → 모달 닫히고 Maya 가 선택된 채 화면 가운데(80%).
- [x] F6. 루프: 템플릿 → 만들기 → 카운트다운 → 지금 실행 → 대상 콘솔 입력 — Pulse check → 지시문 `echo pulse`, Pick consoles·Maya → Create loop → 목록에 "in 14:59" → ▶ → Maya 에만 `echo pulse` / pulse.
- [x] F7. 스티키·도형·펜: 놓기, 색 바꾸기, 그리기, 지우개 — 삽입 메뉴 Sticky note → 캔버스 클릭 → 종이 색 파랑, 도형 메뉴 원 → 캔버스 클릭 → 선 색 주황, 펜 → 끌기로 선 1개(state 의 획 0→1), 지우개 → 선 위 클릭 → 획 0. orca 의 끌기는 시작·끝 두 점만 보내 지우개 끌기는 선을 건너뛰어 클릭으로 확인했다.
- [x] F8. git 카드: bare 원격 예제 레포에서 파일 고르고 Commit & Push — /tmp/symv3repo(원격 /tmp/symv3repo-remote.git)에서 README 를 고친 뒤 아래 왼쪽 main 칩 → 카드에 README.md 1개 → 메시지 입력 → Commit & Push 1 file → 로컬·원격 모두 939aa5b, 작업 트리 깨끗.
- [x] F9. 웹 타일: 포트 칩으로 열기, 해상도 프리셋, 인스펙터 타일 — /tmp/symv3web 에 python http.server 8000, 왼쪽 막대 웹 → 캔버스 클릭 → :8000 칩 → 페이지 보임 → 표시 크기 메뉴 Phone 393×852 → 좁은 폭으로 보임, 벌레 단추 → Inspector 타일(Elements 트리)과 연결선. 인스펙터 타일은 웹 타일 오른쪽에 붙어 생겨 오른쪽 막대에 일부 가린다(놓기 자리 조정은 클릭으로 놓는 노드에만 적용).
- [x] F10. 코드 스튜디오 편집 → Save → 디스크 반영. 마크다운 Reading/Source/Graph — 오른쪽 막대 코드 → src 펼치기 → app.py → 끝에 한 줄 입력 → Save → "Saved", 디스크의 app.py 에 반영. 마크다운 스튜디오 README → Reading → Source(원문) → Graph(README—notes 연결 2개).

## 시험 도구 메모

- `scripts/input/ui.sh` 가 orca computer 를 감싼다(클릭·두 번 클릭·타이핑·키·끌기·상태). `scripts/input/cgclick.swift`(CGEvent 직접 전송)는 이 터미널에 손쉬운 사용 권한이 없어 이벤트가 전달되지 않았다. 쓰지 않는다.
- orca 는 클릭 직전에 그 자리의 접근성 요소를 확인하고, 창이 바뀌었다고 보면 클릭을 거부한다(`window_not_focused`). 모달·팝오버가 열리는 클릭은 들어간 뒤에 이 오류를 낼 수 있어 다시 보내지 않는다.

## 막힌 것

(없음)

## 충돌 기록

이번 회차(14:13 이후) 새 `Symboard-*.ips` 없음. 남아 있는 13:02·13:39·13:43 기록은 이 회차 시작 전 것이다.

## 완료 기준 확인

- `swift build -c release` 통과, `swift test` 92개 통과(2차 72개).
- 고칠 것 1~13 모두 실제 입력으로 확인. 흐름 F1~F10 모두 통과.
