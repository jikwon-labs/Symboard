import AppKit
import SwiftUI
import SymboardCore

/// 처음 켤 때 한 번 뜨는 창(10차): 화면 모드(기기 따라가기·다크·라이트)와 언어를 고른다.
/// 고르는 즉시 앱에 적용해 미리 보이고, 시작하기(또는 창 닫기)로 저장한다. 나중에는 설정 창에서 바꾼다.
@MainActor
final class FirstRunWindow: NSObject, NSWindowDelegate {
    private static var current: FirstRunWindow?
    private let panel: NSPanel
    private let state = FirstRunState()

    static func show(over parent: NSWindow?) {
        guard current == nil else { return }
        let w = FirstRunWindow()
        current = w
        if let p = parent {
            w.panel.setFrameOrigin(NSPoint(x: p.frame.midX - w.panel.frame.width / 2, y: p.frame.midY - w.panel.frame.height / 2))
        } else {
            w.panel.center()
        }
        if AppDelegate.background { w.panel.orderBack(nil) } else { w.panel.makeKeyAndOrderFront(nil) }
    }

    private override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        panel.title = "Symboard"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = Theme.surface
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: FirstRunView(state: state) { [weak self] in self?.panel.close() }.localized())
    }

    func windowWillClose(_ notification: Notification) {
        // 닫기만 해도 지금 고른 값으로 저장한다(다음에 다시 묻지 않게).
        UIPrefs.setAppearance(state.appearance, Prefs.shared)
        UIPrefs.setLanguage(state.language, Prefs.shared)
        Self.current = nil
    }
}

@MainActor
final class FirstRunState: ObservableObject {
    @Published var appearance: AppearanceMode = .system { didSet { Theme.apply(appearance) } }
    @Published var language: LanguageMode = .system { didSet { L10n.apply(language) } }
}

struct FirstRunView: View {
    @ObservedObject var state: FirstRunState
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Welcome to Symboard")).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.symText)
                Text(L("Pick how it looks. You can change this later in Settings."))
                    .font(.system(size: 12)).foregroundStyle(Color.symDim)
            }
            Text(L("Appearance")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.symDim)
            HStack(spacing: 12) {
                ForEach(AppearanceMode.allCases, id: \.self) { m in
                    Button { state.appearance = m } label: { AppearanceCard(mode: m, on: state.appearance == m) }
                        .buttonStyle(.plain)
                        .axName("Appearance \(m.rawValue)")
                }
            }
            Text(L("Language")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.symDim)
            HStack(spacing: 8) {
                ForEach(LanguageMode.allCases, id: \.self) { m in
                    Button(m == .system ? L("Follow system") : (m == .ko ? "한국어" : "English")) { state.language = m }
                        .buttonStyle(PillButtonStyle(active: state.language == m))
                        .axName("Language \(m.rawValue)")
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L("Get started")) { done() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .axName("Get started")
            }
        }
        .padding(24)
        .frame(width: 560, height: 430, alignment: .topLeading)
        .background(Color.symSurface)
    }
}

/// 화면 모드 고르기 카드: 작은 보드 그림과 이름.
private struct AppearanceCard: View {
    var mode: AppearanceMode
    var on: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                switch mode {
                case .dark: Self.preview(dark: true)
                case .light: Self.preview(dark: false)
                case .system:
                    HStack(spacing: 0) { Self.preview(dark: false); Self.preview(dark: true) }
                }
            }
            .frame(width: 150, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? Color.symAccent : Color.symBorder, lineWidth: on ? 2 : 1))
            Text(L(SettingsWindowController.appearanceTitles[mode]!))
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Color.symText : Color.symDim)
        }
        .contentShape(Rectangle())
    }

    /// 보드 바탕, 콘솔 하나, 메모 하나를 그린 작은 그림(그 모드의 실제 색).
    static func preview(dark: Bool) -> some View {
        let bg = Color(hex: dark ? "#0F0E0D" : "#F5F2EE")
        let card = Color(hex: dark ? "#171615" : "#FFFFFF")
        let line = Color(hex: dark ? "#2E2B28" : "#DED7CF")
        return ZStack(alignment: .topLeading) {
            bg
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#121110"))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(line, lineWidth: 1))
                .frame(width: 58, height: 40).offset(x: 10, y: 16)
            RoundedRectangle(cornerRadius: 3).fill(card)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(line, lineWidth: 1))
                .frame(width: 40, height: 28).offset(x: 78, y: 22)
            Circle().fill(Color(hex: Theme.accentHex)).frame(width: 6, height: 6).offset(x: 14, y: 20)
        }
    }
}
