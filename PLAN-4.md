STATUS: DONE

# Symboard 4차 진행표

기준 커밋 `4a73437` (3차 완료본). 3차 테스트 수 92.
확인은 `orca computer` 실제 클릭·키 입력(`scripts/input/ui.sh`)으로 한다. `scripts/drive.sh` 는 상태를 깔아 두는 데만 쓴다.
스크린샷은 `docs/screens/v4/<항목번호>-<이름>.png`. 체크한 항목 아래에 "재현 / 원인 / 확인한 실제 입력" 을 적는다.

## 실제 CLI 질문 수 (한도 12)

| # | 항목 | 대상 | 질문 |
|---|------|------|------|
| 1 | 2번 권한 | Ada(/tmp/symperm, Ask 모드) | make a file named a.txt with the word hi |
| 2 | 3번 Done | Ada | count from 1 to 80, one number per line, no tools |
| 3 | 4번 작업 중 | Ada | write a 200-word paragraph about ocean tides, no tools (5초 안에 끝나 미션 맵을 못 봄) |
| 4 | 4번 작업 중 | Ada | write about 600 words on the history of mechanical clocks, no tools |
| 5 | R 문서 생성 | 문서 스튜디오(/tmp/symsample) | a 5-line README for this repo (실시간 안 그려짐 재현) |
| 6 | R 문서 생성 | 문서 스튜디오(/tmp/symsample) | a 5-line README for this repo (고친 뒤 확인) |
| 7 | S 다이어그램 | 다이어그램 칸(/tmp/symsample) | how hello.py uses util.py |
| 8·9 | 하루 쓰기 1차 | @testers → Ada·Pip(/tmp/symday) | run the tests and tell me which one fails, do not fix |
| 10·11 | 하루 쓰기 2차(통과) | @testers → Ada·Pip(/tmp/symday) | run the tests and tell me which one fails, do not fix |

합계: 11 (한도 12 안). 메모리 Rewrite·git 메시지 생성 같은 다른 질문은 보내지 않았다. 사용량 탐침(`/usage`)은 질문이 아니다.

## 고칠 것

- [x] 1. 사용자 답을 기다리는 claude(신뢰 확인 화면)가 READY 로 보임 → 화면 끝 글자로 Needs you. codex 승인 화면도.
  - 재현: 새 `/tmp/symtrust-3` 에서 별 → Claude Code → 캔버스 클릭. "Quick safety check ... Enter to confirm · Esc to cancel" 화면에서 알약 READY, 미션 맵 Idle. codex 를 띄우면 신뢰 확인 전에 "Background server has incompatible feature settings"(번호 메뉴, 안내 줄 없음)와 "Update available"(enter continue · esc skip) 화면이 먼저 나온다.
  - 원인: 상태는 훅 신호나 출력 시각으로만 판정했다. 이 화면들은 훅이 돌기 전이라 신호가 없고, 출력이 멈추면 Idle 로 봤다. 또 화면 글자를 읽어 보니 한 번도 쓰지 않은 칸이 NUL 로 나와 낱말 사이가 공백이 아니었다.
  - 고침: `PromptDetector`(Core) 가 화면 끝 18줄에서 "고르는 표시(❯ ›) + 안내 줄(Enter to confirm, esc quit 등)" 또는 "고르는 표시가 번호 선택지 위" 를 찾으면 `.waiting`. 1초 판정(`StatusTracker.resolve`)이 훅·출력 판정 위에 이것을 얹는다. 화면 글자의 NUL 은 공백으로. 기다리는 노드는 노란 2pt 테두리. 그룹 머리 요약은 "2 need you" 처럼 개수를 함께. 단위 테스트(실제 화면 표본: claude 신뢰, codex 신뢰·업데이트·데몬 메뉴, 평소 입력창, 번호 목록 답) 9개.
  - codex 승인 화면: 이 머신 codex 는 YOLO 모드(자동 승인)라 명령 승인 화면이 뜨지 않는다. 같은 꼴(번호 선택지 위 › 표시)이라 데몬 메뉴 규칙으로 잡힌다(표본 테스트).
  - 확인한 실제 입력: 새 상태 `/tmp/symv4c` → Open folder → Cmd+Shift+G `/tmp/symtrust-5` → Group → − 두 번 → 둘째 타일 눌러 Codex → Spawn 2. 두 노드 NEEDS YOU·노란 테두리, 그룹 머리 "2 · 2 need you"(`1-group-needs-you.png`). 미션 맵(도구 메뉴 → Mission Map) "Needs you 1", 행 "Needs input"(`1-mission-needs-you.png`, symtrust-4). codex 노드 클릭 → `1`, `2` → 신뢰 화면 동안 waiting → Return → 입력창 READY. claude 노드 클릭 → ↓ → Return → 입력창 READY, 그룹 "idle"(`1-after-answer-ready.png`). 질문 0회.
- [x] 2. 권한 확인을 기다리는 상태를 실제로 확인(노드·그룹 헤더·미션 맵 Needs you, 노드 강조, 승인 후 Working → Idle/Done)
  - 재현: 이 머신의 `~/.claude/settings.json` 이 `defaultMode: auto` 라 노드가 자동 모드로 떴다. 앱 안에서 노드별로 자동 승인을 끌 방법이 없었다(새 콘솔 대화상자의 인자 칸뿐).
  - 고침 1: 노드 머리 ⌄ 메뉴에 Permissions(Use CLI Setting / Ask Before Tools / Auto-Approve). claude 는 `--permission-mode manual|bypassPermissions`, codex 는 `-a on-request -s workspace-write` / `--dangerously-bypass-approvals-and-sandbox`. 바꾸면 같은 대화로 다시 띄우고, 머리에 ASK/AUTO 배지(`PermissionMode`, 단위 테스트 2개).
  - 고침 2(찾은 버그): 다시 띄우기가 옛 프로세스를 끄자마자 같은 터미널에서 새로 띄워, 늦게 온 옛 프로세스 종료 알림이 새 프로세스를 "끝남" 으로 만들고 입력이 막혔다(상태 exited, 친 글자가 안 들어감). 종료 알림을 받은 뒤(최대 2초) 새로 띄운다. Restart Process 도 같은 길을 탄다.
  - 고침 3: 미션 맵 행·상세의 기다림 글자 "Needs input" → "Needs you"(칩과 같은 말).
  - 확인한 실제 입력: Group → Claude+Shell → Spawn → 노드 클릭·↓·Return 으로 신뢰 → ⌄ → Permissions → Ask Before Tools → "manual mode on" 으로 다시 뜸, ASK 배지. 입력칸 클릭 → "make a file named a.txt with the word hi" 타이핑 → Return. 1초 캡처(`2-sequence-1s.png`): READY → RUNNING·"1 running" → NEEDS YOU·노란 테두리·"1 needs you". 화면에 "Do you want to create a.txt? ❯ 1. Yes … Esc to cancel"(`2-permission-node.png`). 미션 맵 Needs you 1(`2-permission-mission.png`) → Ada 클릭 → Go to the console → Return(1. Yes) → working 3초 → idle, `/tmp/symperm/a.txt` = hi. Go to 로 그 터미널에 초점이 있어서 Done 이 아니라 Idle 로 끝났다(3번 규칙대로).
- [x] 3. Idle 과 Done 의 구분(원본 뜻 찾기, DECISIONS, 보거나 새 질문하면 풀림)
  - 원본: `teams.jpg` 미션 맵은 Idle 27 · Done 0 인데, 같은 장면의 콘솔들은 "Worked for 5m 20s · done Sunday" 처럼 일을 끝낸 상태다. 사용자가 이미 본 끝난 콘솔은 Idle 이다. 그래서 Done = "받은 일을 끝냈는데 아직 안 봄" 으로 정했다(DECISIONS.md).
  - 고침: `NodeStatus.done`. 판정(`StatusTracker.resolve`): 훅이 working 을 보냈거나(claude), 입력 뒤 출력이 3초 넘게 이어지면(codex 등) "일을 했다" 로 치고, 그 뒤 idle 이 되면 done. 노드를 고르거나(클릭·Go to) 그 터미널에 키보드 초점이 있거나 새 입력을 보내면 풀린다. 일반 셸은 Done 을 쓰지 않는다. 부팅 출력·짧은 출력은 일로 치지 않는다. 알약 DONE(파란색), 그룹 머리 "1 done", 미션 맵 Done 칩. 단위 테스트 6개.
  - 확인한 실제 입력: 아래 명령 바 클릭 → "@Ada count from 1 to 80, one number per line, no tools" → Return. 2초 working → done, 30초 넘게 done 유지. 알약 DONE·그룹 "1 done"(`3-done-node.png`), 미션 맵 Done 1·행 "Done"(`3-done-mission.png`). Esc → Ada 머리 클릭 → idle(`3-done-cleared.png`). 새 질문을 보내면 바로 working(4번 캡처).
- [x] 4. 작업 중 표시(노드 알약, 그룹 요약 "1 running", 상단 live, 미션 맵 Working 개수) 1초 간격 캡처
  - 재현: 노드 알약·그룹 요약·미션 맵은 바뀌었지만, 상단 live 알약은 살아 있는 프로세스 수만 보여 일하는 중인지 알 수 없었다.
  - 고침: 일하는 콘솔이 있으면 live 점을 강조색으로 바꾸고 "· 1 working" 을 붙인다.
  - 확인한 실제 입력: 명령 바 → "@Ada write a 200-word paragraph about ocean tides, no tools" → Return(1초 캡처 `4-working-board-1s.png`: READY → RUNNING, "idle" → "1 running", "2 live" → "2 live · 1 working"). 이 답은 5초 안에 끝나 미션 맵을 못 열어서, "@Ada write about 600 words on the history of mechanical clocks, no tools" 로 한 번 더 → 2초 뒤 도구 메뉴 → Mission Map(`4-working-mission-1s.png`: 부제 "1 working", Working 1, 행 "Working", 팀 "1 working"). 끝나면 Done 으로.
- [x] 5. 글 쓰는 창이 열리자마자 첫 칸에 초점, Enter 저장 / Esc 취소(여러 줄은 Cmd+Enter)
  - 찾은 창: 칸반 새 카드·카드 고치기, 캘린더 새 일정, 노드·그룹·작업공간·열 이름 바꾸기와 역할(NSAlert `Prompt.text`), 넘겨주기 메모, 넘겨주기 보내기 전 고치기(여러 줄), 계정 프로필 추가(NSAlert), 계정 팝오버 새 이름, 루프 Start from scratch, 메모리 새 메모, git 커밋 메시지, 문서 요청, 다이어그램 설명, 웹 타일 빈 새 탭 주소. 체크리스트 Add an objective 는 이미 초점이 갔다.
  - 원인: SwiftUI 입력 칸에 초점 지정이 없었다. NSAlert 는 `initialFirstResponder` 만 두었는데 창이 뜬 뒤 첫 단추가 초점을 가져가는 때가 있다.
  - 고침: `.autoFocus()`(창이 붙은 뒤 0.05·0.25초에 초점) 를 위 SwiftUI 칸에 붙였다(이미 내용이 있는 고치기 창과 주소가 있는 웹 탭은 제외). 칸반·캘린더는 Enter 저장(제목이 비면 무시)·Esc 취소(`onExitCommand`). 루프·메모리는 Enter 저장, 여러 줄 칸에서는 Cmd+Enter 로 저장 단추. NSAlert 는 `Prompt.run` 이 창이 뜬 뒤 칸에 초점을 주고 글자를 모두 골라 둔다(바로 치면 바뀜). 여러 줄 Prompt 는 Cmd+Enter 가 OK.
  - 확인한 실제 입력(새 상태 /tmp/symv4e, /tmp/symfocus git 레포): 칸반 DOING "Add card" 클릭 → 바로 "Write docs" → Return → 카드 생김(`5-kanban-typed-enter.png`). Add card → "nope" → Esc → 카드 안 생김. … → Rename… → 바로 "Sprint board" → Return → 이름 바뀜(`5-rename-typed.png`). 루프 → Start from scratch → 바로 "Hourly ping"(`5-loop-scratch-typed.png`) → 지시 칸 클릭 "say hi" → Cmd+Return → 루프 생김. Memory → New memory → 바로 "Use pnpm not npm" → Return → 저장(`5-memory-typed.png`). 브랜치 칩 → 바로 "Add b line" → Return → `/tmp/symfocus` 에 커밋 a671b03(`5-git-typed.png`). 문서 스튜디오 → 바로 "a short README"(`5-docs-typed.png`, Enter 는 질문이 되어 R 항목에서). 다이어그램 → 바로 "login flow"(`5-diagram-typed.png`). 웹 타일 놓기 → 바로 "example.invalid" → Return → 그 주소로 이동(`5-web-typed.png`). 캘린더 + New → 바로 "Standup" → Return → 18일에 일정(`5-calendar-typed.png`, `5-calendar-enter.png`).
  - 시험 도구 한계: git 팝오버에서 커밋한 뒤 orca 가 "초점 창 없음" 으로 Esc·클릭을 거부했다(AppKit 키 창은 본 창이었다 — 디버그 `windows` 로 확인). CGEvent 도구는 이 터미널에 손쉬운 사용 권한이 없어(`CGPreflightPostEventAccess` false) 이벤트가 버려진다. 팝오버는 디버그 통로로 닫았다.
- [x] 6. 칸반 Done 열 카드 표시
  - 원본: `videos/node-kanban.mp4` 48초 장면(`6-original-done-column.png`)에서 "Research market trends" 카드를 DONE 열로 옮긴 뒤에도 앞 동그라미는 비어 있고, 우선순위 색 막대와 Today·Low 칩이 그대로다. 열은 자리일 뿐이고, 동그라미는 따로 누르는 완료 표시다.
  - 결정: 원본대로 열을 옮겨도 동그라미를 자동으로 채우지 않는다(DECISIONS.md). 동그라미를 누르면 완료(3차에서 확인한 동작).
  - 확인한 실제 입력: 칸반 머리 클릭 → "Write docs" 카드를 DOING 에서 DONE 열로 끌기 → DONE 1, 빈 동그라미·왼쪽 막대(`6-kanban-done-column.png`). 고친 코드는 없다.
- [x] 7. 앱이 스스로 만드는 노드(인스펙터, 복제, 컴포저 그룹, 문서·다이어그램 결과)도 보이는 영역 안으로
  - 재현: 웹 타일을 화면 오른쪽에 놓고 인스펙터를 열면 웹 타일 오른쪽 +80 에 생겨 오른쪽 막대 밑·화면 밖으로 나갔다(3차 보고). 복제(+40,+40), 자리 없이 만드는 문서·메모리·파일·이미지 카드도 같은 길이었다.
  - 원인: 3차의 자리 조정(`CanvasLayout.fit`)은 클릭으로 놓는 `place` 에만 있었다.
  - 고침: 인스펙터·복제·다이어그램처럼 다른 노드와 붙은 자리는 옮기면 안 되므로, 노드는 그대로 두고 화면을 옮긴다. `CanvasLayout.reveal`(단위 테스트 3개)이 만든 노드(인스펙터는 웹 타일과 함께)를 담는 사각형이 막대를 뺀 보이는 영역 밖이면 그 가운데로 옮기고, 안 들어가면 배율만 줄인다(키우지 않음). 복제, 인스펙터, 자리 없이 만드는 `addNode`/`addTerminal`, 이미지에 붙였다. 컴포저 그룹(`zoomToFitFrames`)과 다이어그램 결과(`zoomToFit`)는 이미 끝에 막대 여백을 둔 전체 맞춤을 한다.
  - 확인한 실제 입력: 새 상태 /tmp/symv4f → 왼쪽 막대 지구 → 캔버스 오른쪽(1300,450) 클릭 → 웹 타일이 오른쪽 막대 바로 옆 → 타일의 벌레 단추 → 인스펙터와 웹 타일이 모두 보이게 87% 로 옮겨짐, 연결선(`7-inspector-revealed.png`). 인스펙터가 고른 채로 왼쪽 막대 복제 단추 → 복제본이 화면 안에 보이게 옮겨짐(`7-duplicate-revealed.png`). 컴포저 그룹은 1·2번 시험에서 Spawn 뒤 막대에 가리지 않는 것을 봤다.
- [x] 8. 셸 Ctrl+C 실제 입력 확인(`sleep 100` 끊기)
  - 재현: 셸 노드 클릭 → `sleep 100` → Return → orca `hotkey Ctrl+C`(Control+C, ctrl+c, type-text 로 문자 3 도 시도) → 계속 RUNNING, 끊기지 않음.
  - 원인 찾기: 환경 변수 `SYMBOARD_KEYLOG` 로 창 키 이벤트를 기록해 보니 Ctrl+C 는 창까지 왔다(code 8, characters [3], control). 그런데 charactersIgnoringModifiers 가 12618("ㅊ") 였다. 이 머신 입력 소스가 한글이라서다. SwiftTerm 은 charactersIgnoringModifiers 의 영문 글자로 제어 문자를 만들고, 영문이 아니면 아무것도 보내지 않는다. 시험 도구 문제가 아니라 한글 입력 상태의 실제 사용자도 Ctrl+C·Ctrl+D·Ctrl+R 이 안 먹는 버그다.
  - 고침: 창 키 감시에서 터미널에 초점이 있고 Ctrl(Cmd·Option 없이)인데 charactersIgnoringModifiers 가 영문이 아니면 characters 의 제어 문자를 그대로 보낸다(`KeyInput.controlByte`, 단위 테스트 3개, 실제로 찍힌 값으로). 영문 자판은 SwiftTerm 그대로.
  - CGEvent 도구(`scripts/input/cgclick`)는 이 터미널에 이벤트 보내기 권한이 없어(`CGPreflightPostEventAccess` false) 쓰지 않았다. 대신 cgclick 이 팝오버가 아니라 본 창을 기준으로 잡게 고쳐 두었다.
  - 확인한 실제 입력: 셸 노드 클릭 → "sleep 100" → Return → 3초 뒤 RUNNING(working) → orca `hotkey Ctrl+C` → 화면 `^C`, 프롬프트에 `INT ✘ took 4s`, READY(`8-shell-ctrl-c.png`). 고친 뒤 두 번 확인.

## 다시 눌러 볼 화면

- [x] 1. G 계정 프로필: 추가, 바꾸기, 노드에 적용
  - 원본(`node-accounts.jpg`)과 같은 점: accounts 머리 + CLI 칩, Keychain 경고, Your sign-in ACTIVE, 프로필 행(머리글자·Use·열기·고치기·지우기), Save your current sign-in, CONNECT ANOTHER ACCOUNT 칸 + Connect.
  - 다른 점: 노드 머리에 어느 프로필로 떴는지 따로 보이지 않는다(마우스 설명에도 없음). 원본 장면에서도 노드 쪽 표시는 찾지 못해 그대로 둔다.
  - 고침(찾은 것): 새 프로필 콘솔의 claude 첫 실행 화면("Choose the text style …", 번호·안내 줄 없는 메뉴)이 READY 로 보였다. `PromptDetector` 에 "고르는 줄 바로 위 10줄 안에 Choose/Select 물음이 있고 그 사이에 ──── 입력창 경계가 없으면 기다림" 규칙을 더했다(표본 테스트 2개: 테마 메뉴는 기다림, 답에 choose 가 있고 아래가 입력창이면 아님).
  - 확인한 실제 입력(새 상태 /tmp/symv4h): 위 계정 단추 → 열리자마자 이름 칸에 "Work" → Return → `/tmp/symv4h/profiles/claude-work-…` 폴더로 claude 콘솔이 뜸(`G-accounts-typed.png`) → 다시 계정 단추 → Work 행 Use → activeProfiles 에 Work(`G-accounts-use.png`) → 팝오버 밖 클릭 → New console → 새 노드 Pip 의 profileID 가 Work, 새 설정 폴더라 첫 실행 화면(`G-profile-applied.png`). 다시 실행해 두 노드 이어하기 → 첫 실행 메뉴에서 둘 다 waiting(`G-onboarding-needs-you.png`).
- [x] 2. N 사용량: 팝오버 숫자, 고리, 초기화 시각
  - 원본(`node-usage.jpg`): 고리 "14% used", Current session "Resets 4:09am (지역)", Current week (all models) 9% 막대 + 초기화 시각, Current week (Fable) 17%, 활동 격자, 통계, 바닥 "claude · /usage". 토큰 화면은 막대 그래프와 By agent.
  - 다른 점(쓰는 데 지장): 우리는 로컬 로그만 읽어 고리가 "? limit", 초기화 시각은 "(estimated)" 였다. 원본 바닥 글자처럼 CLI 의 `/usage` 화면이 출처다.
  - 고침: `PlanUsageProbe` 가 화면 없는 터미널(SwiftTerm HeadlessTerminal)에 지금 프로젝트 폴더에서 claude 를 띄워 `/usage` 를 치고 화면을 읽은 뒤 닫는다. 모델에 질문하지 않는다. 폴더 신뢰·첫 실행처럼 선택 화면이 나오면 대신 고르지 않고 그만둔다(사용자 설정을 바꾸지 않으려고). `PlanUsageParser`(표본 테스트 2개)가 "Current session 29% used / Resets 5pm (Asia/Seoul)" 와 주간 줄들을 읽는다. 팝오버: 고리에 세션 %, "Resets 5pm (Asia/Seoul)", 주간 한도마다 이름·%·막대·초기화 시각, 바닥 "claude · /usage · local session logs". 팝오버를 열 때(2분 지난 값이면)와 새로 고침 단추에서 읽는다. 다 읽은 뒤 탐침 claude 가 남지 않는 것을 ps 로 확인.
  - 남은 차이: codex 는 `/status` 를 읽지 않아 로그 통계만 보인다. 위쪽 알약은 3차에서 맞춘 "resets 5:00pm"(로그 기준 추정) 그대로다.
  - 확인한 실제 입력(새 상태 /tmp/symv4i, 프로젝트 /tmp/symperm): 위 사용량 알약 클릭 → 처음엔 "reading claude /usage…" → 약 10초 뒤 고리 30% used, "Resets 5pm (Asia/Seoul)", Current week (all models) 18% · Resets Oct 22 at 8am(`N-usage.png`). 질문 0회.
- [x] 3. H 체크리스트·캘린더: 항목 추가·체크, 일정 추가
  - 원본(`node-kanban.jpg` 아래 줄): 체크리스트 "No objectives / Add one to begin" + 흐린 자리줄 + "Add an objective", 캘린더 달 격자·+ New·Today·위아래, 일정 창(제목·날짜·All day·색·메모·Cancel/Add event). 우리 쪽 모양이 같다. 차이는 찾지 못했다.
  - 확인한 실제 입력(새 상태 /tmp/symv4j): 오른쪽 막대 체크리스트 아이콘 → Checklist → 캔버스 클릭 → "Add an objective" 클릭 → "Write tests" Return → "Ship it" Return(입력칸이 계속 열려 이어 쓸 수 있음) → "0 of 2 done" → 첫 항목 동그라미 클릭 → "1 of 2 done", 줄 긋기, 고리 채움(`H-checklist.png`). 캘린더 + New → "Standup" → Return → 18일에 일정(5번, `5-calendar-enter.png`).
- [x] 4. I 이미지: 끌어 놓기 또는 붙여 넣기, 크기 조절
  - 차이(쓰는 데 지장): 보드에 그림 붙여 넣기(Cmd+V)가 없었다. 끌어 놓기와 왼쪽 막대 이미지 단추(파일 고르기)만 있었다.
  - 고침: 보드에 초점이 있을 때 Cmd+V 가 클립보드의 그림 파일이면 그 파일로, 그림 자체(스크린샷 복사 등)면 상태 폴더 `images/` 에 PNG 로 저장해 이미지 노드를 놓는다(`pasteImage`). 그림이 없으면 "No image on the clipboard" 안내.
  - 끌어 놓기는 Finder 같은 다른 앱을 눌러야 해서 시험하지 않았다(규칙: 다른 앱 클릭 금지). 코드는 3차 그대로.
  - 확인한 실제 입력(새 상태 /tmp/symv4k): 시험용 그림(/tmp/symimg/test.png)을 클립보드에 그림으로 올림 → 보드 빈 곳 클릭 → Cmd+V → 480×320 이미지 노드와 속성 막대, `/tmp/symv4k/images/pasted-….png`(`I-image-pasted.png`) → 오른쪽 아래 손잡이를 끌어 330×220(비율 유지)(`I-image-resized.png`).
- [x] 5. C 오케스트레이터: 끌어서 팀과 연결, 연결 끊기, 연결된 팀에만 명령
  - 원본(GAPS C, board.jpg): Connect → 그룹 칩 켜기 → Done → 곡선 연결선, 그룹별 섹션(● TEAM n/m)·행 상태 알약, 아래 "Command N agents · @ to direct". 우리 쪽 Connect 흐름은 3차에서 확인했다.
  - 차이(쓰는 데 지장): 끌어서 연결하는 방법이 없었다(Connect 단추 흐름만).
  - 고침: 오케스트레이터 오른쪽 가장자리에 주황 연결 손잡이(`WirePortView`). 누르고 끌면 점선 곡선이 따라오고, 그룹 틀(머리·여백) 위에 놓으면 그 그룹, 콘솔 위에 놓으면 그 콘솔의 연결을 켜거나 끈다. 결과를 "Wired Beta"/"Unwired Beta" 로 알린다.
  - 확인한 실제 입력(새 상태 /tmp/symv4l, 셸 그룹 Alpha·Beta 두 개는 디버그로 깔고): 오른쪽 막대 → Orchestrator → 캔버스 클릭 → 손잡이를 Beta 틀 아래 여백으로 끌기 → "Wired Beta", 연결선, BETA 섹션 Maya·Iris(`C-drag-wired.png`) → 오케스트레이터 입력 "echo only-beta" Return → Maya·Iris 에만 출력, Ada·Pip 은 없음(`C-command-beta-only.png`) → 같은 자리로 다시 끌기 → "Unwired Beta", links 비고 "No agents wired"(`C-drag-unwired.png`).
- [x] 6. O·P 코드 스튜디오: 파일 열기, 고치기, 저장, 탭 여러 개
  - 원본(`studio-code.jpg`, `agent3/code-16.png`): 왼쪽 파일 나무, 경로 조각·언어 배지·줄 수·크기·"• Edited", Add folder · Save · Insert, 줄 번호 편집기. 우리 쪽이 같다. 원본에는 열린 파일 탭 줄이 없다.
  - 차이(쓰는 데 지장): 파일을 바꿔 열면 앞 파일로 돌아갈 길이 나무뿐이었다(진행표가 요구한 "탭 여러 개" 없음).
  - 고침: 연 파일을 `openFiles` 로 남기고, 둘 이상이면 위쪽에 탭 줄(이름, 고친 탭은 노란 점, ×)을 보인다. 하나일 때는 원본처럼 숨긴다. × 를 누르면 고친 내용을 저장하고 남은 탭으로 옮긴다. × 누를 자리를 16pt 로 키웠다(8pt 글자만 눌리던 것을 실제 클릭으로 찾음). 탭은 코드 스튜디오 안에서만 쓴다.
  - 확인한 실제 입력(새 상태 /tmp/symv4m, 예제 /tmp/symcode): 오른쪽 막대 코드 아이콘 → src 펼치기 → calc.py → main.py(경로 src › main.py, PY, 줄 수) → 2행 끝 클릭 → End, Return, "print('saved')" → Cmd+S → 디스크 반영(`O-code-saved.png`). 탭 줄 calc.py·main.py → calc.py 탭 → 끝에 "# edited in tab" → "• Edited"·탭 노란 점(`O-tabs-edited.png`) → Cmd+S → "Saved", 디스크 반영 → main.py 탭 × → calc.py 만 남고 탭 줄 숨김(`O-tab-closed.png`).
- [x] 7. Q 마크다운 스튜디오: Reading/Source/Graph 전환, 링크 따라가기
  - 원본(`studio-markdown.jpg`, `agent3/md-graph.png`): 읽기 화면, Reading/Source/Graph, 링크 그래프, Add to Board·Export PDF. 모양은 같다.
  - 차이(쓰는 데 지장): 읽기 화면에서 `[notes](notes.md)` 링크를 눌러도 아무 일이 없었다(웹뷰가 이동만 시도).
  - 고침: 읽기 웹뷰가 링크 누르기를 가로챈다(`HTMLPreview.onLink`). 같은 컴퓨터의 마크다운 파일이면(.md 를 빼먹은 링크도) 스튜디오에서 읽기로 열고, http(s) 는 보드에 웹 타일로 연다(다른 앱을 띄우지 않음). 문서 안 #앵커는 그대로.
  - 확인한 실제 입력: 오른쪽 막대 마크다운 아이콘 → README 가 읽기로 열림 → 본문 "notes" 링크 클릭 → notes.md 로 이동, 나무 선택도 notes(`Q-link-followed.png`) → Source(`Q-source.png`) → Graph: README—notes 선, 2 notes(`Q-graph.png`) → 그래프 마디 클릭 → 그 노트가 읽기로 열림. 그래프는 힘 배치라 마디가 움직여, README 를 겨눈 클릭이 notes 마디에 맞았다.
- [x] 8. R 문서 생성: 실제 질문 1회, 실시간으로 그려지는지
  - 원본(`studio-documents.jpg`, `agent3/doc-gen.png`): 생성되는 동안 흰 종이에 글이 줄줄이 그려진다.
  - 재현(질문 5): 문서 스튜디오 → 요청 칸 "a 5-line README for this repo" → Return. 1초 캡처에서 "Writing with Claude Code · 8s…21s" 동안 종이에 자리표시 막대만 있다가, 끝난 뒤 한 번에 전체 글이 나왔다(`R-before-skeleton-only.png`).
  - 원인: 종이 웹뷰가 "0.25초 뒤에 그리기" 예약을 조각이 올 때마다 취소하고 다시 걸었다(디바운스). 조각이 0.25초보다 자주 오니 끝날 때까지 한 번도 그려지지 않았다.
  - 고침: 예약이 걸려 있으면 그릴 내용만 바꾸고 예약은 그대로 둔다(0.25초마다 마지막 내용을 그림).
  - 확인(질문 6): 같은 입력 → 0.7초 간격 캡처에서 21s·22s·23s·24s·25s 마다 표·제목·코드 블록이 차례로 늘고 아래로 따라 내려감(`R-live-streaming.png`). 끝나면 문서 목록에 저장(`/tmp/symv4n/docs/…/custom-….md`).
- [x] 9. S 다이어그램 생성: 실제 질문 1회, 손그림 스타일, 노드 옮기면 선이 따라옴
  - 원본(`studio-diagrams.jpg`, `agent3/diagrams-*.png`): 그리는 동안 보드에 자리표시 틀과 "… is drawing" 알약, 끝나면 손그림 상자·화살표·라벨·그룹 점선 틀이 보드에 바로 놓인다. 우리 쪽이 같다. 차이는 찾지 못했다.
  - 확인한 실제 입력(질문 7, 새 상태 /tmp/symv4o): 왼쪽 막대 다이어그램 → 열리자마자 설명 칸에 "how hello.py uses util.py" → Return → 약 13초 동안 손그림 자리표시 세 상자와 "Claude Code is drawing"(`S-drawing-placeholder.png`) → 제목·그룹 점선 틀 3개·손그림 상자 8개·라벨 붙은 화살표가 약 1초에 걸쳐 차례로 놓이고 전체 맞춤(`S-diagram.png`) → "stdout" 상자를 실제로 끌어 아래로 옮김 → "prints to" 화살표가 새 자리로 따라옴, 속성 막대(Sketch·Hand)(`S-node-moved.png`).

## 하루 쓰기 흐름 (새 SYMBOARD_HOME, /tmp/symday)

예제 레포 `/tmp/symday`: calc.py(add, 버그 있는 sub), test_calc.py(test_add 통과, test_sub 실패), README.md, 로컬 git(원격 없음).

**1차(상태 /tmp/symv4day): 7단계에서 멈춤.** 1~6 은 됐고, 7단계 git 칩에서 커밋한 뒤 orca 가 "초점 창 없음" 으로 Cmd+Q·Esc 를 모두 거부했다(입력칸이 사라진 git 팝오버 창이 남아 키를 받을 곳이 없었다). 고침: 커밋 뒤 남은 변경이 없으면 팝오버를 닫고 결과를 알리고 본 창을 키 창으로(`onCommitted`). 그 사이 6단계에서 칸반 "Add card" 가 안 눌린 것처럼 보였는데, 캡처 배율(0.914)을 빼먹은 내 좌표 계산 실수였다(디버그 `hit` 로 칸반이 클릭을 받는 것을 확인). 2차 첫 시도는 컴포저 셋째 타일을 한 번만 눌러 Codex 가 되어 바로 처음부터 다시 했다(질문 전).

**2차(상태 /tmp/symv4day2, 새 예제 레포): 1~8 한 번에 통과.**

- [x] 1. 홈 화면(Projects · Open folder) → Open folder → Cmd+Shift+G `/tmp/symday` → 보드가 symday 로(`day-1a-home.png`, `day-1.png`).
- [x] 2. Group → Testers → − 한 번 → 셋째 타일 두 번(Claude→Codex→Shell) → Spawn 3 → TESTERS 프레임 Ada·Pip(claude)·Maya(셸)(`day-2a-composer.png`). 폴더는 1차에서 신뢰해 둔 상태라 신뢰 화면이 없었다. Pip ⌄ → Permissions → Ask Before Tools → "manual mode on", ASK 배지(`day-2.png`).
- [x] 3. 명령 바에 "@testers run the tests and tell me which one fails, do not fix" → Return(`day-3.png`). Maya(셸)에도 들어가 "command not found" — @team 은 팀 전체에 보낸다.
- [x] 4. 미션 맵(1초 캡처 `day-4-sequence.png`): Working 2 → Working 1·Needs you 1(Pip 권한) → Done 1(Ada)·Needs you 1. 그룹 머리 "1 needs you · 1 done"(`day-4.png`).
- [x] 5. 미션 맵 Pip 클릭 → Go to the console → 노란 테두리 Pip, "Do you want to proceed? ❯ 1. Yes"(`day-5a-goto.png`) → Return → working → 두 번째 권한(pytest 가 없어 unittest 로 다시) waiting → Return → done → (그 노드를 보고 있어서) idle. 답: "test_sub fails with AssertionError: 8 != 2 … I haven't changed anything"(`day-5.png`).
- [x] 6. 오른쪽 막대 → Board → 캔버스 클릭 → TO DO "Add card" → 바로 "Fix sub(): returns a+b (test_sub fails)" → Return → 카드(`day-6.png`, state.json 에 저장).
- [x] 7. 명령 바 "@Maya echo 'test_sub fails: sub returns a+b' > RESULT.md" → 브랜치 칩 → 바로 "Record failing test" → Return → 커밋 9b79acb, 팝오버가 닫히고 보드로(`day-7a.png`, `day-7.png`).
- [x] 8. Cmd+Q(orca hotkey) → 종료 → 같은 상태 폴더로 다시 실행 → 같은 화면 자리와 "Resume all conversations? 2 consoles" 토스트·노드별 말풍선(`day-8a-toast.png`) → Yes → 노드 위치·세션 id 가 종료 전과 같음(diff 없음), Ada·Pip 에 앞 대화(test_sub 답)가 그대로, Pip 은 ASK 그대로(`day-8.png`).

## 막힌 것

(없음. 시험 도구 한계는 각 항목과 REPORT-4 에 적었다.)

## 완료 기준 확인

- `swift build -c release` 통과, `swift test` 119개 통과(3차 92개). 상태 판정 화면 글자 표본 테스트: claude 신뢰·테마 메뉴, codex 신뢰·업데이트·데몬 메뉴, 평소 입력창, 번호 목록 답, 스크롤된 옛 화면, NUL 칸, Done 판정 6개.
- 고칠 것 1~8 실제 입력으로 확인. 다시 눌러 볼 화면 1~9 비교·고침 기록. 하루 쓰기 흐름 2차 한 번에 통과.
- 새 충돌 기록 없음(`Symboard-*.ips` 마지막 13:43 그대로).
- 실제 CLI 질문 11회(한도 12).
