STATUS: IN_PROGRESS

# Symboard 6차 진행표

기준 커밋 `4594a2c` (5차 완료본). 5차 테스트 수 147.
모든 시험은 Finder 와 같은 환경으로 띄운 앱에서 한다:
`env -i HOME=$HOME USER=$USER LOGNAME=$USER SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin SYMBOARD_HOME=/tmp/symv6-N build/Symboard.app/Contents/MacOS/Symboard &`
확인은 `orca computer`(`scripts/input/ui.sh`) 실제 클릭·키 입력. 원본 대조 그림은 `docs/screens/v6/compare/`(커밋 안 함).

## 버전 확인

| 때 | codex | claude |
|----|-------|--------|
| 시작 | 0.157.1 | 2.1.302 |

## 실제 CLI 질문 수 (한도 10)

| # | 항목 | 대상 | 질문 |
|---|------|------|------|
| 1 | 5번 메모리 스캔 | Memory → Scan repo → Claude Code(/tmp/symsample) | (스캔 질문) |

합계: 1

## 고칠 것

- [x] 1. 새 노드 배치: 놓을 때 그룹 프레임·다른 노드와 겹치지 않게(원본 확인 먼저)
  - 원본 장면: `board.mp4` 1.5~5초(2장/초). 미리보기를 그룹 사이 빈 틈에 놓고, 커진 노드가 양쪽 그룹과 겹치지 않는다. 겹쳐 놓는 장면 없음 → 피하는 쪽으로 맞춤(DECISIONS 6차-1).
  - 바꾼 것: `CanvasLayout.obstacles`(팀은 그룹 프레임 하나, 나머지는 노드)·`nearestFree`(장애물 네 변에 붙인 x·y 후보 조합 중 가장 가까운 빈 자리) 를 Core 에 추가. `place()` 가 화면 안으로 맞춘 뒤 겹치면 밀고 `reveal`. 글·도형은 제외. 단위 테스트 5개.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-1): Open folder → /tmp/symsample → 명령 바 `spawn 4 shell` → `add an orchestrator wired to group 1` → 별 → Claude Code → 오케스트레이터 바로 아래 빈 곳(창 254,569) 클릭 → Dax 가 오케스트레이터 아래에 24pt 띄워 놓이고 그룹 프레임과 겹치지 않음. 비교 그림 `compare/1-placement.png`.
- [x] 2. board: 연결 중 그룹 테두리 위 "Click to wire group" 알약
  - 원본 장면: `board.mp4` 9~12초(4장/초). Connect 중 그룹 테두리가 주황 점선이 되고 윗변 가운데에 "⊕ Click to wire group" 알약. 누르면 실선 + 주황으로 채운 "Group wired" 알약.
  - 바꾼 것: `GroupFrameView.wireState`(none/offer/wired)와 `WirePillView`(접근성 단추). `layoutGroups` 가 Connect 중인 오케스트레이터와 이 팀의 연결 여부로 상태를 정하고, 알약을 누르면 `toggleWire`. Connect/Done·연결 바꿈 때 그룹을 다시 그린다. 안내 문구에 "a group's pill" 추가.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-1, 배율 60%): 오케스트레이터 Connect → 그룹 윗변 "Group wired"(이미 연결됨) → 알약 클릭(좌표) → 점선 + "Click to wire group", 오케스트레이터 "0 agents · 0 groups" → 다시 클릭 → "Group wired", "4 agents · 1 group" → Done. 비교 그림 `compare/2-wire-offer.png`, `2-wire-wired.png`.
  - 덧붙임: 첫 실행에서 배율 60% 의 오케스트레이터 Connect 를 좌표로 세 번 눌렀는데 반응이 없었다(접근성 누르기는 됨). 로그를 넣고 다시 띄운 뒤에는 60%·48%·버튼 줌·끌어 옮긴 뒤 모두 첫 클릭에 반응해 재현하지 못했다. 마지막 점검에서 다시 본다.
- [x] 3. node-git: 커밋 뒤 팝오버가 열린 채 결과를 보이게(키 창 문제를 다른 방법으로)
  - 원본 장면: `node-git.mp4` 7.5초. 커밋 뒤 팝오버가 열린 채 CHANGES "Working tree clean · Nothing to commit.", RECENT 맨 위에 새 커밋, 바닥 "Committed 5 files · pushed".
  - 4차에서 닫은 이유(PLAN-4 119줄): 남은 변경이 없으면 입력칸이 사라져, 팝오버 창이 초점 받을 곳 없는 키 창으로 남았고 orca 가 Esc·Cmd+Q 를 "초점 창 없음" 으로 거부했다.
  - 1차 시도(키 창만 본 창으로 돌림): AppKit 키 창은 본 창이 됐지만(`drive.sh windows`) orca 는 여전히 거부했다. 버림.
  - 바꾼 것: 팝오버를 닫지 않는다. 커밋 결과 줄이 생기고 작업 트리가 깨끗해지면 결과 줄이 SwiftUI 초점을 받는다(`focusable`·`focused`, 초점 테두리 없음). Esc 는 `onExitCommand` 로 팝오버를 닫는다. 본 창의 Esc 처리(`closeTopOverlay`)도 git 팝오버부터 닫는다. 쓰지 않게 된 `onCommitted` 를 지웠다.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-3, 로컬 bare 원격이 있는 /tmp/symgit6): Open folder → 브랜치 칩 → 입력칸에 "Add d and e" → Return → 팝오버가 열린 채 Working tree clean·RECENT "Add d and e 4 seconds ago"·"Committed 2 files · pushed"(원격 `366bd24`) → Esc(orca 가 받음) → 팝오버 닫힘 → 명령 바 클릭 → "echo after-commit" 타이핑이 들어감. 비교 그림 `compare/3-git-after-commit.png`.
- [x] 4. node-kanban: Today 를 누르면 날짜 입력으로, 일정 기본색
  - 원본 장면: `node-kanban.mp4` 6~9초(1장/초). NEW CARD 에서 Today/Tomorrow/Next week 칩 중 하나를 누르면 그 줄이 "02/09/2026" 날짜 칸과 ⊗ 지우기로 바뀐다. 20·31초 일정 창: 색 점 6개(호박·초록·파랑·보라·분홍·청록), 처음 고른 것은 첫 색(호박).
  - 바꾼 것: 칸반 카드 창의 날짜 줄이 날짜가 없으면 빠른 칩, 있으면 고칠 수 있는 날짜 칸(`DatePicker` field)과 지우기 단추가 된다. 테두리 상자로 묶었다. 캘린더 색을 원본 순서·색(영상에서 뽑은 값)으로 바꾸고 첫 색 호박이 기본.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-3): 오른쪽 막대 Insert → Board → 캔버스 클릭 → Backlog Add card → "Research market trends" 타이핑 → Today 클릭 → 줄이 "10/18/2026" 칸 + ⊗ 로 바뀜 → ⊗ → 칩으로 돌아옴 → Today → Add card → 카드에 "Today". Insert → Calendar → 캔버스 클릭(보드 아래로 밀려 놓임, 1번 확인) → New → "Coordinate" → 첫 점(호박)에 고리 → Add event → 18일 칸에 호박색 막대. 비교 그림 `compare/4-kanban-date.png`, `4-calendar-color.png`.
- [x] 5. node-memory: 목록 줄 켜짐 체크, 마우스 올리면 휴지통, 스캔 단계 Wrap up
  - 원본 장면: `node-memory.mp4` 9초(스캔: "Launch — Read the repo — Write facts — Wrap up", 오른쪽 "10 facts"), 17초(목록: 줄마다 오른쪽 주황 체크, 바닥 "12 active entries — …").
  - 바꾼 것: `MemoryNote.disabled`(없으면 켜짐, 예전 저장분 그대로) 와 `isEnabled`. 목록 줄을 `MemoryListRow` 로: 오른쪽 체크로 켜고 끔(끈 줄은 흐림), 마우스를 올리면 고치기·휴지통. 바닥 "N active entries · …". 메모리 카드는 켜진 것만 보낸다. 스캔 단계에 Wrap up 과 단계 사이 선, 머리에 "N facts" 알약. 끝나면 Wrap up 을 0.8초 보인 뒤 검토로. 단위 테스트 2개.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-5, /tmp/symsample): Memory → Scan repo → Scan with Claude Code(질문 1) → 8초 "Launch now", 20초 "Launch done / Read the repo now"(`compare/5-memory-scan.png`) → 35초 REVIEW 9 of 9 → Add 9 to memory → 목록 9줄 모두 체크, "9 active entries" → 둘째 줄 체크 클릭 → 흐려지고 체크 빈 원, "8 active entries", 그 줄에 고치기·휴지통(`compare/5-memory-list.png`) → 휴지통 클릭 → 그 줄이 사라짐.
  - 못 본 것: Write facts·Wrap up 단계는 13초 간격 확인 사이에 지나가 화면으로 보지 못했다(접근성 상태로만 단계 이름 4개 확인). 마지막 점검에서 다시 스캔하지는 않는다(질문 한도).
- [x] 6. node-loops: 목표 기본값을 원본과 같은 종류로
  - 원본 장면: `node-loops.mp4` 12초. STOP 에서 "When a goal is met" 를 켜면 "A command passes" 가 먼저 골라져 있고 칸은 비어 있다(안내 글만). 고르는 칩은 두 개(A command passes · An agent judges). 스위치는 글 왼쪽.
  - 바꾼 것: 목표 기본 종류를 "agent" 에서 "command" 로(새 루프·초기화 둘 다). 칩 순서를 원본처럼 command → agent 로 하고, 우리만 있는 "Output shows text" 는 맨 뒤로. STOP·BEHAVIOR 스위치를 글 왼쪽에 두고 글을 눌러도 켜지게.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-5): 오른쪽 막대 Loops → Start from scratch → 아래로 스크롤 → "When a goal is met" 글 클릭 → 스위치 켜짐, "A command passes" 골라짐, 칸 비어 있음(안내 "e.g. swift test"). 비교 그림 `compare/6-loops-goal.png`.
- [x] 7. node-webtiles: 지구 도구 고른 뒤 끌어서 타일 크기
  - 원본 장면: `node-webtiles.mp4` 0~1.5초(2장/초). 지구 도구 → 캔버스를 끌면 주황 사각형과 모서리 손잡이 4개 → 놓으면 그 크기의 웹 타일.
  - 바꾼 것: 웹 도구일 때 캔버스 `mouseDown` 이 바로 놓지 않고 `sizingDrag` 를 시작한다. 끄는 동안 주황 사각형 + 흰 모서리 손잡이를 그리고, 놓으면 `placeWeb(in:)` 이 그 사각형(최소 320×220)에 타일을 놓는다. 24pt 미만으로 끌면 클릭으로 보고 예전처럼 기본 크기로 놓는다(이때는 1번 규칙으로 밀림). 직접 그린 자리는 밀지 않는다.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-7): 지구 도구 클릭 → 캔버스 (300,200)→(900,600) 끌기 → 600×400 웹 타일, 주소 칸에 초점(`compare/7-webtile-drag.png`). 지구 도구 → 빈 곳 클릭 → 820×600 기본 크기, 첫 타일 오른쪽으로 24pt 띄워 놓임(state.json 으로 크기 확인).
  - 못 본 것: orca 끌기는 한 번에 끝나 끄는 중의 사각형 화면은 찍지 못했다.
- [x] 8. node-accounts: 팝오버 머리 CLI 아이콘, 없는 CLI 는 흐리게 + "설치되지 않음"
  - 원본 장면: `node-accounts.mp4` 0초. 머리에 "accounts" 와 CLI 아이콘 다섯(지금 것은 동그란 배경, 나머지 흐림), 오른쪽 끝 닫기 X.
  - 바꾼 것: 공용 `CLIIconStrip`(AgentCatalog.swift)과 Core `CLIIconState`(ready·unsupported·missing, 안내 문구; 단위 테스트 3개). 계정 팝오버 머리에 Claude·Codex·Gemini·Cursor·Qwen 다섯을 글자 배지로(로고 그림 없음). 이 맥에 없는 CLI 는 회색·투명·사선, 누르면 "… is not installed on this Mac. Install `gemini` …" 안내만 뜨고 띄우지 않는다. 깔렸지만 계정 프로필을 다루지 않는 CLI 는 "not supported yet" 안내. 닫기 X 추가. 팝오버가 글 길이만큼 늘어나게(`fixedSize`) — 안내가 뜨면 경고 글이 잘리던 것을 같이 고쳤다.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-7; 이 맥에 gemini·qwen·cursor-agent 없음): 위 계정 단추 → 다섯 아이콘, 셋은 흐리고 사선 → Gemini 클릭 → 안내 줄, "0 live" 그대로, gemini 프로세스 없음 → Codex 클릭 → 안내 사라지고 "Used by new Codex consoles". 비교 그림 `compare/8-accounts-icons.png`.
- [x] 9. node-composer: Fill all 도 8번 규칙
  - 원본 장면: `node-composer.mp4` 4초. "Fill all" 옆에 CLI 아이콘이 두 줄(5개 + 2개 + 더하기)로, 고른 것은 동그란 테두리.
  - 바꾼 것: Fill all 을 8번의 `CLIIconStrip` 로 바꿔 아는 CLI 8개를 모두 6개씩 두 줄로 늘어놓는다. 없는 CLI 는 흐리게 사선, 누르면 카드 안에 "not installed" 안내만(타일은 그대로, 띄우지 않음). 깔린 것을 누르면 예전처럼 모두 채우고 안내를 지운다. 타일을 눌러 바꾸는 것은 깔린 것 사이에서만 돈다(예전대로).
  - 확인한 실제 입력(`env -i`, /tmp/symv6-7): Group → 컴포저 → Fill all 줄에 C·X·G·A·Cu·Q / O·>_ (G·A·Cu·Q·O 사선) → G 클릭 → "Gemini CLI is not installed on this Mac…" 안내, 타일 Claude 4개 그대로, "0 live" → >_ 클릭 → 타일 넷 모두 Shell, 안내 사라짐 → Esc. 비교 그림 `compare/9-composer-fillall.png`.
- [x] 10. studio-code: 저장 뒤 "Saved"
  - 원본 장면: `studio-code.mp4` 17~19초. 고치면 크기 옆 "• Edited", Save 를 누르면 단추가 흐린 "✓ Saved" 로 바뀌고 Edited 가 사라진다.
  - 바꾼 것: 코드 스튜디오 Save 단추가 저장 직후(바뀐 것 없음 + 저장 메모) "✓ Saved" 로 바뀐다. 다시 고치면 Save 로. 크기 옆 초록 "Saved" 글은 단추와 겹쳐 빼고, 실패 메모만 남겼다. 마크다운 스튜디오는 원래 자동 저장 + "Saved 시각" 이라 그대로.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-7): 오른쪽 막대 Code studio → README.md → 마지막 줄 클릭 → End → " (edited)" 타이핑 → "• Edited", 단추 Save → Cmd+S → 단추 "✓ Saved", 파일 마지막 줄에 "(edited)" 저장됨(확인 뒤 표본 파일은 되돌림). 비교 그림 `compare/10-code-saved.png`.
- [ ] 11. studio-diagrams: 화면 맞춤이 다이어그램만, 노드 고르면 노드 편집 패널
- [ ] 12. studio-documents: GENERATE PDF 누르면 작은 메뉴 먼저
- [ ] 13. studio-markdown: 카드 바닥 "Open in Studio · PDF" 글 단추
- [ ] 14. teams: 오른쪽 기본 패널 Fleet / Structure 두 카드
- [ ] 15. voice: 명령 바 보드 명령 THREAD 패널, 프리셋에 콘솔 말고 다른 노드도

## 마지막 점검

- [ ] 7단계 한 번에 통과

## 막힌 것

(없음)
