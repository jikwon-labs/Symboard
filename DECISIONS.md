# 결정 기록
- SwiftTerm 은 1.11.2 고정: 1.12 부터 Metal 셰이더가 들어가 Metal Toolchain(시스템 컴포넌트 다운로드) 없이는 빌드가 안 된다.
- UI 는 AppKit 중심(NSScrollView 확대/축소로 캔버스, 노드는 NSView). 보조 패널만 SwiftUI(NSHostingView). SwiftTerm 이 NSView 라 AppKit 이 덜 막힌다.
- App Nap 을 끈다(ProcessInfo.beginActivity). 가려진 창에서 타이머가 멈춰 상태 판정·루프·디버그 통로가 멈추는 것을 직접 겪었다.
- 루프의 목표·출력 조건은 노드가 우리가 보낸 문장을 다시 찍은 부분을 빼고 본다(보낸 문장 안에 목표 문구가 있어도 바로 꺼지지 않게). 같은 규칙은 3초 안에 다시 보내지 않는다.
- 웹 인스펙터는 공개 API 가 없어 WKWebView 의 내부 _inspector 를 있을 때만 쓰고, 없으면 오른쪽 클릭 Inspect Element 로 안내한다.
- git 카드 Commit 은 add -A 후 커밋(원본처럼 한 번에). pull 은 --ff-only 로 병합 커밋을 만들지 않는다.
- 스튜디오 PDF 는 printOperation 대신 createPDF 결과를 직접 쪽으로 자른다(화면 밖 웹뷰 인쇄가 끝나지 않는 문제를 겪음). 다이어그램은 Mermaid 대신 'A -> B: 라벨' 한 줄 형식으로 단순하게 했다.
