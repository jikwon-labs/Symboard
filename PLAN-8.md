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
- [ ] 2. 새 콘솔을 기존 노드 옆 빈 칸에 놓고 화면을 부드럽게 옮기기
- [ ] 3. claude 가 보드에 콘솔을 띄우는 MCP 도구(list/spawn/send/read/close), 설정 스위치, 부른 콘솔과 옅은 선
- [ ] 4. 명령 바 여러 줄(Shift+Enter, 3줄까지 자람, Cmd+Shift+E 전체 화면 편집, claude·codex 에는 bracketed paste)
- [ ] 5. @ 대상마다 다른 글 보내기(단위 테스트)
- [ ] 6. 왼쪽 아래 ? 단추와 단축키 표, `?` 키
- [ ] 7. 콘솔 안 Cmd·Option 이동과 지우기(단위 테스트)
- [ ] 8. 콘솔 안 한글 글자 사이 틈
- [ ] 9. 콘솔 안 조합 중 한글 보이기
- [ ] 10. Ctrl+Tab·Cmd+1~9 로 콘솔 사이 옮기기, 번호 배지, Zoom to Fit 은 Cmd+Shift+1

## 막힌 것

## 완료 기준 실제 입력 기록
