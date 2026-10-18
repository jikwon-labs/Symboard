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
- [x] 2. 모달을 Esc 로 닫은 직후 오른쪽 막대 버튼 첫 클릭이 무시됨
  - 재현: 오른쪽 막대 루프 → Esc → 체크리스트 아이콘 실제 클릭 → 반응 없음, 다시 누르면 열림. 화면을 찍어 보니 Esc 뒤에도 루프 모달이 그대로 열려 있었다.
  - 원인: 루프·메모리·스튜디오·미션 맵 모달에 Esc 처리가 없었다. 첫 클릭은 모달의 어두운 배경을 눌러 모달을 닫는 데 쓰였다. 키 감시에서 Esc 가 오면 맨 위 모달을 닫고 보드에 초점을 돌리게 했다(`closeTopOverlay`).
  - 확인(실제 입력): 루프 아이콘 클릭 → Esc 키 → 모달 닫힘(화면) → 체크리스트 아이콘 한 번 클릭 → 팝오버 열림. 코드 스튜디오 열기 → Esc → 체크리스트 한 번 클릭 → 열림.
- [x] 3. 컴포저 카드가 아래로 자라 아래 버튼 줄·명령 입력을 가림 → 위로 자라고 화면 안에 머묾
  - 재현: Group → + 실제 클릭 → 타일 줄이 늘며 카드가 아래로 커져 New console 줄과 명령 입력을 덮고, 화살표가 Group 아래로 내려감.
  - 원인: SwiftUI `.popover` 가 내용이 커질 때 위쪽을 고정했다. 컴포저를 Group 단추에 붙인 AppKit `NSPopover`(preferredContentSize 로 크기 따라감)로 바꿔 단추 쪽을 고정했다.
  - 확인(실제 클릭): Group → + 를 같은 자리에서 8번 → 매번 "+" 가 커서 밑에 그대로 있고 카드가 위로 자람, 12개에서도 화면 안. Esc 로 닫힘.
- [x] 4. 컴포저 개수 늘리면 새 타일이 Fill all 값이 아니라 Claude 로 생김
  - 재현: 새 타일은 "바로 앞 타일 값" 을 따랐다. 타일 하나를 따로 Claude 로 돌린 뒤 늘리면 Claude 가 생겼다(Fill all 값이 무시됨).
  - 원인: 컴포저가 마지막 Fill all 값을 기억하지 않았다. `fillChoice` 를 두고 `Composer.resize`(단위 테스트 3개)가 Fill all → 앞 타일 → 기본 CLI 순으로 고른다.
  - 확인(실제 클릭): Fill all Shell → 다섯째 타일을 눌러 Claude 로 → + 두 번 → 새 타일 둘 다 Shell. Fill all Claude → + → Claude.
- [x] 5. 새로 띄운 셸이 첫 명령 전까지 RUNNING 으로 보임 → READY
  - 재현: 이 환경에서는 New console 셸이 3초 뒤 READY 로 바뀌어 그대로 재현되지 않았다. 판정이 "마지막 출력 3초 안이면 RUNNING" 이라, 프롬프트를 다시 그리는 셸 설정(시계·비동기 git 상태 등)이면 입력을 기다리는 동안에도 RUNNING 이 된다는 것을 코드에서 확인했다.
  - 원인/고침: 일반 셸은 출력 시각 대신 터미널의 앞 프로세스 그룹(`tcgetpgrp`)이 셸 자신인지로 판정한다. 셸이 앞에 있으면 READY, 명령이 돌면 출력이 없어도 RUNNING. 첫 출력 전 3초는 STARTING. 단위 테스트 4개.
  - 확인(실제 입력): New console 클릭 → 3초 뒤 READY(첫 명령 전) → 명령 입력에 `sleep 6` + Return → 2초 뒤 RUNNING → 9초 뒤 READY.
- [x] 6. 캔버스 가장자리에 놓은 노드가 왼쪽 막대·아래 버튼 줄 밑으로 들어감
  - 재현: 체크리스트 아이콘 → Board → 캔버스 왼쪽 끝 클릭 → 칸반 왼쪽이 왼쪽 막대 밑으로 들어감(1번 재현 때 같이 봄).
  - 원인: 놓기는 누른 점을 중심으로 그대로 놓았다. 위 70·좌우 80·아래 110 포인트를 뺀 보이는 영역 안으로 옮기고(`CanvasLayout.fit`, 단위 테스트 3개), 영역보다 크면 들어오게 축소한다.
  - 확인(실제 클릭, 100%): Board 를 왼쪽 막대 바로 옆(x 110) 클릭 → 막대 오른쪽·버튼 줄 위로 놓임. 별 → Shell → 오른쪽 아래 구석 클릭 → 오른쪽 막대 왼쪽·버튼 줄 위로 놓임.
- [x] 7. `SYMBOARD_HOME` 을 새 폴더로 줘도 이전 프로젝트(symclaude)로 열림 → 모든 상태를 SYMBOARD_HOME 아래로, 없으면 홈 화면
  - 재현: 빈 `/tmp/symv3` 로 띄우자 위쪽 프로젝트가 symclaude. `defaults read local.symboard.app` 에 `lastCwd = /tmp/symclaude` 가 남아 있었고, 빈 작업공간이 이 값을 프로젝트로 받았다.
  - 원인/고침: lastCwd·lastAgentChoice·docTiming·창 위치를 UserDefaults 대신 상태 폴더의 `prefs.json`(`Prefs`, 단위 테스트 1개)에 둔다. 빈 작업공간에는 프로젝트를 추측해 붙이지 않고, 노드가 하나도 없으면 홈 화면으로 시작한다. 폴더를 열면 처음 생긴 빈 작업공간에 붙인다.
  - 확인(실제 입력): 빈 `/tmp/symv3h` 로 실행 → Projects 화면(Open folder 만) → Open folder 클릭 → 열기 창에서 Cmd+Shift+G, `/tmp/symsample` 입력, Return, Return → 보드가 symsample 로 열림, `prefs.json` 에 lastCwd. Cmd+Q 후 다시 실행 → symsample 로 열림.
- [x] 8. 사용량 알약 글자가 "usage" 와 "resets 5:00pm" 사이를 오감
  - 재현: 재실행할 때마다 처음 몇 초는 "usage", 로그 훑기가 끝나면 "resets 5:00pm"(이번 시험에서 두 가지를 모두 봄). 훑기가 실행 3초 뒤 시작해 12초쯤 걸린다.
  - 원인/고침: 값이 없을 때 다른 낱말("usage")을 보였다. 늘 "resets …" 꼴로 보이고 모르면 `resets –:––` 자리표시(`UsagePill`, 단위 테스트 3개). 마지막으로 구한 묶음 끝을 prefs.json 에 두어 재실행 직후에도 같은 값을 보이고, 훑기는 바로 시작하며 5분마다 다시 한다.
  - 확인(실제 입력): Cmd+Q·재실행을 3번, 각각 2초·17초에 화면 → 여섯 번 모두 "resets 5:00pm". 캐시가 없던 첫 실행들은 여섯 번 모두 "resets –:––" 로 같았다.
- [x] 9. 이름 없는 접근성 button 40개 이상 → 모든 아이콘 버튼에 accessibilityLabel
  - 재현: 노드 10개 보드에서 orca 접근성 트리에 이름 없는 `button` 86개.
  - 원인: 아이콘 단추에 이름이 없었고(.help 는 이름이 아님), 더해서 orca 는 SwiftUI 단추 이름을 아예 읽지 못했다(accessibilityLabel·Button("글자")·.borderless 모두 실험해 봄). 단추마다 `.tip("…")`(설명+이름) 또는 `.axName("…")`(글자 단추)을 달고, 그 안에서 이름 붙은 투명 AppKit 대역을 겹쳤다(DECISIONS.md). 대역은 클릭을 통과시키고 접근성 누르기를 실제 클릭으로 바꾼다.
  - 확인(실제 입력): 같은 보드 트리에서 이름 없는 단추 86 → 0(이름 있는 단추 144, `9-ax-tree.txt`). 칸반 카드 모달·컴포저 팝오버를 연 상태도 0. 대역 위 실제 클릭: 배율 −, 칸반 Add card, 체크리스트 토글, 별 메뉴 Shell 행 → 모두 동작. orca 의 접근성 누르기(element-index)로 "Zoom in" → 40%→50%. SwiftUI 팝오버 창(별 메뉴 등)은 orca 스냅샷에 들어오지 않아 그 안 이름은 트리로 확인하지 못했다(코드로만 달았음).
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
