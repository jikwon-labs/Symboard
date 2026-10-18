STATUS: IN_PROGRESS

# Symboard 7차 진행표

기준 커밋 `1fb534a` (6차 완료본). 6차 테스트 수 162.
모든 시험은 Finder 와 같은 환경으로 띄운 앱에서 한다:
`env -i HOME=$HOME USER=$USER LOGNAME=$USER SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin SYMBOARD_HOME=/tmp/symv7-N build/Symboard.app/Contents/MacOS/Symboard &`
확인은 `orca computer`(`scripts/input/ui.sh`) 실제 클릭·키 입력.

## 버전 확인

| 때 | codex |
|----|-------|
| 시작 | 0.163.0 (프롬프트가 기대한 0.157.1 과 다름. 이번 회차가 바꾼 것 아님, 시작 시점에 이미 0.163.0) |

## 실제 CLI 질문 수 (한도 3)

합계: 0

## 바꾸기 전 명령 바·오케스트레이터 입력칸이 하던 일

명령 바(`ChromeViews.swift` BottomBar, SwiftUI `TextField`):
- a. Enter 로 `runCommand()` (보드 명령 · `@대상 본문` · 고른 콘솔로 보내기 · `/close @이름`).
- b. 자리표시 "Type a command · @ to direct", 터미널을 고르면 "Message <이름> · @ to direct".
- c. 안내 알약 "Try @all git status" 를 누르면 입력칸에 그 글을 넣고 초점을 준다.
- d. 오른쪽 보내기 단추(빈 칸이면 회색, 글이 있으면 주황).
- e. 한 줄 입력. Shift+Enter 줄바꿈 없음(TextField 는 한 줄), 위·아래 기록 없음, 이미지 붙여넣기 없음 — 원래 없던 기능이라 지킬 것도 없음.
- f. 글자 13pt, 글자색 symText, 테두리·배경 없음(캡슐이 배경).
- g. 입력 중 키 단축키(V 등)가 먹지 않는다(초점이 글 편집기에 있음).

오케스트레이터 입력칸(`Orchestrator.swift` commandField):
- h. Enter 로 `orchestratorSend` (연결된 콘솔 전체, 또는 맨 앞 `@대상`). 보내면 비운다.
- i. 자리표시 "Command N agents · @ to direct", 12pt.
- j. 보내기 단추.

## 할 일

- [x] 1. @ 자동완성(명령 바·오케스트레이터), 넣은 이름 색칠, 여러 대상, 한글 IME
  - 만든 것: `SymboardCore/Mention.swift`(커서 앞 @ 토큰 찾기·좁히기·넣기·색칠 범위, UTF-16 단위), `MentionField.swift`(NSTextField 감싼 입력칸 + 자기 글 편집기 + 알약 배경 + 목록 뷰).
    두 입력칸 모두 SwiftUI `TextField` 에서 `MentionField` 로 바꿨다. 목록: 살아 있는 콘솔 → all → 그룹(`group 1`). 오케스트레이터는 연결된 콘솔만.
  - 여러 대상: `CommandTargets.parse` 는 원래 맨 앞 @ 토큰 여러 개를 받았다. 빈칸 든 그룹 이름(`@group 1`)만 가장 길게 맞는 이름으로 잡게 고쳤다.
  - 대상으로 보는 @ 는 맨 앞에 이어 붙은 것뿐이다(본문 중간 `@file` 은 목록·색칠 없음, claude 에 보내는 파일 언급과 겹치지 않게).
  - 한글: 조합 중(`hasMarkedText`)에는 색칠·목록 갱신·바깥 글 반영을 하지 않는다. 색칠은 글 자체가 아니라 layoutManager 임시 속성이라 조합 밑줄을 건드리지 않는다.
  - 바꾸기 전 목록(a~j) 다시 확인: a Enter 보내기(2·4·6 시험), b 자리표시(화면), c 안내 알약 → 글 넣고 초점(실제 클릭, 접근성 초점 = Command), d 보내기 단추 색(화면), e 해당 없음, f 13pt symText(화면), g 입력칸에 `v` 를 치면 글자로 들어감(단축키 아님), h·i·j 오케스트레이터(5 시험).
- [x] 2. 입력칸 I 커서(명령 바·오케스트레이터·칸반 카드·스티커·이름 바꾸기 등), closedHand 뒤 복귀
  - 원인: SwiftUI 입력칸은 AppKit 커서 사각형으로 I 커서를 걸지만, 그 위의 NSHostingView 가 cursorUpdate 로 화살표를 다시 건다. 기준본에서 `SYMBOARD_CURSORLOG` 로 입력칸 위 `NSCursor.current` = arrow 를 확인했다. BoardView 의 closedHand push/pop 은 짝이 맞았다(원인 아님).
  - 고침: `TextCursor`(CursorWatch.swift) 가 마우스 이동마다 hitTest 로 마우스 아래가 편집 가능한 NSTextView/NSTextField 인지 보고 I 커서를 건다. 벗어나면 자기가 건 I 커서만 화살표로 돌린다(터미널·손 모양은 건드리지 않음).
  - 커서 확인법: 화면 캡처에 커서가 안 찍혀 `SYMBOARD_CURSORLOG=<파일>` 로 띄우면 0.1초마다 `NSCursor.current` 와 마우스 아래 뷰를 바뀔 때만 적는다. 마우스는 `cgclick move X Y`(실제 mouseMoved 여러 걸음)로 옮긴다.
- [ ] 3. 터미널 글꼴 설정(영문 고정폭·한글 글꼴·크기, cascade list, 즉시 적용·유지)

## 완료 기준 실제 입력 기록

한 인스턴스(`SYMBOARD_HOME=/tmp/symv7-3`, 7차 1·2 코드 번들)에서 2026-10-18 22:06~22:10 에 이어서 했다.
준비만 DebugBridge(`openProject /tmp/symshell`, `spawn 4 shell`, `orchestrator wired to group 1`, 칸반·스티커 놓기). 판정은 모두 실제 클릭·키.

1. [x] 명령 바 클릭 → `@` → Ada·Pip·Maya·Iris·all·group 1, 줄마다 Shell 배지·READY 점. `docs/screens/v7/1-at-list.png`
2. [x] `p` → @Pip 한 줄(`2-typed.png`) → Tab → 값 `@Pip `, 주황 글자+알약(`2-tab-pip.png`) → `echo hi` 치니 값 `@Pip echo hi` → Enter → Pip 에만 `hi`, 알림 "Sent to 1 console"(`2-sent-pip.png`).
3. [x] `@` → Down 두 번 → @Maya 골라짐(`3-down2.png`) → Tab → 값 `@Maya `(`3-tab.png`). 이어 `@` → Esc → 목록만 닫히고 값 `@Maya @` 그대로(`3-esc.png`).
4. [x] `@Ada @Maya echo two` → Enter → Ada·Maya 에만 `two`, "Sent to 2 consoles"(`4-typed.png`, `4-sent.png`).
5. [x] 오케스트레이터 입력칸 클릭 → `@` → 같은 6줄(`5-orch-at-list.png`) → `p` → Tab → `@Pip ` 주황(`5-orch-tab-pip.png`) → `echo orch` → Enter → Pip 에만, "Sent to 1 agent"(`5-orch-sent.png`).
6. [x] ABC 로 `@Iris ` → 한글 2벌식으로 바꾸고 실제 키 코드 `dkssud` → 값 `@Iris 안녕`, 녕 조합 밑줄, @Iris 색 그대로(`6-composing.png`) → Enter 한 번(조합 확정+보내기) → Iris 에만 `안녕`(zsh: command not found: 안녕)(`6-sent.png`).
   - 시험 방법 주의: `orca computer type-text`·`press-key` 는 글자를 바로 넣어 입력기를 거치지 않는다(`dkssud` 가 그대로 들어감). `cgclick keys dkssud`(CGEvent 키 코드) 로 쳐야 한다. 또 입력 소스를 바꾼 뒤 앱을 한 번 다른 앱 → 다시 앞으로 돌려야 입력 칸이 새 입력 소스를 받았다.
   - 한글 상태에서 `@`(Shift+2) 자체를 치는 것은 시험하지 않았다(`@Iris ` 는 ABC 로 쳤다).
7. [x] `cgclick move` 로 실제 마우스를 옮기고 커서 기록(`/tmp/symv7-3.cursor`)을 읽었다.
   빈 캔버스 arrow → 명령 바 iBeam(MentionTextField) → 캔버스 arrow → 오케스트레이터 입력칸 iBeam → 캔버스 arrow → 칸반 Add card 편집 창 제목 iBeam·메모 iBeam(`7-kanban-editor.png`) → 그 아래 단추 arrow → 캔버스 arrow → 스티커 iBeam → 캔버스 arrow.
   캔버스 끌기 중 closedHand → 놓은 뒤 arrow → 명령 바 iBeam → 캔버스 arrow(두 번 반복).
8. [ ] 터미널 한글 글꼴 (3번 항목)

## 막힌 것

(없음)
