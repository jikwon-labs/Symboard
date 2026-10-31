# SwiftTerm 사본

원본: https://github.com/migueldeicaza/SwiftTerm 1.11.2 (b1262db5), MIT(`LICENSE`).
`Sources/SwiftTerm` 만 옮기고 `Package.swift` 는 라이브러리 대상 하나로 줄였다.

## 고친 곳

1. `LocalProcess.childProcessRead` — 읽기 작업이 끝났을 때(`done == true`)만 다음 읽기를 건다.
   원래는 낮은 수위 1 바이트로 조각이 올 때마다(`done == false` 포함) 새 `io.read` 를 걸어서,
   끝나지 않은 `OS_dispatch_operation` 과 직렬 큐가 출력 양에 비례해 쌓였다.
   Symboard 5차 많이 띄우기 시험(셸 24개 × 3000줄 다섯 번)에서 14만 6천 개, 약 65MB 까지 늘었다.
2. `MacTerminalView.FontSet` — 굵게·기울임 글꼴을 만들 때 기본 글꼴의 대체 글꼴 목록(cascade list)을 다시 붙인다.
   `NSFontManager.convert` 가 글꼴 설명의 `cascadeList` 를 버려서, Symboard 7차 터미널 한글 글꼴 설정이
   굵은 글자(claude 화면의 굵은 한글 등)에서는 적용되지 않고 macOS 기본 대체 글꼴로 돌아갔다.
   대체 글꼴도 같은 굵기·기울임으로 바꾸고, 붙어 있던 글자 범위(characterSet) 제한은 그대로 둔다.
3. `AppleTerminalView.resetFont` — 글꼴을 바꿀 때 창 크기가 바뀔 때와 같은 `processSizeChange` 로 칸 수를 다시 구한다.
   원래는 스크롤 막대 폭을 빼지 않은 전체 폭으로 열 수를 구해(오른쪽 두 칸이 막대 밑으로 들어감) `resize(cols:rows:)` 를 불렀고,
   그 안의 `softReset()` 이 돌고 있는 TUI(claude·codex)의 모드(커서 키 모드, 스크롤 영역 등)를 지웠다.
   Symboard 7차에서 설정의 글꼴을 바꾸면 떠 있는 콘솔에 바로 적용하므로 이 길을 탄다.
4. 콘솔 안 스크롤(Symboard 8차 1번).
   - `MacTerminalView.scrollWheel`: 프로그램이 마우스 보고 모드를 켰으면(claude 2.1.303 은 대체 화면 + anyEvent) 휠을 버튼 4·5 마우스 보고로 넘긴다.
     원래는 모드와 상관없이 지난 줄을 움직이려 해서, 지난 줄이 없는 대체 화면의 claude 에서는 휠이 아무 일도 하지 않았다.
     마우스 보고가 없는 대체 화면이면 위·아래 화살표로 보낸다(xterm alternate scroll). 트랙패드(정밀 스크롤)는 화소 양을 줄 높이로 나눠 모은다.
   - `AppleTerminalView.scrollTo`: 맨 아래가 아니면 `Terminal.userScrolling` 을 켠다. 원래 이 값을 켜는 곳이 없어 출력이 올 때마다 화면이 맨 아래로 튀었다.
   - `MacTerminalView.ensureCaretIsVisible`: 입력을 보내면 커서가 화면 안에 있어도 맨 아래로 돌린다.
   - `isScrolledBack`·`scrollToBottom()` 을 공개로 더했다("맨 아래로" 단추용).
5. 입력기 조합 중 글자 표시(Symboard 8차 9번). `MacTerminalView` 의 `setMarkedText`·`unmarkText`·`hasMarkedText`·`markedRange` 가 비어 있어
   한글 조합 중 글자가 확정되기 전까지 보이지 않았다. 조합 중 글자를 저장하고 커서 자리에 밑줄 친 글(터미널 글꼴·배경)로 겹쳐 그린다.
   폭은 글자 칸 수(한글 2칸)로. 커서가 움직이면(`updateCursorPosition`) 따라가고, 커서 뷰가 다시 붙으면 그 위로 올린다
   (확정 글자가 프로그램 메아리로 늦게 찍혀 겹쳐 보이던 문제). `insertText` 는 조합 표시를 지운다.
   `commitMarkedText()` 를 공개로 더했다(Option·Cmd 이동 키 전에 조합 중 글자를 먼저 확정해 보낸다).
6. 두 칸 글자 틈(Symboard 8차 8번). `AppleTerminalView` 글리프 그리기는 모든 글리프를 칸 왼쪽에 붙여 그린다.
   한글 글리프 폭은 12pt 에서 10.4pt 인데 두 칸은 14.8pt 라 글자마다 오른쪽에 4.4pt 틈이 생겨 "줍 니 다" 처럼 보였다.
   두 칸 글자 묶음(`columnWidth == 2`)은 `fitWideGlyphs`(MacTerminalView)로 글꼴을 두 칸의 84% 까지 키우되
   가장 높은 글리프 윗부분이 영문 글꼴 ascent 를 넘지 않게(최대 1.25배), 두 칸 가운데에 놓는다. 칸 위치는 그대로라 커서·선택·줄바꿈은 그대로다.
   이모지처럼 이미 넓은 글리프는 키우지 않고 가운데만 맞춘다.
7. 접두 글자가 붙은 CSI u(Symboard 8차 뒤 사용자 보고). `EscapeSequenceParser.dispatchCsi` 는 `CSI u` 를 접두 글자와 상관없이 커서 되돌리기(SCORC)로 처리했다.
   claude 2.1.314 는 시작할 때 kitty 키보드 프로토콜 질의 `ESC[?u` 를 보내는데, 이것이 앞서 `ESC 7` 로 저장한 위치(화면 위쪽)로 커서를 옮겨서
   폴더 신뢰 질문처럼 일반 화면에 상대 이동으로 다시 그리는 화면이 맨 위에 겹쳐 그려졌다(지난 화면 조각이 남음). 접두 글자(? > < =)가 있으면 아무것도 하지 않는다.
8. 화면에 없는 터미널의 그리기 건너뛰기(Symboard 성능 점검). 창에 붙지 않았거나(보고 있지 않은 작업공간의 캔버스)
   스스로나 조상이 숨겨졌으면(접힌 그룹) `AppleTerminalView.updateDisplay` 가 그리기 영역 계산·`setNeedsDisplay`·커서 옮기기·
   접근성 알림 두 개를 건너뛰고 `offscreenDirty` 만 켠다. 출력 해석(`Terminal.feed`)은 그대로 해서 버퍼는 늘 최신이다.
   다시 창에 붙거나 보이면(`viewDidMoveToWindow`·`viewDidUnhide`, MacTerminalView) 쌓인 갱신 범위를 비우고 전체를 다시 그린다.
   원래는 보이지 않는 콘솔도 출력이 오면 초당 최대 60번 갱신과 접근성 알림을 했다.
