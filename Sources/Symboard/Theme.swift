import AppKit
import SwiftUI

/// 화면 전체에서 쓰는 색과 글꼴. 짙은 따뜻한 바탕에 주황빨강 강조색.
enum Theme {
    static let canvasHex = "#0F0E0D"
    static let accentHex = "#F05A38"

    static let canvas = NSColor(hex: canvasHex)
    static let dot = NSColor(hex: "#2A2724")
    static let surface = NSColor(hex: "#171615")
    static let surfaceRaised = NSColor(hex: "#1F1D1B")
    static let border = NSColor(hex: "#2E2B28")
    static let nodeBorder = NSColor(hex: "#3A2E2A")
    static let accent = NSColor(hex: accentHex)
    static let text = NSColor(hex: "#ECE7E2")
    static let textDim = NSColor(hex: "#8F8882")
    static let terminalBackground = NSColor(hex: "#121110")

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
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }
}

extension View {
    func floatingCapsule(radius: CGFloat = 14) -> some View { modifier(FloatingCapsule(radius: radius)) }
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
