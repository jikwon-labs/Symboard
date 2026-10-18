STATUS: IN_PROGRESS

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

합계: 4

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
- [ ] 5. 글 쓰는 창이 열리자마자 첫 칸에 초점, Enter 저장 / Esc 취소(여러 줄은 Cmd+Enter)
- [ ] 6. 칸반 Done 열 카드 표시
- [ ] 7. 앱이 스스로 만드는 노드(인스펙터, 복제, 컴포저 그룹, 문서·다이어그램 결과)도 보이는 영역 안으로
- [ ] 8. 셸 Ctrl+C 실제 입력 확인(`sleep 100` 끊기)

## 다시 눌러 볼 화면

- [ ] 1. G 계정 프로필: 추가, 바꾸기, 노드에 적용
- [ ] 2. N 사용량: 팝오버 숫자, 고리, 초기화 시각
- [ ] 3. H 체크리스트·캘린더: 항목 추가·체크, 일정 추가
- [ ] 4. I 이미지: 끌어 놓기 또는 붙여 넣기, 크기 조절
- [ ] 5. C 오케스트레이터: 끌어서 팀과 연결, 연결 끊기, 연결된 팀에만 명령
- [ ] 6. O·P 코드 스튜디오: 파일 열기, 고치기, 저장, 탭 여러 개
- [ ] 7. Q 마크다운 스튜디오: Reading/Source/Graph 전환, 링크 따라가기
- [ ] 8. R 문서 생성: 실제 질문 1회, 실시간으로 그려지는지
- [ ] 9. S 다이어그램 생성: 실제 질문 1회, 손그림 스타일, 노드 옮기면 선이 따라옴

## 하루 쓰기 흐름 (새 SYMBOARD_HOME, /tmp/symday)

- [ ] 1. 홈 화면 → Open folder
- [ ] 2. Group 으로 claude 2 + 셸 1 팀, claude 하나는 자동 승인 끔
- [ ] 3. `@team` 으로 "run the tests and tell me which one fails, do not fix" (질문 2회)
- [ ] 4. 미션 맵에서 Working → Needs you(권한) → Done
- [ ] 5. 권한 기다리는 노드로 Go to → 승인 → 끝날 때까지
- [ ] 6. 칸반에 결과 카드
- [ ] 7. git 카드에서 로컬 커밋
- [ ] 8. Cmd+Q → 다시 실행 → 이어하기 토스트 → 같은 자리·같은 대화

## 막힌 것

(없음)
