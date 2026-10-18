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
- [ ] 2. board: 연결 중 그룹 테두리 위 "Click to wire group" 알약
- [ ] 3. node-git: 커밋 뒤 팝오버가 열린 채 결과를 보이게(키 창 문제를 다른 방법으로)
- [ ] 4. node-kanban: Today 를 누르면 날짜 입력으로, 일정 기본색
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
