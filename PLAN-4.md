STATUS: IN_PROGRESS

# Symboard 4차 진행표

기준 커밋 `4a73437` (3차 완료본). 3차 테스트 수 92.
확인은 `orca computer` 실제 클릭·키 입력(`scripts/input/ui.sh`)으로 한다. `scripts/drive.sh` 는 상태를 깔아 두는 데만 쓴다.
스크린샷은 `docs/screens/v4/<항목번호>-<이름>.png`. 체크한 항목 아래에 "재현 / 원인 / 확인한 실제 입력" 을 적는다.

## 실제 CLI 질문 수 (한도 12)

| # | 항목 | 대상 | 질문 |
|---|------|------|------|

합계: 0

## 고칠 것

- [x] 1. 사용자 답을 기다리는 claude(신뢰 확인 화면)가 READY 로 보임 → 화면 끝 글자로 Needs you. codex 승인 화면도.
  - 재현: 새 `/tmp/symtrust-3` 에서 별 → Claude Code → 캔버스 클릭. "Quick safety check ... Enter to confirm · Esc to cancel" 화면에서 알약 READY, 미션 맵 Idle. codex 를 띄우면 신뢰 확인 전에 "Background server has incompatible feature settings"(번호 메뉴, 안내 줄 없음)와 "Update available"(enter continue · esc skip) 화면이 먼저 나온다.
  - 원인: 상태는 훅 신호나 출력 시각으로만 판정했다. 이 화면들은 훅이 돌기 전이라 신호가 없고, 출력이 멈추면 Idle 로 봤다. 또 화면 글자를 읽어 보니 한 번도 쓰지 않은 칸이 NUL 로 나와 낱말 사이가 공백이 아니었다.
  - 고침: `PromptDetector`(Core) 가 화면 끝 18줄에서 "고르는 표시(❯ ›) + 안내 줄(Enter to confirm, esc quit 등)" 또는 "고르는 표시가 번호 선택지 위" 를 찾으면 `.waiting`. 1초 판정(`StatusTracker.resolve`)이 훅·출력 판정 위에 이것을 얹는다. 화면 글자의 NUL 은 공백으로. 기다리는 노드는 노란 2pt 테두리. 그룹 머리 요약은 "2 need you" 처럼 개수를 함께. 단위 테스트(실제 화면 표본: claude 신뢰, codex 신뢰·업데이트·데몬 메뉴, 평소 입력창, 번호 목록 답) 9개.
  - codex 승인 화면: 이 머신 codex 는 YOLO 모드(자동 승인)라 명령 승인 화면이 뜨지 않는다. 같은 꼴(번호 선택지 위 › 표시)이라 데몬 메뉴 규칙으로 잡힌다(표본 테스트).
  - 확인한 실제 입력: 새 상태 `/tmp/symv4c` → Open folder → Cmd+Shift+G `/tmp/symtrust-5` → Group → − 두 번 → 둘째 타일 눌러 Codex → Spawn 2. 두 노드 NEEDS YOU·노란 테두리, 그룹 머리 "2 · 2 need you"(`1-group-needs-you.png`). 미션 맵(도구 메뉴 → Mission Map) "Needs you 1", 행 "Needs input"(`1-mission-needs-you.png`, symtrust-4). codex 노드 클릭 → `1`, `2` → 신뢰 화면 동안 waiting → Return → 입력창 READY. claude 노드 클릭 → ↓ → Return → 입력창 READY, 그룹 "idle"(`1-after-answer-ready.png`). 질문 0회.
- [ ] 2. 권한 확인을 기다리는 상태를 실제로 확인(노드·그룹 헤더·미션 맵 Needs you, 노드 강조, 승인 후 Working → Idle/Done)
- [ ] 3. Idle 과 Done 의 구분(원본 뜻 찾기, DECISIONS, 보거나 새 질문하면 풀림)
- [ ] 4. 작업 중 표시(노드 알약, 그룹 요약 "1 running", 상단 live, 미션 맵 Working 개수) 1초 간격 캡처
- [ ] 5. 글 쓰는 창이 열리자마자 첫 칸에 초점, Enter 저장 / Esc 취소(여러 줄은 Cmd+Enter)
- [ ] 6. 칸반 Done 열 카드 표시
- [ ] 7. 앱이 스스로 만드는 노드(인스펙터, 복제, 컴포저 그룹, 문서·다이어그램 결과)도 보이는 영역 안으로
- [ ] 8. 셸 Ctrl+C 실제 입력 확인(`sleep 100` 끊기)

## 다시 눌러 볼 화면

- [ ] 1. G 계정 프로필: 추가, 바꾸기, 노드에 적용
- [ ] 2. N 사용량: 팝오버 숫자, 고리, 초기화 시각
- [ ] 3. H 체크리스트·캘린더: 항목 추가·체크, 일정 추가
- [ ] 4. I 이미지: 끌어 놓기 또는 붙여 넣기, 크기 조절
- [ ] 5. C 오케스트레이터: 끌어서 팀과 연결, 연결 끊기, 연결된 팀에만 명령
- [ ] 6. O·P 코드 스튜디오: 파일 열기, 고치기, 저장, 탭 여러 개
- [ ] 7. Q 마크다운 스튜디오: Reading/Source/Graph 전환, 링크 따라가기
- [ ] 8. R 문서 생성: 실제 질문 1회, 실시간으로 그려지는지
- [ ] 9. S 다이어그램 생성: 실제 질문 1회, 손그림 스타일, 노드 옮기면 선이 따라옴

## 하루 쓰기 흐름 (새 SYMBOARD_HOME, /tmp/symday)

- [ ] 1. 홈 화면 → Open folder
- [ ] 2. Group 으로 claude 2 + 셸 1 팀, claude 하나는 자동 승인 끔
- [ ] 3. `@team` 으로 "run the tests and tell me which one fails, do not fix" (질문 2회)
- [ ] 4. 미션 맵에서 Working → Needs you(권한) → Done
- [ ] 5. 권한 기다리는 노드로 Go to → 승인 → 끝날 때까지
- [ ] 6. 칸반에 결과 카드
- [ ] 7. git 카드에서 로컬 커밋
- [ ] 8. Cmd+Q → 다시 실행 → 이어하기 토스트 → 같은 자리·같은 대화

## 막힌 것

(없음)
