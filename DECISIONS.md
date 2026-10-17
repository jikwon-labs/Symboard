# 결정 기록
- SwiftTerm 은 1.11.2 고정: 1.12 부터 Metal 셰이더가 들어가 Metal Toolchain(시스템 컴포넌트 다운로드) 없이는 빌드가 안 된다.
- UI 는 AppKit 중심(NSScrollView 확대/축소로 캔버스, 노드는 NSView). 보조 패널만 SwiftUI(NSHostingView). SwiftTerm 이 NSView 라 AppKit 이 덜 막힌다.
- App Nap 을 끈다(ProcessInfo.beginActivity). 가려진 창에서 타이머가 멈춰 상태 판정·루프·디버그 통로가 멈추는 것을 직접 겪었다.
