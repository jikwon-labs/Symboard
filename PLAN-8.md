STATUS: IN_PROGRESS

# Symboard 8차 진행표

기준 커밋 `51dfe3b` (7차 완료본). 7차 테스트 수 177.
모든 시험은 Finder 와 같은 환경으로 띄운 앱에서 한다:
`env -i HOME=$HOME USER=$USER LOGNAME=$USER SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin SYMBOARD_HOME=/tmp/symv8-N build/Symboard.app/Contents/MacOS/Symboard &`

## 버전 확인

| 때 | claude | codex |
|----|--------|-------|
| 시작 | 2.1.303 (프롬프트의 2.1.302 와 다름. 시작 시점에 이미 2.1.303) | 0.163.0 |
| 끝 | | |

## 실제 claude 질문 수 (한도 12)

| # | 때 | 무엇 |
|---|----|------|
| 1 | 10-20 01:38 | 1번 스크롤 시험. "print the numbers 1 to 150, one per line, nothing else" |

합계: 1

## 할 일

- [x] 1. 콘솔 안 스크롤(휠·트랙패드는 콘솔 scrollback, 마우스 보고 모드면 프로그램에, 위로 올린 동안 튀지 않음, 맨 아래로)
  - 재현: 셸 콘솔은 휠이 원래도 움직였다(orca scroll 3번에 479 → 407). claude 콘솔은 DebugBridge 로 모드를 찍어 보니 claude 2.1.303 은 `alt=true mouse=anyEvent`(대체 화면 + 모든 마우스 보고). SwiftTerm 휠은 모드를 보지 않고 지난 줄만 움직였는데 대체 화면엔 지난 줄이 없어 아무 일도 없었다. 또 `Terminal.userScrolling` 을 켜는 곳이 없어 올려 둔 셸 화면도 출력이 오면 맨 아래로 튀었다.
  - 원인/고침(`Vendor/SwiftTerm/PATCHES.md` 4): 마우스 보고 모드면 휠을 버튼 4·5 로 프로그램에 넘김, 대체 화면이고 보고가 없으면 위·아래 화살표, 트랙패드 정밀 양을 줄 단위로 모음. 맨 아래가 아니면 userScrolling 을 켜 튀지 않게, 입력하면 맨 아래로. 앱 쪽: 올려 둔 동안 콘솔 오른쪽 아래에 "↓ Bottom" 단추(`TerminalNodeContent`). 스크롤 막대 끌기는 SwiftTerm 원래 기능.
  - 확인한 실제 입력(인스턴스 symv8-2): 셸 Ada 에 `seq 1 500` + 1초마다 tick 15번 찍는 백그라운드 → 콘솔 위 orca 휠 30번 → 1 까지 올라감, 4초 뒤에도 1~24 그대로(tick 이 오는 중), 캔버스 그대로(`1-shell-scrolled-to-1.png`). 콘솔 밖 휠 3번 → 캔버스가 움직임(`1-outside-moves-canvas.png`). "↓ Bottom" 실제 클릭 → 맨 아래 tick15 와 프롬프트(`1-bottom-button.png`). claude Pip 에 1~150 출력 질문(질문 1) → 콘솔 위 휠 25번 → claude 가 자기 화면을 1 까지 올리고 자기 "Jump to bottom" 표시, 캔버스 그대로(`1-claude-scrolled.png`). claude 쪽 튀지 않음·맨 아래로는 claude 자기 동작이다.
- [x] 2. 새 콘솔을 기존 노드 옆 빈 칸에 놓고 화면을 부드럽게 옮기기
  - 재현/원인: `addTerminal(at: nil)` 은 `suggestedFrame(near: visibleCenter)` 로 화면 가운데에, Spawn·spawn 명령의 `launchTeam` 은 화면 가운데가 비면 거기(`freeSpotCenter`)에 놓고 `zoomToFit` 으로 배율까지 바꿨다.
  - 고침: `CanvasLayout.besideSlot`(단위 테스트 5개) — 기준 노드(고른 노드 → 마지막 노드, 그룹에 들었으면 그룹 프레임) 같은 줄 오른쪽 첫 빈 칸, 줄 폭 2100 을 넘으면 그 줄 아래 왼쪽부터. 묶음은 그룹 여백·머리까지 넣은 크기로 자리를 찾는다. 놓은 뒤 `glideReveal` 로 0.35초 미끄러지듯 옮기고 배율은 그대로(화면보다 크면 맞춤). 별 메뉴 놓기·컴포저(stagger)는 그대로.
  - 확인한 실제 입력(symv8-3): Ada(0,0)·Pip(700,0)·스티커(0,480) 보드, 화면을 (-3000,-2000) 빈 곳으로 옮김(`2-before-empty-view.png`) → `New console` 실제 클릭 → Maya 가 Pip 오른쪽(1380,0)에 생기고 화면이 그쪽으로, 배율 60% 그대로(`2-after-new-console.png`). 다시 빈 곳으로 옮긴 뒤 명령 바에 `spawn 2 shell` 타이핑 + Enter → 줄이 차서 아래 줄, 스티커 오른쪽에 Group 1, 화면 이동(`2-after-spawn2.png`).
- [ ] 3. claude 가 보드에 콘솔을 띄우는 MCP 도구(list/spawn/send/read/close), 설정 스위치, 부른 콘솔과 옅은 선
- [ ] 4. 명령 바 여러 줄(Shift+Enter, 3줄까지 자람, Cmd+Shift+E 전체 화면 편집, claude·codex 에는 bracketed paste)
- [x] 5. @ 대상마다 다른 글 보내기(단위 테스트)
  - 원인: `CommandTargets.parse` 는 맨 앞에 이어 붙은 @ 만 대상으로 보고 나머지 전부를 한 글로 모든 대상에 보냈다.
  - 고침: `CommandTargets.split`(+ `Mention.targets`·`activeInBody`, 단위 테스트 8개) — 알려진 @이름으로 시작하면 각 @이름 뒤부터 다음 알려진 @이름 앞까지가 그 대상 글, 이어 붙은 이름은 같은 글, 맨 끝 글 없는 이름은 보내지 않고 THREAD 에 알림, 모르는 @ 는 글. 줄바꿈 든 글도 다음 @이름 앞까지 한 덩어리. 명령 바와 오케스트레이터 입력칸 모두 같은 함수(`deliver`), 보내기 직전 THREAD 에 대상별 한 줄. 입력칸은 글 중간 알려진 @이름도 색칠하고 @ 목록을 띄운다.
  - 확인한 실제 입력(symv8-5, 셸 Ada·Pip·Maya, orca type + Return): `@Ada echo one @Pip echo two` → Ada 에 one, Pip 에 two 만, Maya 그대로, THREAD "→ Ada: echo one" "→ Pip: echo two"(`5-sent.png`), 입력칸에서 @Ada·@Pip 둘 다 주황(`5-typed.png`). `@Ada @Maya echo adjacent` → 둘 다 adjacent. `@Ada echo last @Pip` → Ada 만 last, THREAD "Nothing to send to Pip · not sent"(`5-adjacent-missing.png`).
- [ ] 6. 왼쪽 아래 ? 단추와 단축키 표, `?` 키
- [x] 7. 콘솔 안 Cmd·Option 이동과 지우기(단위 테스트)
  - 재현/원인: SwiftTerm 은 Option 을 Meta 로 써서(optionAsMetaKey 기본 켬) Option+←/→ 는 원래 ESC b/f 를 보냈지만, Cmd+←/→·Cmd+Backspace 는 처리하지 않았다. 한글 조합 중이면 조합 글자가 남은 채로 커서만 움직일 수 있었다.
  - 고침: `KeyInput.editBytes`(SymboardCore, 단위 테스트 4개) — Option+←/→ ESC b/f, Cmd+←/→ Ctrl+A/E, Option+Backspace ESC DEL, Cmd+Backspace Ctrl+U. 창 키 감시에서 콘솔이 초점일 때 키 코드로 보고(입력 소스 무관), 보내기 전에 조합 중 글자를 먼저 확정한다(`commitMarkedText`). Shift·Ctrl 이 같이 눌리면 건드리지 않고, Cmd+C·V·A 등 다른 키도 그대로.
  - ESC DEL 이 zsh·claude 둘 다에서 앞 단어를 지워 Ctrl+W 대신 쓰지 않았다.
  - 확인한 실제 입력(symv8-4, `cgclick key CODE mods` — 수정 키를 실제로 눌렀다 떼게 고친 도구): zsh ABC `echo alpha beta gamma` → Option+← x → `xgamma`, Cmd+← y → `yecho…`, Cmd+→ z → `…gammaz`, Option+Backspace → 앞 단어 지워짐, Cmd+Backspace → 줄 비움. zsh 한글: `안녕 하세`+조합 중 `요` 에서 Cmd+← → 요 확정 뒤 줄 처음(ㄱ 이 맨 앞에), Cmd+→ → 끝, Option+← → 단어 앞, 조합 중 `한` 에서 Option+Backspace → 한 이 확정된 뒤 지워짐(겹쳐 들어가지 않음), Cmd+Backspace → 빈 줄. claude 입력 줄 ABC·한글 같은 순서 모두 동작(claude 는 한글을 단어 글자로 보지 않아 Option+Backspace 가 `하세요 한` 을 한 번에 지웠다 — claude 쪽 단어 규칙). Cmd+V 는 그대로 붙여넣기.
- [x] 8. 콘솔 안 한글 글자 사이 틈
  - 원인(측정): SF Mono 12pt 한 칸 7.42pt, 두 칸 14.84pt. Apple SD Gothic Neo·Pretendard 12pt `니` 의 글리프 폭 10.4pt. SwiftTerm 이 글리프를 칸 왼쪽에 붙여 그려 글자마다 오른쪽에 4.4pt(두 칸의 30%) 틈. 14pt 도 같은 비율(17.3 / 12.1). 추측이 맞았다.
  - 고침(`Vendor/SwiftTerm/PATCHES.md` 6): 두 칸 글자는 두 칸의 84% 까지 키우되 영문 ascent 를 넘지 않게(12pt 기준 약 1.2배) 하고 두 칸 가운데에 놓는다. 칸 위치는 안 바꿔 커서·선택·줄바꿈 영향 없음.
  - 확인한 실제 화면: 같은 글(`/tmp/symko.txt`, "줍니다. 기획서에는 …")을 셸 콘솔에 `cat` 해서 고치기 전·후를 같은 조건으로 찍었다. 기본(Apple SD Gothic Neo)·Pretendard × 12·14 (`8-before-*`, `8-after-*`, 위아래로 붙인 `8-compare-*`). 고친 뒤 한글 입력(`cgclick keys`) 후 커서가 `하세요 ` 바로 뒤(`8-after-cursor-Pretendard-14.png`).
- [x] 9. 콘솔 안 조합 중 한글 보이기
  - 원인: SwiftTerm `setMarkedText` 등이 비어 있었다(`PATCHES.md` 5).
  - 고침: 조합 중 글자를 커서 자리에 밑줄과 함께 겹쳐 그림, 커서를 따라감, 커서 뷰 위로.
  - 처음 고친 판에서 `gktpdy`(하세요) 를 치면 `요` 가 `세` 자리에 겹쳤다 — `세` 확정과 `요` 조합 시작이 한 키에 일어나 셸 메아리 전의 커서 자리에 놓였기 때문. 커서 이동 때 다시 놓게 고쳤다. claude 에서는 claude 가 다시 붙인 커서 뷰가 조합 글자를 덮어 그 위로 올리게 고쳤다.
  - 확인한 실제 입력(한글 2벌식, `cgclick keys dkssud gktpdy`): zsh `안녕 하세` 뒤 밑줄 친 `요`(`9-shell-composing.png`), claude 입력 줄 같은 모습(`9-claude-composing.png`, `-crop`). 조합 중 Enter → `안녕` 한 번만 실행(command not found: 안녕).
- [x] 10. Ctrl+Tab·Cmd+1~9 로 콘솔 사이 옮기기, 번호 배지, Zoom to Fit 은 Cmd+Shift+1
  - 만든 것: `ConsoleOrder`(SymboardCore, 단위 테스트 3개: 위→아래·왼→오른쪽 순서, 끝에서 처음으로 돌기, 숫자 키 코드). 창 키 감시 + 창 `sendEvent`(BoardWindow)에서 키 코드로 Ctrl+Tab / Ctrl+Shift+Tab / Cmd+1~9 / Cmd+Shift+1 을 처리. 옮겨 가면 그 콘솔을 고르고 터미널을 첫 응답자로(바로 타이핑), 화면을 0.35초 동안 그 콘솔로. View 메뉴: Zoom to Fit ⇧⌘1, Next/Previous Console, Go to Console 1~9. Cmd 를 누르고 있는 동안 콘솔 머리 이름 옆에 번호 배지. 그냥 Tab 은 가로채지 않는다.
  - 확인한 실제 입력(symv8-10, 셸 5개 Pip(0,0)·Maya(700,20)·Ada(1400,0)·Iris(0,480)·Dax(700,480), ABC 입력): Pip 에서 Ctrl+Tab 다섯 번 → Maya, Ada, Iris, Dax, Pip(한 바퀴, 매번 [keyboard] = 키 입력 받는 상태). Cmd+3 → Ada 로, 바로 `echo hi` + Enter → Ada 에 `hi`, 명령 바 "Message Ada"(`10-cmd3-echo-hi.png`). Cmd 누르고 있는 동안 번호 배지(`10-cmd-badges.png`), 떼면 사라짐. Ada 에서 `ech` + Tab → 셸이 `echo` 로 완성(가로채지 않음). Cmd+Shift+1 → 150% 에서 맞춤 60%, Cmd+0 → 100%. 한글 입력 상태 Ctrl+Shift+Tab → Iris 로(키 코드 기준).
  - 주의: 이 맥에서는 HID 로 보낸 Cmd+3·Ctrl+Tab 이 앱에 오지 않는다(DECISIONS 8차-10). 위 Ctrl+Tab 다섯 번과 Cmd+3 은 같은 키 이벤트를 앱 프로세스에 바로 보내서 확인했다. Cmd+1·2·4·5 와 Ctrl+Shift+Tab 은 HID 실제 키로 동작했다.

## 막힌 것

## 완료 기준 실제 입력 기록
