# Symboard

큰 캔버스 위에 Claude Code·Codex 같은 에이전트 콘솔을 여러 개 띄우고, 누가 일하는 중이고 누가 입력을 기다리는지 한눈에 보며, 앱을 껐다 켜도 그대로 이어지는 macOS 앱. Swift(AppKit + SwiftUI), 터미널은 SwiftTerm.

macOS 14 이상, Apple Silicon. 개인용이라 로그인·결제·자동 업데이트·음성 비서는 없다. 문서·다이어그램·메모리 생성은 사용자가 이미 로그인한 CLI(claude, codex)를 백그라운드로 실행해서 만들고, 외부 API 키는 쓰지 않는다.

## 빌드와 실행

### 만들기

```bash
scripts/bundle.sh        # release 빌드 후 build/Symboard.app 생성(아이콘 포함)
swift test               # 단위 테스트(SymboardCore)
```

### 띄우기 — Finder 에서 더블클릭

1. Finder 에서 `build/Symboard.app` 을 더블클릭한다. (터미널에서는 `open build/Symboard.app`.)
2. 처음 뜨면 **Projects** 화면이다. **Open folder** 로 작업할 레포 폴더를 고른다.
3. 왼쪽 막대의 별(Spawn agent)을 누르면 이 맥에 깔린 CLI(Claude Code, Codex, Shell …)가 보인다. 하나를 고르고 캔버스를 누르면 콘솔이 뜬다.

Finder·Dock 으로 띄운 앱은 터미널의 PATH 를 물려받지 않는다. 그래서 앱이 시작할 때 사용자 로그인 셸(`$SHELL -l -i`)에서 PATH 를 한 번 얻어 온다. nvm·volta·asdf·mise·homebrew 로 깐 `claude`·`codex` 도 그대로 찾는다. 셸 설정이 4초 안에 끝나지 않거나 망가졌으면 흔한 설치 위치를 더해서 찾는다.

### /Applications 로 옮겨 쓰기

```bash
scripts/bundle.sh
ditto build/Symboard.app /Applications/Symboard.app   # 덮어써도 상태는 그대로(아래 상태 폴더)
open /Applications/Symboard.app
```

- 서명은 임시(ad-hoc) 서명이다. 다른 맥으로 옮겨 처음 열 때 막히면 Finder 에서 오른쪽 클릭 → 열기.
- Dock 에 고정하려면 실행 중에 Dock 아이콘 오른쪽 클릭 → 옵션 → Dock 에 유지.
- 창을 닫아도(Cmd+W) 앱과 콘솔은 계속 돈다. Dock 아이콘을 누르면 같은 창이 다시 열린다. 끝내려면 Cmd+Q. 다시 켜면 콘솔이 모두 복원되고, 이어 갈 대화가 있는 claude·codex 만 "Resume all conversations?" 로 묻는다.

### 그 밖

- 의존성: SwiftTerm 1.11.2 를 `Vendor/SwiftTerm` 에 옮겨 두고 읽기 작업이 쌓이는 문제 하나를 고쳤다(`Vendor/SwiftTerm/PATCHES.md`). 1.12 부터는 Metal Toolchain 이 있어야 빌드된다(`DECISIONS.md`).
- 시험할 때 Finder 와 같은 환경: `env -i HOME=$HOME USER=$USER LOGNAME=$USER SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin SYMBOARD_HOME=/tmp/sym-test build/Symboard.app/Contents/MacOS/Symboard`. `SYMBOARD_LAGLOG=1` 을 더하면 5초마다 메인 스레드 지연(p50·p95·최대)을 표준 오류에 남긴다.
- 상태 저장: `~/Library/Application Support/Symboard/state.json`(버전 붙은 JSON). 환경 변수 `SYMBOARD_HOME` 으로 다른 폴더를 쓸 수 있다(시험용). 1차 상태 파일을 그대로 읽는다(작업공간에 프로젝트 폴더를 붙이고 콘솔 이름을 짧은 이름으로 바꿈).
- 같은 폴더 아래: `status/`(훅 상태), `docs/`(문서 스튜디오 라이브러리), `profiles/`(새로 연결한 계정 설정 폴더).

## 화면

창 전체가 점 격자 캔버스이고, 그 위에 막대들이 떠 있다.

| 자리 | 내용 |
| --- | --- |
| 위쪽 왼쪽 | Home(프로젝트 목록) · 프로젝트(폴더) 드롭다운 · 작업공간 탭(노드 수 배지, 닫기, 두 번 눌러 이름 바꾸기) · + · Close |
| 위쪽 오른쪽 | N live · 사용량 알약(지금 5시간 묶음 재설정 시각 추정) · 계정 · 설정 · 도구 메뉴(미션 맵, 루프, 메모리 등) |
| 왼쪽 세로 막대 | 선택 · 에이전트 놓기(CLI 목록 → 캔버스 클릭) · 복제 · 글자 · 펜 · 지우개 · 도형 · 다이어그램 · 웹 · 이미지 · 전체 보기 |
| 오른쪽 세로 막대 | 레이어 · 삽입(체크리스트/보드/캘린더/스티키/오케스트레이터) · 설정 · 코드·마크다운·문서 스튜디오 · 루프(켜진 수 배지) |
| 아래 | New console · Spawn 4 · Group(컴포저) · Presets · Pause all · Resume all · Memory, 그 아래 명령 입력(`@이름`, `@팀`, `@all` 로 대상 지정, `/close @대상`) |
| 아래 왼쪽·오른쪽 | git 브랜치 칩(누르면 git 카드) · 배율 − N% + |

## 기능

| 영역 | 내용 |
| --- | --- |
| 콘솔 | 진짜 PTY. 헤더에 CLI 글자 배지, 상태 점, 짧은 이름(Ada, Pip…), 상태 알약(READY/RUNNING/NEEDS YOU/ON HOLD/PAUSED), 자동 승인 실행이면 AUTO 배지, 다시 시작·복제·닫기 |
| 그룹 | 팀을 둥근 프레임으로 감싸고(색 점·이름·개수·"N running"), 머리를 끌면 함께 이동, 접기. 노드·그룹 사이 점이 흐르는 곡선 연결선. 오케스트레이터 Connect 중에는 테두리 위 "Click to wire group" 알약 |
| 컴포저 | 팀 이름·역할 칩 8개·4열 CLI 타일(누르면 그 타일만 다른 CLI)·Fill all(아는 CLI 모두, 이 맥에 없는 것은 흐리게·안내만)·개수 → 역할 색 그룹으로 차례로 부팅. 프리셋은 콘솔과 함께 오케스트레이터·체크리스트도 놓을 수 있다 |
| 오케스트레이터 | Connect 로 그룹·콘솔을 연결, 상태 목록, 아래 입력으로 연결된 전부 또는 `@대상`에 한 번에 보내기 |
| 미션 맵 | 오케스트레이터 → 팀 → 콘솔 곡선 그래프, 상태 필터·검색, 오른쪽 기본 Fleet·Structure 두 카드, 고르면 상세(Go to·Pause·Kill·상태 시간·소속) |
| 이어하기 | 다시 열면 "Resume all conversations?" 토스트와 노드별 말풍선. Yes 면 claude `--resume`, codex `resume <id>` 로 차례로 이어 띄움. claude 세션 id 는 훅이 알려 준 실제 id 를 쓴다 |
| 루프 | 틀 카드 → 양식(타이머/조용해지면/출력 문구, 모든 콘솔/골라서, 횟수·시간·목표로 멈춤, 목표는 출력 문구·명령 성공·에이전트 판단) → 목록(카운트다운·지금 실행·토글) |
| 화이트보드 | 손글씨 제목 글자, 접힌 종이 스티키, 4열 칸반(카드 모달·끌어 옮기기), 체크리스트, 월 캘린더(일정 팝오버), 손그림 도형(사각·원·마름모·화살표), 펜(색 9+사용자·굵기 5, 부드러운 곡선)·지우개. 고르면 왼쪽 막대 옆에 속성 패널 |
| git 카드 | 파일마다 골라 커밋하고 이어서 push, 메시지 자동(또는 CLI 로 한 줄 생성), 최근 커밋·히스토리. 커밋 뒤에도 팝오버가 열린 채 결과를 보인다(Esc 로 닫기) |
| 웹 타일 | 탭·뒤로/앞으로/새로고침·주소줄, 빈 탭은 localhost 포트 칩과 빠른 열기, 모니터·휴대폰 해상도로 렌더해 타일에 맞춤, 옆 타일로 Elements·Console 인스펙터 |
| 사용량 | 위쪽 알약에 claude `/usage` 의 세션 % 링과 초기화 시각(없으면 로그로 짐작). 팝오버는 claude `/usage`·codex `/status` 의 한도 %, 로컬 세션 로그의 12개월 활동 칸·통계·30일 토큰 그래프·에이전트별 비율 |
| 스튜디오 | 보드 위 패널. 코드(줄 번호·구문 색 편집·저장·보드에 카드로), 마크다운(읽기·원문·힘 기반 링크 그래프·PDF), 문서(CLI 로 레포 문서 생성 → 흰 종이에 실시간 → PDF·보드 카드) |
| 다이어그램 | CLI 가 JSON 으로 낸 노드·간선·그룹을 보드 위에 손그림 도형·점선 그룹·라벨 화살표·손글씨 제목으로 차례로 그림. 시작 도형 4종 |
| 메모리 | 모달에서 레포 스캔(CLI 가 사실을 한 줄씩) → 검토 → 저장, 분류·적용 범위 편집, 보드 메모리 카드에서 골라 콘솔로 보내기 |
| 계정 | 머리에 CLI 아이콘 다섯(이 맥에 없는 것은 흐리게, 누르면 안내만). CLI 별 프로필(설정 폴더) 목록, Use 로 새 콘솔 기본 계정 지정, Connect 로 새 계정 콘솔 열어 로그인 |
| 명령 바 THREAD | `spawn 4 shell`, `add an orchestrator wired to group 1`, `put me preset 4`, `delete the group called group 1` 같은 보드 명령의 친 글·계획·결과가 명령 바 위 THREAD 카드에 쌓인다. 그룹 닫기는 그 안의 Confirm · N 으로 확인. 입력칸 옆 꺾쇠로 접고 편다 |
| 배치 | 새로 놓는 노드·카드가 그룹 프레임이나 다른 노드와 겹치면 가장 가까운 빈 자리로 민다(글·도형은 그대로). 웹 도구는 끌어서 크기를 정한다 |

## 구조

- `Sources/SymboardCore`: UI 없는 로직과 단위 테스트 대상. 모델·저장, 실행 계획(이어하기·훅 주입), 상태 판정, 명령 대상 해석, 루프 판정·요약, git·사용량·CLI 스트림 파싱, 마크다운·다이어그램 배치·힘 기반 배치.
- `Sources/Symboard`: AppKit 앱. `MainWindowController`(떠 있는 막대 배치), `BoardView`(캔버스·그룹 프레임·연결선·펜 층), `NodeView`(헤더), 각 노드 본문, 모달(미션 맵·루프·메모리), 스튜디오 패널, `AgentJob`(CLI 백그라운드 실행).
- `scripts/bundle.sh`: `.app` 번들. `scripts/drive.sh`: 자동 확인용 디버그 통로.

### 디버그 통로

`<상태 폴더>/debug/` 가 있으면 앱이 0.5초마다 `cmd.json` 을 읽어 명령을 실행하고 `result.txt` 에 결과를 쓴다. `scripts/drive.sh '<JSON 배열>' [상태 폴더]` 로 쓴다. 폴더가 없으면 아무 일도 하지 않는다.

## 기록

- 1차: `PLAN.md`, `REPORT.md`, 스크린샷 `docs/screens/`.
- 2차(원본과 같게 보이고 움직이게): `PLAN-2.md`(항목마다 비교한 원본 장면·스크린샷·남은 차이), `REPORT-2.md`, 스크린샷 `docs/screens/v2/`.
- 3~5차: `PLAN-3.md`~`PLAN-5.md`, `REPORT-3.md`~`REPORT-5.md`.
- 6차(영상별 작은 차이): `PLAN-6.md`, `REPORT-6.md`. 원본과 나란히 둔 그림은 `docs/screens/v6/compare/`(커밋하지 않음).
- 결정 기록: `DECISIONS.md`.
