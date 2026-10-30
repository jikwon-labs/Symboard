STATUS: IN PROGRESS

# Symboard 9차 진행표

기준 커밋 `79b1f15` (8차 완료본). 8차 테스트 수 204.
목표: AI 가 보드를 혼자 다뤄 세션을 이어 띄우고(세션1 → 세션2 → 세션3), 넘긴 프롬프트와 그림을 보드에 남긴다. 혼자 끝없이 띄우지 못하게 멈춤 장치를 둔다.
시험은 앱 상태 폴더를 따로 둔 인스턴스(`SYMBOARD_HOME=<scratchpad>/symv9-N`)에서 한다. 사용자가 띄워 둔 앱은 건드리지 않는다.

## 버전 확인

| 때 | claude | codex |
|----|--------|-------|
| 시작 | 2.1.314 | 0.166.0 (9차 시작 전 시험 중 업데이트 질문에 시험 입력이 들어가 0.163.0 에서 올라감) |

## 실제 claude·codex 질문 수 (한도 12)

| # | 때 | 무엇 |
|---|----|------|
| 1 | 10-31 01:41 | Shift+Enter 시험 뒤 그냥 Enter 확인. "Reply with only the word OK." |
| 2 | 10-31 01:58 | codex `-c developer_instructions` 확인(`codex exec`). "Where are you running? Answer in one word." |
| 3 | 10-31 02:05 | codex 보드 도구 시험. 시험 폴더 경로가 길어 소켓 경로 초과로 실패(아래 3번) |
| 4 | 10-31 02:08 | codex 보드 도구 시험 다시. 같은 질문 |

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
- [ ] 4. 작업공간 폴더가 없으면 홈 폴더로 몰래 넘어가지 않고 알린다
- [ ] 5. 멈춤 장치: 이어 띄우기 최대 단계, 에이전트가 연 콘솔 최대 개수, 설정 창에서 바꿈
- [ ] 6. 넘겨주기 도구 hand_off: 프롬프트 카드 + 새 세션 + 선
- [ ] 7. 그리기 도구: add_note, draw_diagram
- [ ] 8. 안내 문구에 이어 달리기·그리기 방식(claude·codex 같은 글)
