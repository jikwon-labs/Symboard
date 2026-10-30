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
- [ ] 3. codex 도 Symboard 안에 있음을 알고 보드 도구를 쓴다 (사용자 요청)
- [ ] 4. 작업공간 폴더가 없으면 홈 폴더로 몰래 넘어가지 않고 알린다
- [ ] 5. 멈춤 장치: 이어 띄우기 최대 단계, 에이전트가 연 콘솔 최대 개수, 설정 창에서 바꿈
- [ ] 6. 넘겨주기 도구 hand_off: 프롬프트 카드 + 새 세션 + 선
- [ ] 7. 그리기 도구: add_note, draw_diagram
- [ ] 8. 안내 문구에 이어 달리기·그리기 방식(claude·codex 같은 글)
