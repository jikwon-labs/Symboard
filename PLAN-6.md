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

- [ ] 1. 새 노드 배치: 놓을 때 그룹 프레임·다른 노드와 겹치지 않게(원본 확인 먼저)
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
