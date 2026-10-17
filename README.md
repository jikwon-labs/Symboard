# Symboard

큰 캔버스 위에 Claude Code·Codex 같은 에이전트 터미널을 여러 개 띄우고, 누가 일하는 중이고 누가 입력을 기다리는지 한눈에 보며, 앱을 껐다 켜도 그대로 이어지는 macOS 앱. Swift(AppKit + 일부 SwiftUI), 터미널은 SwiftTerm.

macOS 14 이상, Apple Silicon. 개인용이라 로그인·결제·자동 업데이트·음성 비서는 없다.

## 빌드와 실행

```bash
swift build -c release   # 빌드
swift test               # 단위 테스트(SymboardCore)
scripts/bundle.sh        # build/Symboard.app 생성(release 빌드 포함)
open build/Symboard.app  # 실행
```

- 의존성: SwiftTerm 1.11.2 고정(1.12 부터는 Metal Toolchain 이 있어야 빌드된다, `DECISIONS.md`).
- 상태 저장 위치: `~/Library/Application Support/Symboard/state.json`(버전 붙은 JSON). 환경 변수 `SYMBOARD_HOME` 으로 다른 폴더를 쓸 수 있다(시험용).
- 훅 상태 파일: 같은 폴더의 `status/<노드 id>`.

## 기능

| 영역 | 내용 | 여는 곳 |
| --- | --- | --- |
| 보드 | 무한 캔버스, 빈 곳 끌어 이동, Cmd+스크롤·Cmd +/-/0/9 확대·축소·맞춤, 노드 헤더 끌기·오른쪽 아래 손잡이로 크기 조절 | 메인 창 |
| 작업공간 | 위쪽 탭, + 로 추가, 탭 오른쪽 클릭으로 이름 바꾸기·삭제, Cmd+Shift+[ ] 전환 | 탭 막대 |
| 터미널 노드 | 진짜 PTY(SwiftTerm, forkpty). 실행할 것: Claude Code, Codex, Shell, 임의 실행 파일. 폴더·인자·계정 프로필 선택 | New Terminal(Cmd+T), 보드 빈 곳 더블클릭 |
| 상태(미션 맵) | 일하는 중 / 쉬는 중 / 입력 기다림 / 종료. Claude Code 는 `--settings` 로 주입한 훅이 신호를 보내고, 나머지는 출력이 3초 멈추면 쉬는 중 | 노드 헤더, 오른쪽 패널 Mission |
| 이어하기 | 노드 위치·크기·CLI 복원. claude 는 앱이 정한 `--session-id` 로 시작하고 다시 켤 때 `--resume <id>`, codex 는 세션 파일에서 찾은 id 로 `codex resume <id>`(못 찾으면 `--last`) | 자동 |
| 컴포저·팀 | 최대 12개 노드를 격자로 한 번에 띄우고 팀으로 묶기, 역할 이름. 노드 메뉴에서 팀·역할 바꾸기 | Composer, 노드 메뉴 |
| 루프 | 정해진 문장을 시간 간격 / 유휴 / 특정 출력 등장 때 자동 입력, 목표 문구가 나오거나 최대 횟수에 닿으면 꺼짐 | 패널 Loops, 터미널 노드 메뉴 Add Loop |
| 넘겨주기 | 보내는 노드의 CLI 에게 요약을 요청 → 대화 기록(또는 화면)에서 요약을 읽어 확인 창 → 받는 노드에 입력. 외부 API 없음 | 터미널 노드 메뉴 Hand Off To |
| 메모 도구 | 스티키(색), 텍스트, 체크리스트, 칸반 노드. 펜으로 보드에 그리기, 끌어다 놓은 이미지 위에 표시 | Add, Pen |
| 웹 타일 | WKWebView 로 localhost 등 주소 표시, 웹 인스펙터 | Add > Web Tile, 노드 메뉴 |
| git 카드 | 브랜치·추적·앞뒤 커밋 수·변경 파일, Commit All·Pull(--ff-only)·Push. 로컬 git 만 씀 | Add > Git Card |
| 스튜디오 | Code(파일 트리·하이라이트·보드에 고정), Markdown(트리·자동 저장 편집기·링크 그래프), Docs(마크다운 → PDF), Diagram(`A -> B: 라벨` → PNG) | Studio |
| 사용량 | Claude Code·Codex 로컬 세션 로그에서 날짜별·에이전트별 토큰 | 패널 Usage |
| 계정 프로필 | CLI 별 설정 폴더를 따로(claude: `CLAUDE_CONFIG_DIR`, codex: `CODEX_HOME`) 두어 두 계정을 동시에 | 패널 Profiles, New Terminal |
| 메모리 | 레포별·전역 메모. 버튼을 눌렀을 때만 고른 노드에 입력(기본은 Enter 없이) | 패널 Memory |

## 구조

- `Sources/SymboardCore`: UI 없는 로직. 모델·저장, 실행 계획(이어하기·훅 주입), 상태 판정, 루프 판정, 넘겨주기 요약 읽기, git 상태 파싱, 스튜디오(하이라이트·마크다운·다이어그램), 사용량 파싱. 단위 테스트는 여기에.
- `Sources/Symboard`: AppKit 앱. 보드(`BoardView`, `NodeView`), 터미널(`TerminalSession`), 각 노드 본문, 패널, 스튜디오 창.
- `scripts/bundle.sh`: `.app` 번들. `scripts/drive.sh`: 자동 확인용 디버그 통로(아래).

### 디버그 통로

`<상태 폴더>/debug/` 가 있으면 앱이 0.5초마다 `cmd.json` 을 읽어 명령을 실행하고 `result.txt` 에 결과를 쓴다. `scripts/drive.sh '<JSON 배열>'` 로 쓴다. 노드 만들기, 키 보내기, 화면 텍스트 읽기, 마우스 끌기(실제 NSEvent), 창 번호(`screencapture -l` 용) 등. 개발·확인용이고, 폴더가 없으면 아무 일도 하지 않는다.

## 확인한 것

`PLAN.md` 의 메모에 항목마다 확인 방법을 적었다. 스크린샷은 `docs/screens/`. 마지막 확인(`open build/Symboard.app` 으로 띄워 터미널 3개 → vim 열고 닫기 → claude 띄우기 → 종료 → 다시 실행 시 같은 자리로 복원)은 `final-1` ~ `final-3`.

## 포기한 것과 한계

포기한 항목은 없다. 다만 아래는 확인 범위나 구현이 원본보다 좁다.

- htop: 이 맥에 설치돼 있지 않아 확인하지 못했다(설치는 하지 않음). vim·Ctrl-C·Claude Code·Codex 화면으로 확인했다.
- 입력 기다림 상태(Claude Code 의 권한 요청 훅): 실제 권한 요청을 일으키지 않으려고 실행 확인은 안 했고 단위 테스트로만 봤다. 폴더 신뢰 화면처럼 훅이 켜지기 전 화면은 Idle 로 보인다.
- 넘겨주기: 실제 에이전트에 요약 일을 시키지 않으려고 가짜 에이전트 스크립트로 확인했다. claude·codex 대화 기록에서 마지막 답을 읽는 부분은 디스크의 실제 형식으로 단위 테스트했다.
- 웹 인스펙터: WKWebView 는 인스펙터를 여는 공개 API 가 없어 내부 객체(`_inspector`)를 있을 때만 쓴다. 없으면 오른쪽 클릭 Inspect Element 로 안내한다.
- 다이어그램은 Mermaid 가 아니라 `A -> B: 라벨` 한 줄 형식만 지원한다.
- 사용량은 로그에 남은 토큰 수만 보여 준다(금액 환산 없음). 이 맥 로그 549개 기준 한 번 읽는 데 약 7초.
- 메모 노드에 키보드로 직접 타이핑하는 경로는 자동 확인하지 않았다(내용 저장·복원은 확인).
- 셸 프롬프트의 Nerd Font 글리프는 기본 고정폭 글꼴에 없어 네모로 보인다.
