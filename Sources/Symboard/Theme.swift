import AppKit
import SwiftUI
import SymboardCore

/// 화면 전체에서 쓰는 색과 글꼴. 짙은 따뜻한 바탕(다크) 또는 밝은 종이 바탕(라이트, 10차)에 주황빨강 강조색.
/// 색은 모두 화면 모드에 따라 바뀌는 색(NSColor dynamicProvider)이라 NSApp.appearance 를 바꾸면 AppKit·SwiftUI 가 다시 칠한다.
/// 층(CALayer)에 넣은 cgColor 는 저절로 바뀌지 않으므로 `Theme.didChange` 알림에서 다시 넣는다.
enum Theme {
    static let canvasHex = "#0F0E0D"
    static let accentHex = "#F05A38"

    static let canvas = dynamic(dark: canvasHex, light: "#F5F2EE")
    static let dot = dynamic(dark: "#2A2724", light: "#D9D2CA")
    static let surface = dynamic(dark: "#171615", light: "#FFFFFF")
    static let surfaceRaised = dynamic(dark: "#1F1D1B", light: "#F1EDE8")
    static let border = dynamic(dark: "#2E2B28", light: "#DED7CF")
    static let nodeBorder = dynamic(dark: "#3A2E2A", light: "#D8C9C2")
    static let accent = NSColor(hex: accentHex)
    static let text = dynamic(dark: "#ECE7E2", light: "#211D1A")
    static let textDim = dynamic(dark: "#8F8882", light: "#77706A")
    /// 콘솔 안은 두 모드 모두 어두운 바탕(claude·codex·셸 색이 어두운 바탕에 맞춰져 있다, DECISIONS 10차-1).
    static let terminalBackground = NSColor(hex: "#121110")
    static let terminalText = NSColor(hex: "#ECE7E2")
    /// 떠 있는 막대 그림자.
    static let shadow = dynamic(dark: "#000000", light: "#5A4A40")

    /// 화면 모드가 바뀌었을 때(층 색을 다시 넣는 곳이 받는다).
    static let didChange = Notification.Name("symboard.themeDidChange")

    /// 화면 모드가 바뀔 때마다(처음 한 번 포함) body 를 다시 부른다. 층 색처럼 저절로 바뀌지 않는 곳에서 쓴다.
    @MainActor
    static func paint(_ body: @escaping @MainActor () -> Void) {
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { body() }
        _ = NotificationCenter.default.addObserver(forName: didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { body() } }
        }
    }

    /// 기기 화면 모드가 바뀌어도(기기 따라가기일 때) didChange 를 보낸다.
    @MainActor
    static func watchSystemAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }
    @MainActor private static var appearanceObservation: NSKeyValueObservation?

    static func dynamic(dark: String, light: String) -> NSColor {
        let d = NSColor(hex: dark), l = NSColor(hex: light)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? l : d
        }
    }

    static var isLight: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua }

    /// 동적 색을 지금 모드의 고정 색으로(층 색·층 글자용). cgColor 를 그때그때 풀면 옛 모드 색이 남는 경우가 있었다.
    static func resolved(_ c: NSColor) -> NSColor {
        var out = c
        NSAppearance(named: isLight ? .aqua : .darkAqua)!.performAsCurrentDrawingAppearance {
            out = c.usingColorSpace(.sRGB) ?? c
        }
        return out
    }

    /// 저장된 노드 색 중 "어두운 바탕용 글·선 색"(다이어그램 잉크 등)을 지금 모드에 맞는 색으로. 나머지 색은 그대로.
    static func ink(_ hex: String?) -> NSColor? {
        guard let hex else { return nil }
        switch hex.uppercased() {
        case "#ECE7E2": return text
        case "#8F8882": return textDim
        case "#5A5550": return dynamic(dark: "#5A5550", light: "#B7AEA6")
        default: return NSColor(hex: hex)
        }
    }

    /// 설정한 화면 모드를 앱에 적용한다. nil 은 기기 설정을 따른다.
    @MainActor
    static func apply(_ mode: AppearanceMode) {
        let fades = coverWindowsForFade()
        switch mode {
        case .system: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
        // NSApp.effectiveAppearance 는 다음 순간에 바뀐다. 바로 보내면 층 색을 옛 모드로 다시 칠했다(다크로 바꿨는데 화살표가 어두운 색).
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didChange, object: nil)
            // 새 모드로 다 칠한 뒤 옛 화면 사진을 서서히 걷어 낸다.
            DispatchQueue.main.async { fadeOut(fades) }
        }
    }

    static let fadeDuration: TimeInterval = 0.4

    /// 바꾸기 전, 보이는 창마다 지금 화면을 사진으로 찍어 맨 위에 덮는다(모드 전환을 부드럽게 넘기는 교차 페이드).
    /// 층 색·SwiftUI·콘솔이 저마다 다른 때에 바뀌어도 사진이 가려 주므로 한 번에 자연스럽게 바뀐 것처럼 보인다.
    /// 동작 줄이기(손쉬운 사용)가 켜져 있으면 바로 바꾼다.
    @MainActor
    private static func coverWindowsForFade() -> [NSView] {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return [] }
        var covers: [NSView] = []
        for window in NSApp.windows where window.isVisible && window.occlusionState.contains(.visible) {
            guard let root = window.contentView?.superview ?? window.contentView, root.bounds.width > 0, root.bounds.height > 0,
                  let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { continue }
            root.cacheDisplay(in: root.bounds, to: rep)
            let image = NSImage(size: root.bounds.size)
            image.addRepresentation(rep)
            let cover = FadeCover(frame: root.bounds)
            cover.image = image
            cover.imageScaling = .scaleAxesIndependently
            cover.wantsLayer = true
            cover.autoresizingMask = [.width, .height]
            root.addSubview(cover, positioned: .above, relativeTo: nil)
            covers.append(cover)
        }
        return covers
    }

    @MainActor
    private static func fadeOut(_ covers: [NSView]) {
        guard !covers.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for c in covers { c.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated { for c in covers { c.removeFromSuperview() } }
        })
    }

    /// 손글씨풍 글꼴. 시스템에 있는 것 중 고른다.
    static func handwriting(size: CGFloat) -> NSFont {
        for name in ["ChalkboardSE-Regular", "Noteworthy-Light", "MarkerFelt-Thin"] {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return .systemFont(ofSize: size)
    }

    static func mono(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

extension Color {
    static let symCanvas = Color(nsColor: Theme.canvas)
    static let symSurface = Color(nsColor: Theme.surface)
    static let symRaised = Color(nsColor: Theme.surfaceRaised)
    static let symBorder = Color(nsColor: Theme.border)
    static let symAccent = Color(nsColor: Theme.accent)
    static let symText = Color(nsColor: Theme.text)
    static let symDim = Color(nsColor: Theme.textDim)

    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}

/// 떠 있는 둥근 막대의 바탕.
struct FloatingCapsule: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.symSurface.opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.symBorder, lineWidth: 1))
            .shadow(color: Color(nsColor: Theme.shadow).opacity(Theme.isLight ? 0.16 : 0.45), radius: 10, y: 4)
    }
}

extension View {
    func floatingCapsule(radius: CGFloat = 14) -> some View { modifier(FloatingCapsule(radius: radius)) }
    /// 언어를 바꾸면 다시 그린다(10차). SwiftUI 뿌리 뷰마다 붙인다.
    func localized() -> some View { modifier(LocalizedRoot()) }
}

struct LocalizedRoot: ViewModifier {
    @ObservedObject private var l10n = L10n.shared
    func body(content: Content) -> some View { content.id(l10n.revision) }
}

/// 위쪽·아래쪽 막대의 알약 버튼.
struct PillButtonStyle: ButtonStyle {
    var active = false
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Color.white : (active ? Color.symText : Color.symText.opacity(0.85)))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent ? Color.symAccent : Color.symRaised.opacity(configuration.isPressed ? 1 : 0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(active ? Color.symAccent : Color.symBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

/// 세로 막대의 아이콘 버튼.
struct RailButtonStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(active ? Color.symAccent : Color.symText.opacity(configuration.isPressed ? 0.6 : 0.85))
            .frame(width: 36, height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.symAccent.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
    }
}

/// 창 위치·크기를 prefs.json 에 두고 되살린다(UserDefaults 의 frame autosave 대신).
@MainActor
enum WindowFrames {
    private static var observers: [NSObjectProtocol] = []

    /// 저장된 위치가 있으면 그 자리로, 없으면 가운데. 이후 옮기거나 크기를 바꾸면 저장한다.
    static func track(_ window: NSWindow, key: String) {
        if let s = Prefs.shared.string("window.\(key)") { window.setFrame(from: s) } else { window.center() }
        let save = { [weak window] (_: Notification) in
            MainActor.assumeIsolated {
                if let w = window { Prefs.shared.set(w.frameDescriptor, for: "window.\(key)") }
            }
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: save))
        observers.append(nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main, using: save))
    }
}

/// 모드 전환 때 덮는 옛 화면 사진. 클릭은 아래로 그대로 지나간다.
private final class FadeCover: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
