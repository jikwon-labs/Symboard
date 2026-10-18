STATUS: IN_PROGRESS

# Symboard 5차 진행표

기준 커밋 `f9bd7c1` (4차 완료본). 4차 테스트 수 119.
모든 시험은 Finder 와 같은 환경으로 띄운 앱에서 한다:
`env -i HOME=$HOME USER=$USER LOGNAME=$USER SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin SYMBOARD_HOME=/tmp/symv5-N build/Symboard.app/Contents/MacOS/Symboard &`
확인은 `orca computer` 실제 클릭·키 입력. 스크린샷은 `docs/screens/v5/`. 원본 대조 그림은 `docs/screens/v5/compare/`(커밋 안 함).

## 실제 CLI 질문 수 (한도 15)

| # | 항목 | 대상 | 질문 |
|---|------|------|------|
| 1 | 1번 문서 생성 | 문서 스튜디오 Quick(/tmp/symsample) | a 5-line README for this repo |
| 2 | 1번 루프 | 루프 Run now → Ada(/tmp/symsample) | reply with just the word ok, no tools |
| 3 | 4번 다이어그램 움직임 | 다이어그램 Components(/tmp/symsample) | (템플릿 질문) |
| 4 | V8 메모리 | Memory → Scan with Claude Code(/tmp/symsample) | (스캔 질문) |

합계: 4

## 고칠 것

- [x] 1. 더블클릭으로 띄우면 claude·codex 가 안 보인다 (로그인·대화형 셸 PATH 얻기)
  - 재현: `env -i ... PATH=/usr/bin:/bin:/usr/sbin:/sbin` 로 띄우면 별 메뉴에 Shell 만 있었다(감독 세션 확인).
  - 원인: 감지(`AgentCatalog.detect`)·`AgentJob`·루프 목표 명령이 `$SHELL -lc` 를 썼다. 로그인 셸은 `.zshrc` 를 읽지 않아 nvm 경로(`~/.nvm/versions/node/v24.17.0/bin`)가 없다.
  - 고침: `main.swift` 맨 앞에서 `LoginEnvironment.bootstrap()` 이 `$SHELL -l -i -c "printf 표식 $PATH 표식"` 을 한 번 돌린다(4초 제한, stderr 버림, 끝 표식이 보이면 셸이 안 끝나도 바로 읽음 — p10k gitstatus 데몬이 파이프를 잡고 있어도 기다리지 않는다). 표식 사이만 꺼내 `setenv("PATH")` 하므로 감지·AgentJob·루프·사용량 읽기·git·터미널 모두 물려받는다. 실패·시간 초과면 nvm 현재 버전(`alias/default`)·volta·asdf·mise·`~/.local/bin`·bun·pnpm·homebrew·`/usr/local/bin` 중 있는 곳을 앞에 더한다. 감지는 셸을 거치지 않고 PATH 를 직접 뒤진다(`LoginPath.which`). 이 머신에서 0.37초.
  - 같이 고친 것: 루프 목록 ▶(Run now)가 목표 판정 없이 바로 보냈다. 명령·에이전트 목표가 있으면 타이머 때처럼 먼저 판정한다.
  - 단위 테스트 12개(`V5Tests.swift`): 잡음 섞인 출력, 표식 두 번, 잘린·빈 출력, 합치기, 셸 성공, 실패·시간 초과 대체 경로, nvm 버전 고르기, which, 실제 셸 잡음, 표식 뒤 안 끝나는 셸, 멈춘 셸 시간 초과, 없는 셸.
  - 확인한 실제 입력(`env -i`, SYMBOARD_HOME=/tmp/symv5-1): 로그 `Symboard PATH (shell, 0.37s): /Users/jikwon/.nvm/...`. Open folder → Cmd+Shift+G `/tmp/symsample` → 별 → 메뉴에 Claude Code·Codex·Shell(`1-spawn-menu-envi.png`) → Claude Code → 캔버스 클릭 → Ada 신뢰 화면 NEEDS YOU(`1-claude-node-envi.png`) → ↓ Return → READY. 사용량 알약 클릭 → 4% used, 주간 20%(`1-usage-envi.png`). main 칩 → git 카드 변경 7개·Commit & Push(`1-git-envi.png`). 문서 스튜디오 → Quick → "a 5-line README for this repo" → 22초에 완성(`1-doc-generated-envi.png`). 루프 Start from scratch → "Path check" / "reply with just the word ok, no tools" → ▶ → Ada 에 보내져 답함(1 runs). 앱 다시 띄움 → 이어하기 토스트 Yes → 루프 Edit → 목표 명령 `command -v claude codex > /tmp/symv5-loopgoal.txt` → ▶ → "goal met", 파일에 nvm 의 claude·codex 경로(`1-loop-goal-envi.png`).
  - 대체 경로: `SHELL=/usr/bin/false` 로 띄우면 로그 `PATH (fallback, 0.01s): ~/.nvm/versions/node/v24.17.0/bin:~/.local/bin:~/Library/pnpm:/opt/homebrew/bin:...`.
- [x] 2. 사용량 알약과 팝오버의 시각이 다르다 (`/usage` 값 우선, 세션 % 함께)
  - 재현: 알약은 로그로 짐작한 5시간 묶음 끝("resets 10:00pm"), 팝오버는 `/usage` 의 "Resets 9:59pm" 이었다. `/usage` 는 팝오버를 열 때만 읽었다.
  - 원인: 알약(`UsageStore.resetText`)이 `/usage` 값을 보지 않았다.
  - 고침: `UsagePill.display`(Core) 가 `/usage` 의 세션 줄과 초기화 시각이 있고 그 시각이 아직 안 지났으면(`PlanUsageParser.resetDate` 로 "9:59pm (Asia/Seoul)" 을 실제 시각으로 바꿔 비교) "resets 9:59pm" 과 세션 % 를, 아니면 짐작값을 쓴다. 알약에는 원본처럼 작은 % 링(`SessionRing`)을 시계 아이콘 옆에 그린다. 앱 시작 3초 뒤와 5분마다 `/usage` 가 15분 넘게 묵었거나 초기화 시각이 지났으면 다시 읽는다(claude 가 깔렸을 때만, 질문 아님). 단위 테스트 5개.
  - 확인한 실제 입력(`env -i`, /tmp/symv5-1): 띄우고 20초 뒤 알약 "링 5 · resets 10pm". 알약 클릭 → 팝오버 "5% used · Resets 10pm (Asia/Seoul)" 로 같다(`2-pill-matches-usage.png`).
- [x] 3. codex 사용량 (X 탭)
  - 확인한 화면: codex 0.157.1 `/status` 상자 끝에 `Weekly limit: [████] 100% left (resets 5:34 PM on 25 Oct)`(Plus 요금제라 5h 줄은 없음). 질문 없이 읽힌다. 세션 로그(`~/.codex/sessions/**.jsonl`)의 `token_count` 에도 `rate_limits.primary{used_percent, window_minutes, resets_at}` 가 있지만 마지막 codex 응답 때 값이라 묵는다(로그는 24일 00:10, /status 는 25일 17:34).
  - 고침: `CodexStatusProbe` 가 화면 없는 터미널에 `codex --no-daemon` 을 띄워 `/status` 를 읽는다(`--no-daemon` 은 데몬 설정 메뉴를 피한다). 업데이트 안내는 Esc(건너뛰기) 한 번, Enter 는 입력칸에 `/status` 가 보일 때만 보낸다. 폴더 신뢰 화면이면 답하지 않고 그만두고 가장 최근 세션 로그의 `rate_limits` 를 보이며 이유를 적는다. `CodexLimitParser`(Core, 단위 테스트 3개)가 `% left` 를 used % 로 바꾼다. 팝오버 X 탭은 claude 탭과 같은 꼴: 큰 링(세션 한도가 없으면 첫 한도, 이름 "Weekly limit"), 나머지 한도 막대, 바닥 "codex · /status · local session logs".
  - 확인한 실제 입력(`env -i`): /tmp/symsample(codex 가 신뢰 안 한 폴더) → 알약 → X → "Weekly limit 0% · Resets 12:10 AM on 24 Oct · codex is asking a question in this folder… · showing the last session log"(`3-codex-tab-log-fallback.png`). Home → Open folder `/tmp/symtrust-5`(4차에서 신뢰한 폴더) → 알약 → X → "Weekly limit 0% used · Resets 5:38 PM on 25 Oct", 바닥 "codex · /status"(`3-codex-tab-status.png`). 끝난 뒤 codex 프로세스 남지 않음, `codex --version` 0.157.1 그대로.
  - **사고 기록**: 처음 화면을 살피려고 파이썬 pty 로 codex 를 띄워 `/status` + Enter 를 보냈는데, 그때 화면이 업데이트 메뉴(기본값 "1. Update now")여서 Enter 가 `npm install -g @openai/codex` 를 돌려 0.157.1 → 0.163.0 으로 올라갔다(전역 설치 금지 위반). 바로 `npm install -g @openai/codex@0.157.1` 로 원래 버전으로 되돌렸다. 앱의 탐침은 이 때문에 업데이트 메뉴에서 Enter 를 절대 보내지 않게 만들었다. `~/.codex/config.toml` 은 건드리지 않았다(신뢰 화면에서 그만둠).
- [x] 4. 움직임 (스튜디오 → 카드 줄어들기, 다이어그램 노드 미끄러지기, 노드 추가·닫기, 팝오버)
  - 원본(1초 4장·8장으로 뽑음): `studio-documents.mp4` 19초 Add to board → 스튜디오가 0.25초 안에 카드 자리로 줄어든다. `studio-diagrams.mp4` 2~6초: 노드가 제목 아래 한 줄로 먼저 생기고, 그래프 꼴로 자리를 옮긴 뒤 화면이 부드럽게 맞춰진다. `board.mp4` 1초: 놓기 미리보기(점선 상자) → 클릭하면 노드가 작게(약 60%) 나타나 0.2초 안에 커진다. 팝오버는 시스템 기본 움직임.
  - 원인: 카드·노드는 모델이 바뀌면 바로 그 자리에 생기고 사라졌다. 다이어그램 노드는 처음부터 최종 자리에 놓였다. 화면 맞춤(`zoomToFit`)은 한 번에 건너뛰었다.
  - 고침: `collapseStudio`(스튜디오 패널을 찍은 그림을 새 카드 자리로 0.28초에 옮긴 뒤 카드를 보임) — Add to Board·Insert·닫을 때 파일 카드·문서 카드에 씀. `NodeMotion.appear`(층 변환으로 가운데 기준 60%→100%, 투명→불투명 0.2초)·`disappear`(92%·투명 0.15초, 그동안 클릭 안 받음) — 처음 불러올 때는 쓰지 않는다. frame 이 아니라 층 변환이라 터미널 크기가 흔들리지 않는다. 다이어그램 노드는 제목 아래 6개씩 한 줄 자리에서 최종 자리로 0.45초에 미끄러진다(`CanvasView.slideNode`, 그동안 모델 맞추기가 frame 을 덮지 않음). `zoomToFit` 은 0.35초 동안 배율(로그 눈금)과 가운데를 옮긴다(`glide`).
  - 확인한 실제 입력(`env -i`, 화면 녹화 `screencapture -v` 를 20장/초로 뽑음): README 카드 X → 0.15초에 흐려지며 작아짐(`4-node-close-20fps.png`). Markdown 스튜디오 → Add to Board → 패널이 카드 자리로 줄어듦(`4-studio-collapse-20fps.png`). 별 → Shell → 캔버스 클릭 → 점선 미리보기 → 작게 나타나 커짐(`4-node-appear-20fps.png`). 다이어그램 → Components(질문 3) → 노드가 한 줄에서 자리로 미끄러지고 화면이 맞춰짐(`4-diagram-slide-8fps.png`).
  - 남은 것: 다이어그램이 화면 가운데에 그려져 기존 카드 위에 겹친다(원본은 빈 캔버스). V13 에서 다룬다.
- [x] 5. 앱 아이콘과 Dock (번들 아이콘, Dock·Cmd+Tab, 창 닫은 뒤 Dock 클릭으로 다시 열기)
  - 재현: `Resources/AppIcon.icns` 가 없어 번들에 아이콘이 없었다(`bundle.sh` 는 있으면 넣게만 돼 있었다). 창을 닫으면 앱이 끝났다(`applicationShouldTerminateAfterLastWindowClosed` true) — 콘솔도 같이 죽는다.
  - 고침: `scripts/icon/make-icon.swift` 로 직접 그린 아이콘(점 격자 보드 위 이어진 카드 세 장, 하나는 강조색, 반짝임)을 `Resources/AppIcon.icns` 로 만들었다. 창을 닫아도 앱·콘솔은 돌고(`isReleasedWhenClosed = false`), `applicationShouldHandleReopen` 이 창을 다시 연다. DECISIONS.md 에 적음.
  - 확인한 입력(`env -i`): 번들 `Contents/Resources/AppIcon.icns`, Info.plist `CFBundleIconFile=AppIcon`. 띄운 뒤 화면 캡처에 Dock 아이콘과 실행 점(`5-dock-icon.png`). Cmd+W → 창 0개, 프로세스(pid 62578) 그대로 → 다시 열기 → 같은 pid 로 창이 돌아오고 "2 live" 콘솔 그대로(`5-reopened-after-close.png`). `lsappinfo` 종류 Foreground(Cmd+Tab 에 나오는 종류).
  - 한계: orca 는 Dock(다른 앱)을 누를 수 없고 CGEvent 도구는 손쉬운 사용 권한이 없어, Dock 클릭은 같은 "다시 열기" Apple Event 를 보내는 `open build/Symboard.app` 로 대신했다. Cmd+Tab 전환기 화면은 키를 누른 채 찍을 방법이 없어 눈으로는 못 봤다. README 의 "직접 눌러 볼 순서" 에 넣는다.

## 많이 띄우기

- [x] 6. 셸 24 + claude 4, 그룹 4개, `@all` 대량 출력, CPU·메모리 60초, 끌기·확대·타이핑, 미션 맵 28개·검색·필터, 10분 방치 메모리, Cmd+Q 후 복원·이어하기 토스트
  - 띄운 것(`env -i`, SYMBOARD_HOME=/tmp/symv5-6, 폴더 /tmp/symsample): 아래 Group → 컴포저 4번. Frontend 8(Fill all 셸 → + 네 번 → 윗줄 타일 4개를 눌러 Claude), Backend 7, Testers 7, Reviewers 6(모두 셸). "28 live". claude 4개는 띄우기만 했다(질문 0).
  - 대량 출력: `@all` 은 claude 4개에도 글을 보내 질문이 되므로, 셸 24개만 겨눴다: `@backend @testers @reviewers @dax @rafa @kai @zoe for i in $(seq 1 3000); do echo line $i; done`(명령 바에 실제 타이핑).
  - 반응 재기: 메인 스레드 지연 감시(`SYMBOARD_LAGLOG=1`, 0.1초마다 메인 큐에 일을 넣고 실제로 돌기까지 걸린 시간 → 5초마다 p50·p95·최대) 를 새로 넣었다. 출력 중 캔버스 끌기 3번·스크롤 2번·명령 바 타이핑을 orca 로 보냈고, 동작마다 왕복 0.39~0.44초(출력이 없을 때와 같은 orca 자체 시간), 친 글자가 바로 보였다(`6-` 화면은 아래).
  - 찾은 문제 1(고침): **읽기 작업 누수**. `heap` 으로 보니 출력할수록 `OS_dispatch_operation`·직렬 큐가 늘기만 했다(8만 8천 → 14만 6천, 약 65MB). SwiftTerm `LocalProcess.childProcessRead` 가 같은 읽기가 끝나기 전 조각(`done == false`)마다 새 `io.read` 를 걸어 끝나지 않은 작업이 쌓였다. SwiftTerm 1.11.2 를 `Vendor/SwiftTerm` 으로 옮기고 끝났을 때만 다시 걸게 고쳤다(`PATCHES.md`). 고친 뒤 5번 쏟아도 28개 그대로.
  - 찾은 문제 2(고침): **5분마다 사용량 로그 905개를 다시 읽음**(CPU 16%, 메모리 튐). 파일별 결과를 (수정 시각, 크기)로 기억해 바뀐 파일만 읽는다(`UsageFileCache`, 단위 테스트 2개). 다시 훑기 15.5초 → 0.2초.
  - 남은 것(원인만 확인): 쏟아지는 동안 `Malloc Small (empty)` — 터미널 줄 객체를 만들고 지운 빈 쪽 — 이 물리 메모리로 잡혀 있다가 몇 분 뒤 운영체제가 거둬 간다. 살아 있는 heap 은 100~180MB 로 일정하다. `malloc_zone_pressure_relief` 로 당겨 보려 했으나 이 macOS 에서 0바이트를 돌려줘서 빼고, 10분 방치에서 내려오는 것을 확인했다.
  - 수치(ps `%cpu`·`rss` 는 공유 쪽을 포함해 크게 나온다. 물리 사용량은 vmmap "Physical footprint"):

    | 측정 | 고치기 전 | 고친 뒤 |
    |---|---|---|
    | 28개 가만히(60초) | CPU 평균 2.7%, RSS 391MB, footprint 약 300MB | CPU 0.0~0.3%, RSS 391MB, footprint 292~296MB |
    | 한 번 쏟을 때(셸 24 × 3000줄) | 끝나는 데 약 2초, CPU 최대 135%, RSS 391 → 832MB | CPU 최대 124%, footprint 296 → 738~795MB |
    | 다섯 번 연달아 | RSS 832 → 1240 → 1590MB(셋째까지), 읽기 작업 8.8만 → 14.6만 | 읽기 작업 28 그대로, footprint 최대 1.9GB 뒤 1.5GB |
    | 메인 스레드 지연(5초 묶음, 쏟는 동안 최악) | p95 5.8ms, 최대 46.8ms | p95 15.3ms, 최대 36.5ms |
    | 다 끝나고 10분 방치(30초 간격 footprint) | — | 753 → 753(4분) → 631·646 → 292(5분 반) → 292 → 466MB(9분, 5분 주기 사용량 훑기) — 계속 늘지 않음 |
    | 사용량 로그 다시 훑기 | 15.5초 | 0.2초 |

  - 미션 맵: 도구 메뉴 → Mission Map → "0 orchestrators · 4 teams · 28 consoles", Idle 28(`6-mission-28.png`). 검색 "rev" → Reviewers 6개만(`6-mission-search.png`). Working 칩 → 0개.
  - 복원: Cmd+Q → 다시 띄움 → 28개 그대로, 셸 24개 바로 live, 토스트 "Resume all conversations? 4 consoles can pick up their last chat"(claude 4개만, `6-restore-toast-4.png`) → Yes → 28 live. 이 시험에서 다섯 번 다시 띄우며 매번 같았다.

## 영상 따라 하기

- [x] V1. board.mp4
  - 원본 조작: 별 → SPAWN AGENT 목록(Claude ✓ …) → 캔버스 클릭 → "Maya 2" 부팅 → 오른쪽 막대 셋째(꽃 모양) → 그 콘솔 아래 Orchestrator(이미 "1 agent", 선 연결) → Connect → GROUPS/CONSOLES 행 클릭(주황 채움, 보드에 선) → 그룹 테두리 위 "Click to wire group" 알약 → Done → 목록(콘솔·팀별 행, 상태 알약) → 아래 입력 "give them basic instructio…" 타이핑.
  - 우리(`env -i`, /tmp/symv5-6 28개 보드): 별 → Claude Code → 캔버스 클릭(Dax2) → Dax2 고른 채 오른쪽 막대 셋째 → Orchestrator → Connect → Backend·Testers·Dax2 → 주황 행·선(`compare/video-board.png` 위) → Done → "15 agents · 2 groups" 목록 → 입력에 같은 글 타이핑(보내지 않음, 아래).
  - 쓰는 데 지장 있는 차이(고침): ① 오른쪽 막대 셋째가 원본은 오케스트레이터, 우리는 아무것도 안 하는 Settings(알림만) → 오케스트레이터를 바로 놓는 단추(고른 노드 아래)로, 코드 스튜디오 아이콘도 원본처럼 폴더로. ② 고른 콘솔에서 만들면 원본은 그 콘솔이 처음부터 연결("1 agent") → 같게.
  - 모양 차이(남김): 원본은 연결 중 각 그룹 테두리 위에 "Click to wire group" 알약이 떠서 보드에서 그룹을 바로 잇는다(우리는 목록 행으로 같은 일). 머리의 "0/21"(원본은 일하는 수 / 전체로 보임, 우리는 준비된 수 / 전체). 목록 행에 마우스를 올리면 원본은 ⛶·❚❚ 아이콘.
- [x] V2. node-accounts.mp4
  - 원본 조작: 위쪽 계정 팝오버(열린 채 시작) → CONNECT ANOTHER ACCOUNT 칸 클릭 → "5 Account Claude Code" 타이핑 → + Connect → 팝오버 닫히고 가운데에 고른 상태의 새 claude 콘솔 "Ada 3"(머리에 "5A" 계정 칩), live 32 → 33.
  - 우리(`env -i`): 위쪽 사람 아이콘 → 팝오버(경고·Your sign-in ACTIVE·Save current sign-in·CONNECT ANOTHER ACCOUNT, 칸에 이미 초점) → 같은 글 타이핑 → Connect → 새 claude 콘솔(자기 설정 폴더, 첫 실행 화면이라 NEEDS YOU), live 29 → 30.
  - 쓰는 데 지장 있는 차이: 없음.
  - 모양 차이(고침): 다른 계정으로 띄운 콘솔인지 머리에서 알 수 없었다 → 원본처럼 계정 머리글자 칩("5A")을 CLI 배지 옆에(`AccountProfile.initials`, 단위 테스트 1개, `v2-account-chip.png`).
  - 모양 차이(남김): 원본 팝오버 머리의 CLI 아이콘 다섯 개(우리는 claude·codex 둘), 프로필 카드의 Use·터미널·연필·× 줄은 우리도 있으나 이 상태 폴더엔 저장된 프로필이 없어 비교 못 함.
- [x] V3. node-composer.mp4
  - 원본 조작: Group 칩 → 컴포저(Team, 6 Claude) → + 로 12 → 셋째 줄 타일 넷을 눌러 Codex → Testers → Backend(Spawn 단추 색이 역할 색) → Spawn 12 → "BACKEND 12" 4×3 그룹, Claude 8 + Codex 4 가 부팅해 입력창.
  - 우리(`env -i`, 새 작업공간 탭): 같은 순서(Group → + 여덟 번 → 셋째 줄 넷 → Testers → Backend → Spawn 12). 컴포저 모양·타일 색·단추 색이 원본과 같다(`compare/video-node-composer.png` 위). 4×3 "BACKEND" 그룹, Claude 8 READY(`v3-backend-12.png`).
  - 쓰는 데 지장 있는 차이(고침): Codex 4개가 "Background server has incompatible feature settings" 메뉴에서 멈췄다(이 맥에서 다른 codex 화면이 띄운 공용 데몬과 설정이 다름). 콘솔 codex 를 `--no-daemon` 으로 띄운다(사용자가 인자로 데몬을 고르면 그대로, 단위 테스트 1개 + 기존 2개 고침, DECISIONS.md). 고친 뒤 메뉴 없이 codex 자체 화면으로 간다.
  - 남은 것(사용자 결정이라 둠): codex 의 "Update available" 화면(Enter 기본값이 전역 업데이트)과 /tmp/symsample 폴더 신뢰 화면. 둘 다 NEEDS YOU 로 잘 보이고, 답하면 ~/.codex 를 바꾸거나 전역 설치가 되므로 시험에서는 답하지 않았다(Esc 로 업데이트 건너뛰기만 확인, codex 0.157.1 그대로).
  - 쓰는 데 지장 있는 차이(고침, 따라 하다 찾음): 다시 켜면 지금 보이는 탭의 콘솔만 돌고 다른 탭 콘솔은 그 탭을 열어야 떴다(live 12, Main 의 셸 24개 꺼짐). 켤 때 모든 작업공간의 콘솔을 띄운다. 확인: Workspace 2 가 보이는 채 Cmd+Q → 다시 띄움 → "28 live", 토스트 "14 consoles"(두 탭의 claude 전부).
  - 모양 차이: 원본 Fill all 줄의 CLI 아이콘 열두 개(우리는 이 맥에 깔린 것만: Claude·Codex·Shell). 원본 그룹 머리 "12 running", 우리는 "4 need you"(상태가 다름).
- [x] V4. node-git.mp4
  - 원본 조작: 아래 왼쪽 "main 5" → git 팝오버(Reading changes… → Commit & Push 5 files) → 시계(히스토리) → 다시 변경 → 메시지 칸 "bugfix/payment-gateway-timeout" → Commit & Push → Committing… → Pushing… → "Working tree clean", "Committed 5 files · pushed", 칩 "main".
  - 우리(`env -i`, /tmp/symsample, 원격 없음): main 칩 → 같은 꼴 팝오버(저장소·브랜치·synced, 시계·열기·새로고침·닫기, CHANGES 7/7 +25 −3, 파일별 체크·M/U, 메시지 칸 + 반짝임, Commit & Push 7 files, RECENT) → 시계 → 같은 메시지 타이핑 → 커밋 3d24c97, 칩 "main"(배지 없음).
  - 쓰는 데 지장 있는 차이(고침): 칩 숫자(4)와 팝오버 변경 수(7)가 달랐다 — 칩은 추적 안 된 폴더를 한 줄로 셌다. 칩도 `-uall` 로 파일마다 센다. 확인: 새 폴더에 파일 둘 → 다시 띄움 → "main 2"(`v4-chip-count.png`).
  - 모양 차이(남김): 커밋 뒤 원본은 팝오버가 열린 채 "Working tree clean · Committed · pushed" 를 보이고, 우리는 4차에서 닫고 알림으로 보인다(입력칸이 사라진 팝오버가 키 창으로 남아 Esc·Cmd+Q 가 먹지 않던 문제 때문, REPORT-4). 시계를 눌렀을 때 히스토리로 바뀌는 것은 0.8초 캡처에서 보이지 않았다(2차에서 확인된 기능, 이번엔 다시 보지 않음).
- [x] V5. node-ink.mp4
  - 원본 조작: 펜 도구(COLOR 9칸 + 사용자 색, WIDTH 5단계) → 사진 위 배 둘레 빨간 타원 → 산 둘레 타원에서 사진 밖으로 긴 곡선 → 화살촉 → 손글씨 "60".
  - 우리(`env -i`, 새 탭 Workspace 3): 왼쪽 그림 도구 → 열기 창 Cmd+Shift+G `/tmp/symsample/sample-image.png` → 그림 노드 → 펜(같은 COLOR·WIDTH 패널) → 빨강 → orca 끌기로 그림 위 사각 둘레, 그림 밖으로 꺾인 선, 화살촉(`v5-ink.png`). 획이 끌면서 바로 그려지고 그림 밖 캔버스에도 그려진다.
  - 쓰는 데 지장 있는 차이: 없음.
  - 모양 차이: orca 끌기는 직선만 보내 원본 같은 둥근 타원·손글씨는 시험 도구로 못 그렸다(펜이 곡선을 부드럽게 잇는 것은 2차에서 확인). 그림이 골라진 채 펜을 고르면 그림 속성 패널이 펜 패널 아래에 잠깐 겹쳐 보이다가 첫 획에서 사라진다(원본은 펜 패널만).
- [x] V6. node-kanban.mp4
  - 원본 조작: 칸반 TO DO "+ Add card" → NEW CARD(제목·메모·Today/Tomorrow/Next week·None/Low/Med/High) → "Research market trends" → Today → Low → Add card → IN PROGRESS → DONE 로 끌기 → 오른쪽 막대 둘째 INSERT TO-DO → Checklist → Calendar → + New → 날짜·파랑·메모·"Coordinate" → Add event → 일정을 12일로 끌기 → 일정 눌러 고치기 → 왼쪽 도형 → Sticky → 놓자마자 "Prepare some things about the app." → Arrow·Rectangle·"ROI %".
  - 우리(`env -i`, Workspace 3): 오른쪽 막대 둘째 → Board → TO DO Add card → 같은 대화상자, 같은 글 → Today → Low → Add card(초록 막대·Today·Low) → IN PROGRESS → DONE 끌기(DONE 1). Calendar → + New → "Coordinate" → 파랑 → Add event(18일) → 24일로 끌기. 도형 → Sticky → 클릭 → 바로 타이핑(`v6-sticky-typed.png`).
  - 쓰는 데 지장 있는 차이(고침): ① 캘린더 일정을 다른 날로 끌 수 없었다 → 일정 끌기(놓을 칸 강조, 시각 유지). ② 스티커를 놓은 뒤 글을 바로 칠 수 없었다(두 번 눌러야 편집) → 놓자마자 편집 상태. ③ 도형 메뉴에 Sticky 가 없었다(Insert 에만) → 원본처럼 도형 메뉴에도.
  - 모양 차이(남김): 원본 날짜 칸은 Today 를 누르면 날짜 입력으로 바뀌고 dd/mm/yyyy, 우리는 칩 그대로. 원본 일정 기본색은 노랑, 우리는 주황. 스티커 PAPER 패널이 새 스티커를 가린다(원본도 왼쪽 패널이지만 스티커가 화면 가운데라 겹치지 않음).
- [x] V7. node-loops.mp4
  - 원본 조작: Loops(빈 상태 틀 카드) → Start from scratch → NAME "Test watchdog" → INSTRUCTION 붙여넣기 → 기본값(On a schedule, 15 min, All consoles) → 스크롤 → When a goal is met → An agent judges(Claude) → "ALL GREEN" → Keep running behind other tabs → Create loop → 목록 한 줄, 카운트다운 in 15:00 → 14:56, 오른쪽 막대 루프 아이콘에 빨간 1.
  - 우리(`env -i`, Workspace 3): 오른쪽 막대 맨 아래 → 같은 틀 카드 화면 → Start from scratch → 같은 이름·지시 → 스크롤 → When a goal is met → (An agent judges·Claude 가 기본) → "ALL GREEN" → 바닥 요약 "…until Claude judges the goal met." → Create loop → 목록 한 줄 "in 14:59"·▶·토글·…, 루프 아이콘 빨간 1(`v7-loop-list.png`). 질문을 보내지 않으려고 끄고 지웠다.
  - 쓰는 데 지장 있는 차이: 없음.
  - 모양 차이: 틀 카드 이름·설명 글이 원본과 다르다(원본 문구를 옮기지 않으려고 2차에서 바꿈). 원본 목표 기본은 "A command passes", 우리는 "An agent judges". 원본 BEHAVIOR 토글 기본 꺼짐, 우리는 켜짐.
- [x] V8. node-memory.mp4
  - 원본 조작: Memory 칩 → 빈 상태 → Scan repo → CLI 고르기(Claude…) → Scan with Claude → 단계(Launch·Read the repo·Write facts·Wrap up)와 사실이 하나씩 → REVIEW PROPOSALS 12 of 12 → Add 12 to memory → 목록(탭 "Votelanding 12 / All repos 0") → 연필 → EDIT MEMORY(분류 칩·제목·Refresh·본문·APPLIES TO·Delete·Cancel·Save memory).
  - 우리(`env -i`, 질문 4): Memory 칩 → 같은 빈 상태 → Scan repo → Claude Code·Codex → Scan with Claude Code → 단계 표시·빈 줄 → 약 40초 뒤 REVIEW PROPOSALS 9 of 9(분류 색·제목·본문·연필, `v8-memory-review.png`) → Add 9 to memory → 목록 → 연필 → EDIT MEMORY(같은 칸들, Rewrite) → Cancel.
  - 쓰는 데 지장 있는 차이(고침): 위 탭 "All repos" 가 모든 레포의 모든 메모리를 세고 보였다(이 레포 9 / All repos 9). 원본은 적용 범위로 나눠 "All repos" 는 모든 레포에 적용되는 것만(0). 같게 고쳤다(목록에서 이 레포 것과 전역 것을 나눠 봄). 확인: 다시 띄워 "All repos 0".
  - 모양 차이(남김): 원본 목록 줄 오른쪽의 켜짐 체크(활성)와 마우스를 올리면 나오는 휴지통(우리는 편집 화면의 Delete), 바닥의 "12 active entries" 문구. 원본 CLI 칩 다섯 개(우리는 깔린 것만). 우리 단계는 Wrap up 이 없다.
- [x] V9. node-resume.mp4
  - 원본 조작: 다시 켠 보드, claude 타일마다 "Resume last conversation?" 칩, 오른쪽 위 토스트 "Resume all conversations? 9 consoles…" → Otto 칩 → 그 타일만 WORKING → 지난 대화 → 토스트 "8 consoles" → Yes → 나머지가 차례로 이어짐.
  - 우리(`env -i`, Workspace 2 를 연 채 Cmd+Q → 다시 띄움): 타일마다 같은 칩(ON HOLD), 토스트 "14 consoles"(`v9-resume-toast.png`) → Iris 칩 Yes → Iris 만 뜸, 토스트 "13 consoles" → 토스트 Yes → 13개가 차례로 떠서 42 live.
  - 쓰는 데 지장 있는 차이: 없음.
  - 모양 차이: 이 콘솔들은 질문을 한 적이 없어 이을 대화가 없으므로 claude 첫 화면이 뜬다(원본은 지난 대화). 대화가 있는 콘솔의 이어하기는 3·4차에서 확인. 원본은 이어지는 동안 "Claude lane restored — relaunching." 두 줄을 보이고, 우리는 "Restored — picking up the last conversation..." 한 줄.
- [x] V10. node-usage.mp4
  - 원본 조작: 알약 "resets 4:09am" 아래 팝오버(claude: 14% 링·주간 줄·활동 칸·통계) → Codex 아이콘 → codex 화면(Monthly limit 27%), 알약도 codex 초기화 시각으로 → Claude → 아래로 스크롤(LAST 24H) → 막대 아이콘 → tokens(Reading local session logs → 30일 막대·BY AGENT).
  - 우리(`env -i`): 알약 → 같은 꼴 팝오버(16% · Resets 10pm, 주간 22% · 0%, 7일, 활동 칸, 통계, LAST 30D, `v10-usage-claude.png`) → X → codex(Weekly limit 0%, 마지막 세션 로그) → Claude → tokens(7.4B, 30일 막대, BY AGENT).
  - 쓰는 데 지장 있는 차이(고침): 팝오버에서 codex 를 골라도 위 알약이 claude 그대로였다 → 원본처럼 알약도 codex 한도·초기화 시각과 보라 링으로, 팝오버를 닫으면 claude 로 돌아간다. 확인: X → 알약 "0 · resets 12:10 am on 24 Oct", C → "16 · resets 10pm".
  - 시험 도구 한계: 팝오버 머리의 막대 아이콘은 orca 좌표·접근성 어느 쪽으로도 눌리지 않아(팝오버가 별도 창이고 접근성 트리에 안 나옴) tokens 쪽은 디버그 `usage page=tokens` 로 열고 화면만 확인했다. C/X 아이콘은 실제 클릭으로 눌렸다.
  - 모양 차이: 원본은 CLI 다섯 아이콘, 우리는 둘. 원본 LAST 24H, 우리 LAST 30D.
- [x] V11. node-webtiles.mp4
  - 원본 조작: 지구 도구로 사각형 끌기 → Web 타일("Open a page": LOCALHOST 포트 칩, QUICK OPEN) → :3000 → 페이지(타일 머리·탭이 페이지 제목) → 모니터 아이콘 → 24 in monitor → 타일이 16:9 로 커지고 "24 in monitor"·"1920 × 1080" 빨간 표시 → {} → 옆에 Inspector 타일(연결선).
  - 우리(`env -i`, /tmp/symv5-web 을 python http.server :3000 으로 띄움): 지구 → 캔버스 클릭 → 같은 시작 화면 → :3000 → 페이지 → 모니터 → 24" 4K → 빨간 "24\" 4K · 1920 × 1080", 1920 폭으로 렌더 → 벌레 아이콘 → Inspector 타일(Elements·Console, DOM 트리).
  - 쓰는 데 지장 있는 차이(고침): ① 화면 크기를 골라도 타일 크기는 그대로라 페이지가 위아래 검은 띠 안에 작게 보였다 → 원본처럼 타일을 그 비율로(가로형은 폭 유지·높이 맞춤, 폰은 높이 유지·폭 맞춤). ② 타일 머리가 늘 "Web", 탭은 주소였다 → 페이지 제목(didFinish 뒤 늦게 오는 제목도 한 번 더 읽음). 확인 `v11-web-24in.png`.
  - 모양 차이(남김): 원본은 지구 도구로 끌어 크기를 정하고, 우리는 클릭해 기본 크기로 놓는다. 원본 인스펙터는 Styles·Computed·Box Model 이 있는 DevTools 꼴, 우리는 Elements·Console(공개 API 한계, 2차 DECISIONS). 원본 모니터 메뉴의 휴대폰 다섯 종, 우리는 셋(Phone·Phone Max·Tablet).
- [x] V12. studio-code.mp4
  - 원본 조작: 오른쪽 막대 폴더 아이콘 → Code 스튜디오(왼쪽 파일 나무, README.md 열림) → 폴더 여러 개 펼침 → src/app/submit/page.tsx → 문자열 끝에 글 더함("• Edited") → Save("✓ Saved") → Insert → 보드에 page.tsx 코드 카드.
  - 우리(`env -i`): 폴더 아이콘 → Code 스튜디오 → src 펼침 → hello.py(경로·PY·8 lines) → 3줄 끝에 " Edited in the studio." 타이핑("• Edited") → Save(디스크에 저장 확인) → Insert → 패널이 카드로 줄어들며 hello.py 카드(chip "main 1"). 끝나고 `git checkout` 으로 되돌림.
  - 쓰는 데 지장 있는 차이: 없음.
  - 모양 차이(고침): 처음 열면 원본은 README.md, 우리는 빈 편집기("Pick a file on the left") → README 를 먼저 연다(`v12-code-readme.png`).
  - 모양 차이(남김): 원본은 저장 뒤 단추가 "✓ Saved" 로 바뀐다(우리는 "Edited" 표시만 사라짐).
- [ ] V13. studio-diagrams.mp4
- [ ] V14. studio-documents.mp4
- [ ] V15. studio-markdown.mp4
- [ ] V16. teams.mp4
- [ ] V17. voice.mp4

## 막힌 것

(없음)
