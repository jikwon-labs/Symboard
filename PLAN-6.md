STATUS: IN_PROGRESS

# Symboard 6차 진행표

기준 커밋 `4594a2c` (5차 완료본). 5차 테스트 수 147.
모든 시험은 Finder 와 같은 환경으로 띄운 앱에서 한다:
`env -i HOME=$HOME USER=$USER LOGNAME=$USER SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin SYMBOARD_HOME=/tmp/symv6-N build/Symboard.app/Contents/MacOS/Symboard &`
확인은 `orca computer`(`scripts/input/ui.sh`) 실제 클릭·키 입력. 원본 대조 그림은 `docs/screens/v6/compare/`(커밋 안 함).

## 버전 확인

| 때 | codex | claude |
|----|-------|--------|
| 시작 | 0.157.1 | 2.1.302 |

## 실제 CLI 질문 수 (한도 10)

| # | 항목 | 대상 | 질문 |
|---|------|------|------|

합계: 0

## 고칠 것

- [x] 1. 새 노드 배치: 놓을 때 그룹 프레임·다른 노드와 겹치지 않게(원본 확인 먼저)
  - 원본 장면: `board.mp4` 1.5~5초(2장/초). 미리보기를 그룹 사이 빈 틈에 놓고, 커진 노드가 양쪽 그룹과 겹치지 않는다. 겹쳐 놓는 장면 없음 → 피하는 쪽으로 맞춤(DECISIONS 6차-1).
  - 바꾼 것: `CanvasLayout.obstacles`(팀은 그룹 프레임 하나, 나머지는 노드)·`nearestFree`(장애물 네 변에 붙인 x·y 후보 조합 중 가장 가까운 빈 자리) 를 Core 에 추가. `place()` 가 화면 안으로 맞춘 뒤 겹치면 밀고 `reveal`. 글·도형은 제외. 단위 테스트 5개.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-1): Open folder → /tmp/symsample → 명령 바 `spawn 4 shell` → `add an orchestrator wired to group 1` → 별 → Claude Code → 오케스트레이터 바로 아래 빈 곳(창 254,569) 클릭 → Dax 가 오케스트레이터 아래에 24pt 띄워 놓이고 그룹 프레임과 겹치지 않음. 비교 그림 `compare/1-placement.png`.
- [x] 2. board: 연결 중 그룹 테두리 위 "Click to wire group" 알약
  - 원본 장면: `board.mp4` 9~12초(4장/초). Connect 중 그룹 테두리가 주황 점선이 되고 윗변 가운데에 "⊕ Click to wire group" 알약. 누르면 실선 + 주황으로 채운 "Group wired" 알약.
  - 바꾼 것: `GroupFrameView.wireState`(none/offer/wired)와 `WirePillView`(접근성 단추). `layoutGroups` 가 Connect 중인 오케스트레이터와 이 팀의 연결 여부로 상태를 정하고, 알약을 누르면 `toggleWire`. Connect/Done·연결 바꿈 때 그룹을 다시 그린다. 안내 문구에 "a group's pill" 추가.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-1, 배율 60%): 오케스트레이터 Connect → 그룹 윗변 "Group wired"(이미 연결됨) → 알약 클릭(좌표) → 점선 + "Click to wire group", 오케스트레이터 "0 agents · 0 groups" → 다시 클릭 → "Group wired", "4 agents · 1 group" → Done. 비교 그림 `compare/2-wire-offer.png`, `2-wire-wired.png`.
  - 덧붙임: 첫 실행에서 배율 60% 의 오케스트레이터 Connect 를 좌표로 세 번 눌렀는데 반응이 없었다(접근성 누르기는 됨). 로그를 넣고 다시 띄운 뒤에는 60%·48%·버튼 줌·끌어 옮긴 뒤 모두 첫 클릭에 반응해 재현하지 못했다. 마지막 점검에서 다시 본다.
- [x] 3. node-git: 커밋 뒤 팝오버가 열린 채 결과를 보이게(키 창 문제를 다른 방법으로)
  - 원본 장면: `node-git.mp4` 7.5초. 커밋 뒤 팝오버가 열린 채 CHANGES "Working tree clean · Nothing to commit.", RECENT 맨 위에 새 커밋, 바닥 "Committed 5 files · pushed".
  - 4차에서 닫은 이유(PLAN-4 119줄): 남은 변경이 없으면 입력칸이 사라져, 팝오버 창이 초점 받을 곳 없는 키 창으로 남았고 orca 가 Esc·Cmd+Q 를 "초점 창 없음" 으로 거부했다.
  - 1차 시도(키 창만 본 창으로 돌림): AppKit 키 창은 본 창이 됐지만(`drive.sh windows`) orca 는 여전히 거부했다. 버림.
  - 바꾼 것: 팝오버를 닫지 않는다. 커밋 결과 줄이 생기고 작업 트리가 깨끗해지면 결과 줄이 SwiftUI 초점을 받는다(`focusable`·`focused`, 초점 테두리 없음). Esc 는 `onExitCommand` 로 팝오버를 닫는다. 본 창의 Esc 처리(`closeTopOverlay`)도 git 팝오버부터 닫는다. 쓰지 않게 된 `onCommitted` 를 지웠다.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-3, 로컬 bare 원격이 있는 /tmp/symgit6): Open folder → 브랜치 칩 → 입력칸에 "Add d and e" → Return → 팝오버가 열린 채 Working tree clean·RECENT "Add d and e 4 seconds ago"·"Committed 2 files · pushed"(원격 `366bd24`) → Esc(orca 가 받음) → 팝오버 닫힘 → 명령 바 클릭 → "echo after-commit" 타이핑이 들어감. 비교 그림 `compare/3-git-after-commit.png`.
- [x] 4. node-kanban: Today 를 누르면 날짜 입력으로, 일정 기본색
  - 원본 장면: `node-kanban.mp4` 6~9초(1장/초). NEW CARD 에서 Today/Tomorrow/Next week 칩 중 하나를 누르면 그 줄이 "02/09/2026" 날짜 칸과 ⊗ 지우기로 바뀐다. 20·31초 일정 창: 색 점 6개(호박·초록·파랑·보라·분홍·청록), 처음 고른 것은 첫 색(호박).
  - 바꾼 것: 칸반 카드 창의 날짜 줄이 날짜가 없으면 빠른 칩, 있으면 고칠 수 있는 날짜 칸(`DatePicker` field)과 지우기 단추가 된다. 테두리 상자로 묶었다. 캘린더 색을 원본 순서·색(영상에서 뽑은 값)으로 바꾸고 첫 색 호박이 기본.
  - 확인한 실제 입력(`env -i`, /tmp/symv6-3): 오른쪽 막대 Insert → Board → 캔버스 클릭 → Backlog Add card → "Research market trends" 타이핑 → Today 클릭 → 줄이 "10/18/2026" 칸 + ⊗ 로 바뀜 → ⊗ → 칩으로 돌아옴 → Today → Add card → 카드에 "Today". Insert → Calendar → 캔버스 클릭(보드 아래로 밀려 놓임, 1번 확인) → New → "Coordinate" → 첫 점(호박)에 고리 → Add event → 18일 칸에 호박색 막대. 비교 그림 `compare/4-kanban-date.png`, `4-calendar-color.png`.
- [ ] 5. node-memory: 목록 줄 켜짐 체크, 마우스 올리면 휴지통, 스캔 단계 Wrap up
- [ ] 6. node-loops: 목표 기본값을 원본과 같은 종류로
- [ ] 7. node-webtiles: 지구 도구 고른 뒤 끌어서 타일 크기
- [ ] 8. node-accounts: 팝오버 머리 CLI 아이콘, 없는 CLI 는 흐리게 + "설치되지 않음"
- [ ] 9. node-composer: Fill all 도 8번 규칙
- [ ] 10. studio-code: 저장 뒤 "Saved"
- [ ] 11. studio-diagrams: 화면 맞춤이 다이어그램만, 노드 고르면 노드 편집 패널
- [ ] 12. studio-documents: GENERATE PDF 누르면 작은 메뉴 먼저
- [ ] 13. studio-markdown: 카드 바닥 "Open in Studio · PDF" 글 단추
- [ ] 14. teams: 오른쪽 기본 패널 Fleet / Structure 두 카드
- [ ] 15. voice: 명령 바 보드 명령 THREAD 패널, 프리셋에 콘솔 말고 다른 노드도

## 마지막 점검

- [ ] 7단계 한 번에 통과

## 막힌 것

(없음)
