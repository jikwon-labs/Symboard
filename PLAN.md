STATUS: IN_PROGRESS

# Symboard 계획

순서: 0 → 1 → 2 → 4 → 3 → 나머지. 각 항목은 빌드·테스트 통과 후 체크하고 메모를 남긴다.

## 체크리스트

- [x] 0. 뼈대: SwiftPM 패키지(SymboardCore 라이브러리 + Symboard 실행 타깃 + 테스트), SwiftTerm 의존성, `scripts/bundle.sh` 로 `build/Symboard.app` 생성
- [x] 1a. 보드: 무한 캔버스(이동·확대/축소)
- [x] 1b. 보드: 노드 끌어서 이동·크기 조절
- [x] 1c. 보드: 작업공간 여러 개를 탭처럼 전환
- [x] 2a. 터미널 노드: SwiftTerm + forkpty 로 셸 실행(Ctrl-C·vim·htop)
- [ ] 2b. 터미널 노드: 새 노드 생성 시 CLI 선택(claude, codex, 임의 실행 파일)
- [x] 4a. 이어하기: 작업공간 자동 저장(버전 붙은 JSON, ~/Library/Application Support/Symboard/)
- [ ] 4b. 이어하기: 재실행 시 노드 위치·크기·CLI 복원, claude `--session-id`/`--resume`, codex `resume --last`
- [ ] 3a. 상태: Claude Code 훅(`--settings` 로 주입) → 앱에 신호
- [ ] 3b. 상태: 훅 없는 CLI 는 출력 멈춘 시간으로 추정
- [ ] 3c. 상태: 전체 노드 목록 패널(미션 맵)
- [ ] 5. 컴포저(최대 12개 한 번에)와 팀(묶기·역할 이름)
- [ ] 6. 루프(시간 간격/유휴/특정 출력 시작, 목표 문구로 자동 종료)
- [ ] 7. 넘겨주기(보내는 노드 CLI 에 요약 요청 → 다른 노드에 입력)
- [ ] 8a. 메모 도구: 스티키·텍스트·체크리스트·칸반 노드
- [ ] 8b. 메모 도구: 펜 그리기, 이미지 드롭 후 표시
- [ ] 9. 웹 타일(WKWebView, 웹 인스펙터)
- [ ] 10. git 카드(브랜치·상태, commit·push·pull)
- [ ] 11a. 스튜디오: 코드(파일 트리·하이라이트·노드로 고정)
- [ ] 11b. 스튜디오: 마크다운(파일 트리·자동 저장 편집기·링크 그래프)
- [ ] 11c. 스튜디오: 문서(마크다운 → PDF), 다이어그램(PNG 내보내기)
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

## 막힌 것

