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

합계: 2

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
- [ ] 3. codex 사용량 (X 탭)
- [ ] 4. 움직임 (스튜디오 → 카드 줄어들기, 다이어그램 노드 미끄러지기, 노드 추가·닫기, 팝오버)
- [ ] 5. 앱 아이콘과 Dock (번들 아이콘, Dock·Cmd+Tab, 창 닫은 뒤 Dock 클릭으로 다시 열기)

## 많이 띄우기

- [ ] 6. 셸 24 + claude 4, 그룹 4개, `@all` 대량 출력, CPU·메모리 60초, 끌기·확대·타이핑, 미션 맵 28개·검색·필터, 10분 방치 메모리, Cmd+Q 후 복원·이어하기 토스트

## 영상 따라 하기

- [ ] V1. board.mp4
- [ ] V2. node-accounts.mp4
- [ ] V3. node-composer.mp4
- [ ] V4. node-git.mp4
- [ ] V5. node-ink.mp4
- [ ] V6. node-kanban.mp4
- [ ] V7. node-loops.mp4
- [ ] V8. node-memory.mp4
- [ ] V9. node-resume.mp4
- [ ] V10. node-usage.mp4
- [ ] V11. node-webtiles.mp4
- [ ] V12. studio-code.mp4
- [ ] V13. studio-diagrams.mp4
- [ ] V14. studio-documents.mp4
- [ ] V15. studio-markdown.mp4
- [ ] V16. teams.mp4
- [ ] V17. voice.mp4

## 막힌 것

(없음)
