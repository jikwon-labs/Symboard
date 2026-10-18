STATUS: IN_PROGRESS

# Symboard 3차 진행표

기준 커밋 `d5d1f37` (2차 완료본). 2차 테스트 수 72.
확인은 `orca computer`(`/Applications/Orca.app/Contents/Resources/bin/orca`) 실제 클릭·키 입력으로 한다. DebugBridge(`scripts/drive.sh`)는 상태를 깔아 두는 데만 쓴다.
스크린샷은 `docs/screens/v3/<항목번호>-<이름>.png`. 체크한 항목 아래에 "재현 방법 / 고친 원인 / 확인한 실제 입력" 을 적는다.

## 고칠 것

- [x] 1. 칸반 "+ Add card" 등 터미널이 아닌 모든 노드 안쪽 버튼이 실제 클릭(배율 100%·50%)에 반응
  - 재현: 51% 에서 TO DO "Add card" 실제 클릭 두 번 → 반응 없음. 같은 자리 100% 는 됨. SwiftUI 탭 위치를 찍어 보니 실제 (911,272) 대신 (465,139) = 정확히 ×0.51.
  - 원인: NSHostingView 가 조상 NSScrollView 의 배율을 빼지 않고 마우스 위치를 계산한다. 노드 본문 호스팅 뷰를 `CanvasHostingView`(이벤트 위치를 배율 보정해 넘김)로 바꿨다. 덧붙여 `.plain` 단추는 글자·아이콘 픽셀만 눌려 50% 의 캘린더 "+ New" 가 빗나가서, 라벨 사각형 전체가 눌리는 `.plainHit` 로 모두 바꿨다. 시작할 때 복원된 오케스트레이터는 창 컨트롤러를 못 잡아 Connect 가 죽어 있어서 `MainWindowController.current` 로 고쳤다.
  - 확인(실제 클릭, 50%): 칸반 Add card → 모달 → 제목 입력 → Add card 저장, 카드 동그라미 완료 토글, + Column 입력창, 열 메뉴 · 체크리스트 항목 토글, Add an objective 입력·저장 · 캘린더 다음 달, + New, 날짜 칸, 일정 제목 입력·Add event 저장 · 스티키·도형 두 번 눌러 편집·입력 · git 파일 체크 토글 · 웹 탭 +, 포트 칩 :3000, 표시 크기 메뉴, 인스펙터 열기·Console 탭 · 코드 파일 Open in studio · 오케스트레이터 Connect/Done. 100%: 칸반 Add card·제목 입력, 캘린더 + New, git 체크, 웹 탭 +, Connect/Done, Open in studio. 문서 카드는 안쪽 단추가 없다.
- [ ] 2. 모달을 Esc 로 닫은 직후 오른쪽 막대 버튼 첫 클릭이 무시됨
- [ ] 3. 컴포저 카드가 아래로 자라 아래 버튼 줄·명령 입력을 가림 → 위로 자라고 화면 안에 머묾
- [ ] 4. 컴포저 개수 늘리면 새 타일이 Fill all 값이 아니라 Claude 로 생김
- [ ] 5. 새로 띄운 셸이 첫 명령 전까지 RUNNING 으로 보임 → READY
- [ ] 6. 캔버스 가장자리에 놓은 노드가 왼쪽 막대·아래 버튼 줄 밑으로 들어감
- [ ] 7. `SYMBOARD_HOME` 을 새 폴더로 줘도 이전 프로젝트(symclaude)로 열림 → 모든 상태를 SYMBOARD_HOME 아래로, 없으면 홈 화면
- [ ] 8. 사용량 알약 글자가 "usage" 와 "resets 5:00pm" 사이를 오감
- [ ] 9. 이름 없는 접근성 button 40개 이상 → 모든 아이콘 버튼에 accessibilityLabel
- [ ] 10. 루프 템플릿 7개 이름·설명 다시 쓰기 (원본과 같은 "Commit checkpoint" 등)
- [ ] 11. 루프 시작 화면 모달 아래 절반이 빔 → 내용 높이에 맞춤
- [ ] 12. "Try @all git status" 안내 알약이 팝오버 뒤로 비침
- [ ] 13. 2차에서 자동 확인 못 한 것 실제 입력 확인: 칸반 카드 끌어 옮기기, 메모리 카드 Send, git 메시지 생성, 메모리 Rewrite, 에이전트 판단 루프 목표

## 실제 입력으로 다시 확인할 흐름

- [ ] F1. 별 → Shell → 캔버스 클릭 → 아래 입력 `echo hi` + Return → 출력
- [ ] F2. Group → Testers → 개수 5 → Fill all Shell → Spawn → TESTERS 프레임 → `@all echo ok` → "Sent to 6 consoles"
- [ ] F3. Cmd+Q → 다시 실행 → 노드·그룹 같은 자리
- [ ] F4. 오케스트레이터 → Connect → 그룹 → Done → 연결선 → 오케스트레이터 입력으로 명령
- [ ] F5. 미션 맵 → 콘솔 고르기 → Go to → 이동
- [ ] F6. 루프: 템플릿 → 만들기 → 카운트다운 → 지금 실행 → 대상 콘솔 입력
- [ ] F7. 스티키·도형·펜: 놓기, 색 바꾸기, 그리기, 지우개
- [ ] F8. git 카드: bare 원격 예제 레포에서 파일 고르고 Commit & Push
- [ ] F9. 웹 타일: 포트 칩으로 열기, 해상도 프리셋, 인스펙터 타일
- [ ] F10. 코드 스튜디오 편집 → Save → 디스크 반영. 마크다운 Reading/Source/Graph

## 막힌 것

(없음)

## 충돌 기록

(없음)
