# Symboard 7차 완료 보고

## 한 줄 결론

명령 바·오케스트레이터 입력칸에 @ 자동완성과 이름 색칠을 넣었고, 앱 안 입력칸에서 I 커서가 나오게 고쳤으며, 설정 창에 터미널 영문·한글 글꼴과 크기를 고르는 칸을 만들었다. 완료 기준 실제 입력 시험 1~8 을 모두 통과했다(1~7 은 한 인스턴스에서 이어서, 8 은 3번 코드를 넣은 새 인스턴스에서). 테스트 162 → 177개, `swift build -c release` 통과, codex 0.163.0 그대로(시작부터 0.163.0, 프롬프트 기대값 0.157.1 과 다름), 실제 claude 질문 1회.

## 고친 것 (원인 한 줄씩)

1. **@ 자동완성**: 입력칸이 SwiftUI `TextField` 라 목록·부분 색칠을 붙일 수 없었다 → NSTextField 를 감싼 `MentionField` 로 바꾸고, @ 를 치면 살아 있는 콘솔 → all → 그룹 목록(CLI 배지·상태 점), 앞부분 일치로 좁히기, 위·아래·Tab·Enter·클릭으로 `@이름 ` 넣기, Esc 는 목록만 닫기. 계산은 `SymboardCore/Mention.swift` 에 두고 단위 테스트를 붙였다.
2. **이름 색칠**: 알려진 @이름(넣은 것·직접 끝까지 친 것)은 주황 글자 + 옅은 알약 배경. 한글 조합 중에는 칠하지 않아 조합이 깨지지 않는다.
3. **여러 대상**: 맨 앞 @ 여러 개는 원래 지원됐지만 빈칸 든 그룹 이름(`@group 1`)을 못 잡았다 → 가장 길게 맞는 알려진 이름으로 잡는다.
4. **I 커서**: SwiftUI 입력칸이 건 I 커서를 위의 NSHostingView 가 화살표로 다시 덮었다(기준본에서 커서 기록으로 확인, closedHand push/pop 은 원인 아님) → 마우스 이동마다 마우스 아래가 편집 가능한 글 입력칸이면 I 커서를 거는 `TextCursor` 하나로 앱 전체를 고쳤다.
5. **터미널 글꼴**: 글꼴이 12pt SF Mono 고정이고 설정 창이 없었다 → 톱니로 여는 Settings 창(Font·Korean font·Size·미리보기). 한글 글꼴은 cascade list + 한글 글자 범위 제한으로 한글에만 쓰인다. 바꾸면 떠 있는 모든 콘솔에 바로, prefs.json 에 남아 다시 켜도 유지.
6. **SwiftTerm 두 곳**(`Vendor/SwiftTerm/PATCHES.md`): 굵은 글꼴을 만들 때 cascade list 가 사라져 굵은 한글에 적용이 안 됐다 / 글꼴을 바꿀 때 스크롤 막대 폭을 무시하고 열 수를 구하며 `softReset()` 으로 돌고 있는 TUI 모드를 지웠다 → 둘 다 고쳤다.

## 남은 것

- Pretendard 와 Apple SD Gothic Neo 는 생김새가 거의 같아 비교 화면에서 눈으로 구분하기 어렵다(화소 비교로 다름 확인). 한글만 바뀌는 것은 Nanum Pen Script 비교 화면으로 보였다.
- 터미널 안에서 한글 조합 중인 글자는 그려지지 않는다(확정되면 보임). SwiftTerm 원래 동작이고 이번 범위에서 바꾸지 않았다.
- 한글 입력 상태에서 `@` 를 치는 경우, 프리셋·delete group 실제 입력은 이번에 다시 시험하지 않았다.
- 마지막 다시 켜기 직전에 설정 크기가 원인 모르게 14pt 로 저장돼 있었다(PLAN-7 "확인 못 한 것").
- 시험 방법 메모: `orca computer type-text`·`press-key` 는 입력기를 거치지 않는다. 한글 입력 시험은 `scripts/input/cgclick.swift keys` + `inputsrc.swift`, 입력 소스를 바꾼 뒤 앱을 한 번 다른 앱 → 다시 앞으로.

## 사용자가 직접 눌러 볼 순서

1. 앱을 켜고 폴더를 연 뒤 아래 명령 바에 `spawn 4 shell` → Enter.
2. 명령 바에 `@` → 목록에 Ada·Pip·Maya·Iris·all·group 1. `p` → Tab → `@Pip ` 가 주황으로 → `echo hi` → Enter → Pip 에만 찍힌다.
3. `@` → 아래 화살표 두 번 → Tab → `@Maya `. 다시 `@` → Esc → 목록만 닫힌다.
4. `@Ada @Maya echo two` → Enter → 두 콘솔에만.
5. 한글 입력으로 바꿔 `@Iris 안녕` → Enter → Iris 에만.
6. 명령 바·칸반 카드 편집 창·스티커에 마우스를 올리면 I 커서, 빈 캔버스로 나오면 화살표. 캔버스를 끈 뒤에도 같다.
7. 오른쪽 위 톱니 → Settings → Korean font 를 Pretendard(또는 차이가 크게 보이는 Nanum Pen Script)로 → 떠 있는 콘솔의 한글만 바뀐다. Size 를 바꾸면 콘솔 글자 크기와 줄 폭이 바로 바뀐다. 앱을 다시 켜도 그대로.
