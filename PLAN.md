STATUS: IN_PROGRESS

# Symboard 계획

순서: 0 → 1 → 2 → 4 → 3 → 나머지. 각 항목은 빌드·테스트 통과 후 체크하고 메모를 남긴다.

## 체크리스트

- [x] 0. 뼈대: SwiftPM 패키지(SymboardCore 라이브러리 + Symboard 실행 타깃 + 테스트), SwiftTerm 의존성, `scripts/bundle.sh` 로 `build/Symboard.app` 생성
- [x] 1a. 보드: 무한 캔버스(이동·확대/축소)
- [x] 1b. 보드: 노드 끌어서 이동·크기 조절
- [x] 1c. 보드: 작업공간 여러 개를 탭처럼 전환
- [x] 2a. 터미널 노드: SwiftTerm + forkpty 로 셸 실행(Ctrl-C·vim·htop)
- [x] 2b. 터미널 노드: 새 노드 생성 시 CLI 선택(claude, codex, 임의 실행 파일)
- [x] 4a. 이어하기: 작업공간 자동 저장(버전 붙은 JSON, ~/Library/Application Support/Symboard/)
- [x] 4b. 이어하기: 재실행 시 노드 위치·크기·CLI 복원, claude `--session-id`/`--resume`, codex `resume --last`
- [x] 3a. 상태: Claude Code 훅(`--settings` 로 주입) → 앱에 신호
- [x] 3b. 상태: 훅 없는 CLI 는 출력 멈춘 시간으로 추정
- [x] 3c. 상태: 전체 노드 목록 패널(미션 맵)
- [x] 5. 컴포저(최대 12개 한 번에)와 팀(묶기·역할 이름)
- [x] 6. 루프(시간 간격/유휴/특정 출력 시작, 목표 문구로 자동 종료)
- [x] 7. 넘겨주기(보내는 노드 CLI 에 요약 요청 → 다른 노드에 입력)
- [x] 8a. 메모 도구: 스티키·텍스트·체크리스트·칸반 노드
- [x] 8b. 메모 도구: 펜 그리기, 이미지 드롭 후 표시
- [x] 9. 웹 타일(WKWebView, 웹 인스펙터)
- [x] 10. git 카드(브랜치·상태, commit·push·pull)
- [x] 11a. 스튜디오: 코드(파일 트리·하이라이트·노드로 고정)
- [x] 11b. 스튜디오: 마크다운(파일 트리·자동 저장 편집기·링크 그래프)
- [x] 11c. 스튜디오: 문서(마크다운 → PDF), 다이어그램(PNG 내보내기)
- [ ] 12. 사용량(로컬 세션 로그에서 날짜별·에이전트별 토큰)
- [ ] 13. 계정 프로필(CLI 별 설정 폴더 환경 변수)
- [ ] 14. 메모리(레포별·전역 메모, 버튼으로 노드에 보내기)
- [ ] 15. 완료 기준 확인(스크린샷 docs/screens/, README.md, REPORT.md)

## 메모

- 0: `swift build`, `swift test`(15개 통과), `scripts/bundle.sh` → `build/Symboard.app` 생성 확인. 이전 회차가 남긴 미커밋 코드(보드·터미널·저장·상태 일부 포함)를 이 커밋에 함께 올렸다. 해당 항목은 각각 실행 확인 후 따로 체크한다.
- 1a: 디버그 통로 `zoom`(0.5)·`fit` 후 창 캡처로 축소된 보드 확인(`docs/screens/03-zoomed-out.png`). Cmd+스크롤 확대/축소, 빈 곳 끌어 이동은 BoardScrollView/CanvasView 코드.
- 1b: 디버그 `drag` 명령(창에 NSEvent 마우스 이벤트를 직접 넣음)으로 헤더 끌기 +100,+40 → frame -250,90 / 손잡이 끌기 -120,-80 → 520x320, state.json 에도 반영 확인.
- 1c: `addWorkspace`·`selectWorkspace` 로 탭 2개 전환, 각 작업공간 노드·배율 유지 확인(`docs/screens/02-second-workspace.png`, `03-zoomed-out.png`).
- 2a: SwiftTerm LocalProcessTerminalView(forkpty). 노드에서 `vim` 열기→Esc `:q!` 로 닫힘, `sleep 100` 에 Ctrl-C(0x03) → 프롬프트 복귀 확인(디버그 `screen` 출력, `docs/screens/01-three-terminals-restored.png`). htop 은 이 맥에 없어 top 으로 대신 봤다.
- 4a: 바뀔 때 0.4초 모아 `state.json`(version 1) 저장. SYMBOARD_HOME=/tmp/symtest 로 띄워 노드 3개 만든 뒤 종료→재실행, 같은 frame 으로 복원 확인. 기본 경로는 ~/Library/Application Support/Symboard/.
- 주의: 창이 가려지면 App Nap 으로 타이머가 멈춰 디버그 통로가 응답하지 않았다 → AppDelegate 에서 beginActivity 로 끔.
- 2b: 도구 막대 New Terminal 대화상자에서 Claude Code·Codex·Shell·Custom(실행 파일 경로)·인자·폴더·프로필 선택(`docs/screens/04-new-terminal-dialog.png`).
- 4b: 옵션은 `claude --help`(`--session-id`, `--resume`, `--settings`), `codex resume --help`(`[SESSION_ID]`, `--last` 는 기본이 현재 폴더로 걸러짐)로 확인. /tmp/symclaude 에서 claude 에 hello → 종료 → 재실행 시 `claude --resume <id>` 로 같은 대화 복원(`docs/screens/05-claude-resumed.png`). /tmp/symcodex 에서 codex 에 hello → 세션 파일에서 id 찾아 기록 → 재실행 시 `codex resume <id>` 로 복원(`docs/screens/06-claude-codex-resumed.png`).
  - 고친 것: 앱을 Claude Code 세션 안에서 띄우면 CLAUDE_CODE_CHILD_SESSION 등이 자식에게 물려져 claude 가 대화 기록을 저장하지 않았다("Transcript saving is off" 경고를 화면에서 봄). 자식 환경에서 세션 표시 변수를 지운다. 또 /tmp 는 /private/tmp 로 기록되므로 realpath 로 맞춘다(claude 기록 존재 확인, codex 세션 cwd 비교 둘 다).
- 3a: `--settings` 에 훅 JSON 을 넣어 주입(사용자 ~/.claude 설정은 건드리지 않음). 훅은 SYMBOARD_STATUS_FILE 에 상태 단어를 쓴다. hello 직후 state=working, 응답 뒤 status 파일 내용 `idle` 확인. 입력 기다림(PermissionRequest·Notification)은 실제 권한 요청을 일으키지 않으려고 실행 확인은 안 했고 단위 테스트(hookSettingsIsValidJSON·hooksOverrideOutput)로만 봤다. 폴더 신뢰 화면처럼 훅이 켜지기 전 화면은 Idle 로 보인다.
- 3b: 훅 없는 노드는 마지막 출력 후 3초가 지나면 Idle. vim 출력 중 Working → 멈춘 뒤 Idle 확인(디버그 `state`, 스크린샷 01).
- 3c: 오른쪽 Mission 패널에 모든 작업공간의 터미널 노드와 상태·유휴 시간·작업공간 이름, 상단에 상태별 개수(스크린샷 03). 줄을 누르면 그 노드로 이동.
- 8a: 도구 막대 Add 메뉴로 스티키(색 바꾸기)·텍스트·체크리스트(진행 막대)·칸반(카드 좌우 이동) 노드. SwiftUI 본문을 NSHostingView 로 붙이고 편집 즉시 모델에 저장. 디버그 `addNode` 로 만들고 화면 확인(`docs/screens/07-notes.png`), 재실행 후 내용 유지 확인. 키보드로 직접 타이핑하는 경로는 자동 확인하지 않았다.
- 8b: 펜 버튼을 켜고 보드 위를 끌면 획 저장(디버그 `stroke` 로 실제 마우스 이벤트, state.json strokes 1). 이미지는 끌어다 놓기 또는 Add > Image... 로 추가하고, 펜이 켜진 채 이미지 위를 끌면 이미지 기준 0~1 좌표로 표시 저장(스크린샷 07 의 빨간 선). Add > Clear Pen Drawings, 노드 메뉴 Clear Markup.
- 5: 도구 막대 Composer(프로그램·개수 1~12·폴더·팀 이름·역할 쉼표 목록) → 격자로 띄우고 새 팀으로 묶음. 노드 메뉴 Team > New Team.../기존 팀 지정, Set Role.... 디버그 `team` 으로 12개 띄워 격자·역할·팀 배지·Mission 패널 확인(`docs/screens/08-composer-team.png`, `09-composer-dialog.png`). 격자 배치·역할 펴기는 단위 테스트(ComposerTests).
- 6: 판정은 SymboardCore LoopEngine(단위 테스트 5개), 실행은 LoopRunner(1초 틱 + 노드 출력 구독). 패널 Loops 탭(켜기/끄기·삭제·New Loop), 터미널 노드 메뉴 Add Loop.... 셸 노드 3개로 확인: 5초 간격 2회 전송 → `echo GOALHIT` 출력에 스스로 꺼짐, 출력에 PING 이 나오자 1회 전송, 유휴 4초 조건 2회 후 최대 횟수로 정지(디버그 `loops`, `docs/screens/10-loops.png`).
- 7: 터미널 노드 메뉴 Hand Off To... → 받을 노드 선택 → 보내는 노드에 요약 요청(HANDOFF-BEGIN/END 표시 사이에 쓰라고) → 일했다가 다시 쉬면 답을 읽어 확인 창(편집 가능) 뒤 받는 노드에 입력. 답은 claude 는 대화 기록 jsonl, codex 는 세션 jsonl 의 마지막 assistant 글(형식은 디스크에서 확인, 단위 테스트 HandoffTests), 그 밖은 화면 출력에서 표시 사이를 찾는다. 실제 에이전트에 일을 시키지 않으려고 가짜 에이전트 스크립트 두 개로 확인(디버그 `handoff` 자동 전송, `docs/screens/11-handoff.png`). claude·codex 로 실제 요약을 받는 것은 실행 확인하지 않았다.
  - 고친 것: bracketed paste 를 프로그램이 그 모드를 켰을 때만 쓰게 했다(안 켠 프로그램에 ^[[200~ 가 그대로 찍혔다).
- 9: Add > Web Tile... 로 주소 입력. WKWebView + 주소 칸, Info.plist 에 NSAllowsLocalNetworking. 노드 메뉴 Open Web Inspector(WKWebView 내부 _inspector 객체가 있으면 show, 없으면 오른쪽 클릭 Inspect Element 안내; developerExtrasEnabled·isInspectable 켬). /tmp/symweb 를 python http.server 8765 로 띄워 페이지 표시와 인스펙터 열림 확인(`docs/screens/12-web-git.png`, `13-web-inspector.png`).
- 10: Add > Git Card... 로 레포 선택. `git status --porcelain=v2 --branch` 파싱(단위 테스트 GitStatusTests)으로 브랜치·추적·앞뒤 개수·변경 파일, Commit All(add -A + commit)·Pull(--ff-only)·Push 버튼, 결과 로그 표시. GIT_TERMINAL_PROMPT=0 으로 비밀번호 대기 방지. /tmp/symgit(+ /tmp 로컬 bare 레포를 origin 으로) 에서 커밋 → 푸시 → 다른 클론에서 푸시한 것 풀까지 확인(디버그 `git`/`gitState`).
- 11: 도구 막대 Studio 로 별도 창. 탭 4개. 확인 폴더 /tmp/symstudio(마크다운 4개 + swift 파일).
  - 11a Code: 파일 트리(.git·.build·node_modules 등 제외), 정규식 기반 하이라이트(키워드·문자열·주석·숫자, 단위 테스트), Pin to Board → file 노드(`docs/screens/14-studio-code.png`, `21-pinned-file.png`).
  - 11b Markdown: .md 트리, 편집기 0.6초 뒤 자동 저장(디버그로 내용 바꾼 뒤 파일 내용과 "Saved" 표시 확인), [[링크]]·[글](x.md) 링크 그래프(`15`, `16-studio-link-graph.png`).
  - 11c Docs: 마크다운 → HTML 미리보기 → Export PDF(WKWebView createPDF 로 긴 한 장을 받아 Letter 쪽으로 자름). README 1쪽, 150문단 문서 8쪽 확인(`17-studio-docs.png`, `19-docs-export-page1.png`). Diagram: `A -> B: 라벨` 줄 형식, 순환 간선은 깊이 우선 탐색으로 빼고 층 배치, 되돌아가는 간선은 아래로 점선, Export PNG(ImageRenderer) 확인(`18`, `20-diagram-export.png`).
  - 사고와 수정: 처음엔 화면 밖 WKWebView 의 printOperation 으로 PDF 를 만들었는데 쪽 나누기가 끝나지 않아 파일이 1.4GB 까지 커졌다. 즉시 앱을 죽이고 파일을 지운 뒤 createPDF + 직접 쪽 자르기(최대 300쪽)로 바꿨고, 다시 시험할 때는 20MB 감시 스크립트를 함께 돌렸다.

## 막힌 것

