STATUS: DONE

# Symboard 9차 진행표

기준 커밋 `79b1f15` (8차 완료본). 8차 테스트 수 204.
목표: AI 가 보드를 혼자 다뤄 세션을 이어 띄우고(세션1 → 세션2 → 세션3), 넘긴 프롬프트와 그림을 보드에 남긴다. 혼자 끝없이 띄우지 못하게 멈춤 장치를 둔다.
시험은 앱 상태 폴더를 따로 둔 인스턴스(`SYMBOARD_HOME=<scratchpad>/symv9-N`)에서 한다. 사용자가 띄워 둔 앱은 건드리지 않는다.

## 버전 확인

| 때 | claude | codex |
|----|--------|-------|
| 시작 | 2.1.314 | 0.166.0 (9차 시작 전 시험 중 업데이트 질문에 시험 입력이 들어가 0.163.0 에서 올라감) |
| 끝 | 2.1.314 | 0.166.0 |

## 실제 claude·codex 질문 수 (한도 12)

| # | 때 | 무엇 |
|---|----|------|
| 1 | 10-31 01:41 | Shift+Enter 시험 뒤 그냥 Enter 확인. "Reply with only the word OK." |
| 2 | 10-31 01:58 | codex `-c developer_instructions` 확인(`codex exec`). "Where are you running? Answer in one word." |
| 3 | 10-31 02:05 | codex 보드 도구 시험. 시험 폴더 경로가 길어 소켓 경로 초과로 실패(아래 3번) |
| 4 | 10-31 02:08 | codex 보드 도구 시험 다시. 같은 질문 |
| 5 | 10-31 02:18 | 완료 기준. claude Ada 에 두 단계 넘겨주기 시험 질문 |
| 6 | 10-31 02:19 | 완료 기준. Ada 가 넘긴 claude Pip 이 받은 프롬프트 |
| 7 | 10-31 02:31 | 화면 시험(사용자 요청). 다이어그램 + hand_off + 메모 두 줄 요청 |
| 8 | 10-31 02:35 | 화면 시험 다시(겹침 고친 뒤). 같은 요청 |
| 9 | 10-31 02:37 | 화면 시험. 개수 제한 1 에서 한 번 더 hand_off |

합계: 9

## 할 일

- [x] 1. 콘솔 안 Shift+Enter 줄바꿈 (사용자 보고)
  - 원래: SwiftTerm 은 Return 을 Shift 와 상관없이 `insertNewline` → CR 로 보내 claude·codex 가 바로 보냈다. 명령 바(8차 4번)는 정상.
  - 고침: `KeyInput.editBytes` 에 Shift+Return·Shift+키패드 Enter → ESC CR(Meta+Enter). 창 키 감시에서 콘솔이 초점일 때 조합 중 글자를 먼저 확정하고 보낸다. Option·Cmd·Ctrl 이 같이 눌리면 건드리지 않는다.
  - 확인: ESC CR 을 바로 보내 claude 2.1.314(`aaa`/`bbb` 두 줄), codex 0.166.0(두 줄), zsh(실행하지 않고 다음 줄) 모두 줄바꿈. 새 번들에서 claude 콘솔에 실제 Shift+Return 키 이벤트(`CGCLICK_TOPID=1 cgclick key 36 shift`) 두 번 → 입력 줄에 `first line / second line / third`. 그냥 Return → 보내짐, 답 OK(질문 1).
- [x] 2. claude 폴더 신뢰 화면이 위쪽에 겹쳐 그려지는 문제 (사용자 보고, SwiftTerm)
  - 원래: 신뢰 질문에서 ↑↓ 로 고르면 화면 맨 위에 지난 선택지 조각이 남았다. claude 출력을 `script` 로 받아 셸 콘솔에 그대로 `cat` 해도 같은 모양 → 터미널 해석 문제.
  - 원인: claude 는 그리기 전에 `ESC 7`(커서 저장) 뒤 kitty 키보드 질의 `ESC[?u` 를 보낸다. SwiftTerm 은 접두 글자와 상관없이 `CSI u` 를 커서 되돌리기(SCORC)로 처리해 커서를 저장 위치(위쪽)로 옮겼고, 그 뒤 상대 이동(`ESC[4A` 등)으로 고치는 줄이 맨 위에 찍혔다.
  - 고침: 접두 글자(? > < =)가 붙은 `CSI u` 는 무시(`Vendor/SwiftTerm/PATCHES.md` 7).
  - 확인: 같은 녹화 재생과 실제 claude 신뢰 화면에서 ↓↑↓ → 위쪽 조각 없음, 선택 표시만 바뀜. 평소 claude 첫 화면(대체 화면)도 그대로.
- [x] 3. codex 도 Symboard 안에 있음을 알고 보드 도구를 쓴다 (사용자 요청)
  - 원래: codex 콘솔에는 환경 변수(SYMBOARD_NODE_ID 등)만 있고 안내·도구가 없었다.
  - 고침: `BoardTools.codexArgs` — `-c developer_instructions=<claude 와 같은 안내>`, `-c mcp_servers.symboard.command=<번들 symboard-mcp>`, `-c mcp_servers.symboard.env={SYMBOARD_SOCKET, SYMBOARD_CALLER}`. 새로 띄울 때와 `codex resume` 모두. 사용자 `~/.codex/config.toml` 은 그대로. 설정 스위치("Let agents open consoles on the board")를 같이 따른다.
  - 더 고침: 유닉스 소켓 경로는 103바이트까지인데 상태 폴더 경로가 길면 소켓을 못 열었다(첫 시험에서 codex 가 "Socket path too long"). 길면 임시 폴더에 `symboard-<폴더 해시>.sock`.
  - 확인: `codex exec -c developer_instructions=…` 로 안내를 따름(질문 2). `codex mcp list -c …` 에 symboard 가 enabled 로 보임. 새 번들, codex 콘솔에 "Where are you running? Then use the symboard tools to open a shell console with the prompt `echo codex-ok` …"(질문 4) → `Called symboard.spawn_console` → 보드에 셸 Pip, `read_console` → 답 "the Symboard shell printed codex-ok".
- [x] 4. 작업공간 폴더가 없으면 홈 폴더로 몰래 넘어가지 않고 알린다
  - 원래: `TerminalSession.start` 가 폴더가 없으면 홈 폴더에서 띄웠다. 사용자 보드의 작업공간 폴더 `/tmp/symwork`(8차 시험 폴더)가 지워져 모든 콘솔이 홈에서 떴고, claude 가 홈 폴더 신뢰를 매번 물었다(홈 폴더 신뢰는 저장되지 않음: `~/.claude.json` 의 `/Users/jikwon` 은 hasTrustDialogAccepted false). 홈 아래 Music·Pictures 를 훑어 macOS 가 Symboard 에 사진 보관함·Apple Music 접근을 물었다.
  - 고침: `SessionManager.launch` 에서 폴더가 없으면 띄우지 않고 콘솔에 노란 "Folder not found: <경로>" 와 안내, 상태 EXITED, 아래 알림 "Folder not found: … · open a folder from Home". 폴더를 고친 뒤 Restart 로 다시 띄운다. 보드 도구(spawn_console·hand_off)는 부른 콘솔 폴더가 없으면 열지 않고 이유를 답한다.
  - 확인(symv9-5): `/tmp/symwork-gone` 셸 콘솔 → 위 문구, 상태 exited(`relay.png` 의 Pip). 그 콘솔이 부른 spawn_console → "The folder /tmp/symwork-gone does not exist, so no console was opened."
- [x] 5. 멈춤 장치: 이어 띄우기 최대 단계, 에이전트가 연 콘솔 최대 개수, 설정 창에서 바꿈
  - 만든 것: `AgentLimits`(SymboardCore, 단위 테스트 4개). 단계 = spawned·handoff 선을 거슬러 위에 있는 콘솔 수(카드는 지나가기만), 개수 = 들어오는 spawned·handoff 선이 있는 콘솔 수. 기본 4단계·12개, 설정 창 AGENTS 아래 "Max chain steps"·"Max consoles opened by agents"(1~20). 넘으면 아래 확인 띠 "<이름> wants to open another console: chain step 5 is past the limit of 4." 와 Allow once / Cancel. Cancel·2분 무응답·다른 확인이 이미 떠 있으면 거절하고, 도구는 "The user did not allow another console … Do not retry; tell the user." 를 답한다.
  - 확인(symv9-5, prefs 에 단계 2): Ada → Maya(1) → Iris(2) 는 바로 열림. Iris 의 hand_off → 확인 띠(`limit-ask.png`) → Cancel → 거절 답, 콘솔 없음. 다시 → Allow once → Dax 열림.
- [x] 6. 넘겨주기 도구 hand_off: 프롬프트 카드 + 새 세션 + 선
  - 만든 것: `hand_off(prompt, agent=claude, title?, name?)`. 부른 콘솔 옆 빈 칸에 카드(노란 스티커 "<title> → <새 이름>" + 프롬프트)와 새 콘솔을 한 덩어리로(카드 왼쪽, 콘솔 오른쪽, 같은 줄) 놓고, 부른 콘솔 → 카드 → 새 콘솔을 handoff 선(점이 흐르는 보통 선)으로 잇고, 준비되면 프롬프트를 보낸다. 새 콘솔도 같은 도구를 받아 다시 넘길 수 있다.
  - 처음 판은 카드와 콘솔 자리를 따로 찾아, 줄이 바뀌면 콘솔이 줄 맨 왼쪽으로 떨어졌다(`relay.png` 의 Dax) → 둘을 합친 폭으로 한 번에 자리를 찾게 고침.
  - 확인(symv9-6, MCP 서버에 바로): Ada → Step 1 → Pip(echo relay-1) → Step 2 → Maya(relay-2) → Step 3 → Iris(relay-3), 카드마다 콘솔 바로 왼쪽(`relay2.png`).
- [x] 7. 그리기 도구: add_note, draw_diagram
  - 만든 것: `add_note(text, title?, color?)` 부른 콘솔 옆 스티커(노랑·파랑·초록·분홍·보라·회색). `draw_diagram(title, nodes, edges, groups?)` 는 기존 다이어그램 그리기(`DiagramMaker.draw`, 손그림 상자·화살표, 위→아래 배치)를 그대로 쓴다.
  - 확인(symv9-6): Iris 로 add_note 초록 "Relay finished…" → 스티커. draw_diagram 4상자 3화살표(라벨 hand_off) → 보드 오른쪽 빈 곳에 "Relay" 다이어그램(`relay2.png`).
- [x] 8. 안내 문구에 이어 달리기·그리기 방식(claude·codex 같은 글)
  - 고침: `BoardTools.systemPrompt` 에 넘겨주기(스스로 완결된 프롬프트: 목표·맥락·파일·한 것·남은 것·확인 방법 → hand_off, 넘긴 단계는 직접 하지 않음), 그리기(add_note·draw_diagram), 제한·거절 시 멈추고 알리기를 더했다. claude 는 `--append-system-prompt`, codex 는 `developer_instructions` 로 같은 글.

## 완료 기준 실제 입력 기록

`release` 번들, 상태 폴더를 따로 둔 인스턴스(`symv9-7`, Finder 와 같은 최소 PATH), 프로젝트 폴더는 이 레포. 준비만 DebugBridge(`openProject`, claude 콘솔 Ada).

1. 통과. Ada 에 "Relay test, no file changes. Hand off to a new claude console. Its task: hand off to a new shell console with the prompt `echo chain-ok`, then read that shell console and reply with what it printed. After your hand_off, wait about 40 seconds, read the claude console you opened, and tell me in one line what came back."(질문 5) → Ada 옆에 카드 "Relay test: shell chain → Pip" 과 claude Pip, Pip 이 받은 프롬프트로(질문 6) 다시 hand_off → 카드 "Relay test → Maya" 와 셸 Maya(`echo chain-ok` → `chain-ok`), Pip 답 `chain-ok`, Ada 답 "The relay worked: Pip … replied chain-ok."(`docs/screens/v9/claude-relay.png`). 선은 Ada → 카드 → Pip → 카드 → Maya.
2. 통과. codex 콘솔이 보드 도구로 셸을 띄우고 읽음(3번, `codex-board-tools.png`).
3. 통과. 제한을 넘으면 묻고, Cancel 이면 열지 않음(5번, `limit-ask.png`).
4. 통과. 폴더가 없는 콘솔은 띄우지 않고 알림(4번, `relay.png`).

`swift test` 216개 통과(8차 204), `scripts/bundle.sh`(release) 통과.

## 화면 시험 (완료 보고 뒤 사용자 요청: "직접 창 띄워서 테스트")

사용자 앱과 따로 상태 폴더를 둔 인스턴스를 위쪽 모니터에 띄우고, 실제 클릭·키(`cgclick`, 키는 앱 프로세스에 바로)와 실제 화면 캡처(`screencapture -R`)로 했다. 글자 입력만 DebugBridge `send`.

1. 통과. Ada 를 클릭 → 첫 줄 → 실제 Shift+Return → 둘째 줄: 입력 줄에 두 줄, 보내지지 않음(`ui-shift-enter.png`). 실제 Return 으로 보냄(질문 7).
2. 고침. 다이어그램 상자가 hand_off 카드·Pip 과 겹쳤다(`ui-overlap-before.png`). 원인: draw_diagram 이 상자를 시차를 두고 놓는데 바로 답해서, 곧이은 hand_off 가 아직 없는 상자 자리를 빈 칸으로 봤다. 다이어그램 자리도 화면 가운데였다. → 부른 콘솔 옆 빈 칸을 다이어그램 크기(`DiagramMaker.footprint`)로 찾아 그 안에 그리고, 마지막 화살표까지 놓은 뒤 답한다. 다시(질문 8): Ada 옆 다이어그램, 그 옆 카드 "Step 2 → Pip" 과 Pip(`echo step-2-ok` → `step-2-ok`), 위에 메모, 겹침 없음(`ui-diagram-handoff-note.png`).
3. 통과. 톱니 실제 클릭 → Settings → "Max consoles opened by agents" 팝업 클릭 → 1 → prefs `agents.maxOpened: 1`. Ada 에 "Hand off once more …"(질문 9) → 아래 띠 "Ada wants to open another console: agents already opened 1 console (limit 1)."(`ui-limit-ask.png`) → Cancel 실제 클릭 → 콘솔 안 생김, claude 가 다시 시도하지 않고 "The handoff didn't go through … I won't retry" 와 방법을 알림.
4. 고침. Settings 창이 낮아 마지막 설명 줄이 잘렸다 → 창 높이 446. "1 consoles" → "1 console". 다시 띄워 확인(`ui-settings.png`).
5. claude 는 레포 파일을 바꾸지 않았다(`git status` 에 내 수정만).


## 추가 요청 (완료 보고 뒤)

- [x] 9. ⌘Z·⇧⌘Z 보드 되돌리기 (사용자 요청)
  - 원래: Edit 메뉴의 Undo 는 글 입력칸에만 닿고 보드에는 되돌리기가 없었다.
  - 만든 것: `BoardHistory`(SymboardCore, 단위 테스트 4개). 작업공간이 바뀐 뒤 0.6초 조용하면 그 상태를 한 칸으로 남긴다(끌기·입력은 한 번에, 사람·에이전트·명령 어느 쪽 변경이든 같게, 100칸). 노드·그룹·펜 획·선을 되돌리고, 콘솔의 대화 id·띄운 적 있음은 비교에서 빼고 되돌릴 때도 지금 값을 지킨다. 사라지는 콘솔은 프로세스를 끄고 돌아오는 콘솔은 다시 띄운다(claude 는 대화 id 로 이어 감).
  - ⌘Z 는 `BoardWindow.undo`: 초점이 있는 글 칸에 되돌릴 입력이 있으면 그 글부터, 없으면 보드. 처음 판은 "글 칸에 초점이면 글" 이었는데 명령 바 입력칸이 거의 늘 초점이라 ⌘Z 가 아무 일도 안 했다.
  - 확인(symv9-undo6, DebugBridge `move`·`remove`·`undo` — 사용자가 같은 모니터에서 시스템 설정 암호를 입력 중이라 실제 키는 보내지 않았다): 스티커 +300 이동 → undo 제자리 → redo 다시 400. 셸 콘솔 Ada 삭제 → undo → Ada 가 같은 자리에 돌아오고 셸이 다시 뜸. 처음부터 undo 하면 스티커 추가도 되돌림.
- [x] 10. 다이어그램 제목이 둘째 줄에서 잘림 (사용자 보고)
  - 원인: 제목 칸 폭을 글자 수 × 22pt 로 어림해 한글(40pt 손글씨 한 글자 ≈ 40pt)이 줄을 넘기고, 높이 70pt 에 둘째 줄이 잘렸다.
  - 고침: 실제 글꼴로 잰 크기(`DiagramMaker.titleSize`), 한 줄로 1100pt 까지, 넘으면 줄을 바꾸고 높이를 늘려 위로 올린다. 보드 도구의 자리 찾기(`footprint`)도 같은 크기.
  - 확인: "사이즈표 이미지 → 상세페이지 HTML (3분할)" 한 줄로 다 보임(`diagram-korean-title.png`).
- [x] 11. 위쪽 폴더 메뉴 폭이 이름 길이에 따라 바뀜 (사용자 보고)
  - 고침: 폴더 메뉴를 200pt 고정 폭, 긴 이름은 말줄임, 전체 경로는 툴팁. 이름을 바꿔도 옆 작업공간 탭·Close 가 밀리지 않는다.
  - 확인: 폴더 `a` 와 `현브로맘X오즈키즈 사이즈표 상세페이지 작업 폴더` 에서 메뉴 오른쪽 끝이 같은 자리(`folder-menu-short.png`·`folder-menu-long.png`).
