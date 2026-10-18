import AppKit
import QuartzCore
import SwiftUI
import SymboardCore

/// 모든 노드 위에 얹는 펜 획 층. 획마다 CAShapeLayer 하나라 큰 캔버스에서도 가볍다.
/// 펜·지우개·놓기 도구일 때만 마우스를 받아 캔버스에 넘긴다(노드 위에서도 이어 그리기).
final class InkOverlayView: NSView {
    weak var canvas: CanvasView?
    private var layers: [UUID: CAShapeLayer] = [:]
    private let live = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(live)
        live.fillColor = nil
        live.lineCap = .round
        live.lineJoin = .round
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let c = canvas, c.tool != .select, frame.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) { canvas?.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { canvas?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { canvas?.mouseUp(with: event) }
    override func mouseMoved(with event: NSEvent) { canvas?.mouseMoved(with: event) }
    override func resetCursorRects() {
        if let c = canvas, c.tool != .select { addCursorRect(visibleRect, cursor: .crosshair) }
    }

    static func path(_ pts: [Point], offset: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let simple = Ink.simplify(pts)
        guard let first = simple.first else { return p }
        p.move(to: CGPoint(x: first.x + offset, y: first.y + offset))
        if simple.count == 1 { p.addLine(to: CGPoint(x: first.x + offset + 0.1, y: first.y + offset)); return p }
        for (end, c1, c2) in Ink.bezier(simple) {
            p.addCurve(to: CGPoint(x: end.x + offset, y: end.y + offset),
                       control1: CGPoint(x: c1.x + offset, y: c1.y + offset),
                       control2: CGPoint(x: c2.x + offset, y: c2.y + offset))
        }
        return p
    }

    func sync(_ strokes: [Stroke]) {
        guard let root = layer else { return }
        let ids = Set(strokes.map(\.id))
        for (id, l) in layers where !ids.contains(id) { l.removeFromSuperlayer(); layers[id] = nil }
        for s in strokes where layers[s.id] == nil {
            let l = CAShapeLayer()
            l.path = Self.path(s.points, offset: CanvasGeometry.origin)
            l.strokeColor = NSColor(hex: s.colorHex).cgColor
            l.lineWidth = s.width
            l.fillColor = nil
            l.lineCap = .round
            l.lineJoin = .round
            root.insertSublayer(l, below: live)
            layers[s.id] = l
        }
    }

    func showLive(_ pts: [Point]?, color: String, width: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        live.path = pts.map { Self.path($0, offset: CanvasGeometry.origin) }
        live.strokeColor = NSColor(hex: color).cgColor
        live.lineWidth = width
        CATransaction.commit()
    }
}

/// 펜을 켜면 왼쪽 막대 옆에 뜨는 색·굵기 패널.
struct PenPanel: View {
    @ObservedObject var chrome: ChromeModel
    static let colors = ["#F05A38", "#E8564A", "#E9C46A", "#6FCF97", "#56C2C9", "#56A8F5", "#B48CF2", "#F28AB2", "#ECE7E2"]
    static let widths: [Double] = [1.5, 3, 5, 8, 12]

    var body: some View {
        if chrome.tool == .pen {
            VStack(alignment: .leading, spacing: 8) {
                Text("COLOR").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
                HStack(spacing: 6) {
                    ForEach(Self.colors, id: \.self) { hex in
                        Button { chrome.penColor = hex } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                .overlay(Circle().stroke(Color.white.opacity(chrome.penColor == hex ? 0.9 : 0.1), lineWidth: chrome.penColor == hex ? 2 : 1))
                        }
                        .buttonStyle(.plainHit)
                    }
                    Button { ColorPanelBridge.shared.open(current: chrome.penColor) { chrome.penColor = $0 } } label: {
                        Image(systemName: "eyedropper").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.black.opacity(0.7))
                            .frame(width: 18, height: 18).background(Circle().fill(Color(hex: chrome.penColor)))
                    }
                    .buttonStyle(.plainHit).help("Custom color")
                }
                Text("WIDTH").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
                HStack(spacing: 6) {
                    ForEach(Self.widths, id: \.self) { w in
                        Button { chrome.penWidth = w } label: {
                            Circle().fill(Color.symText).frame(width: max(3, w), height: max(3, w))
                                .frame(width: 32, height: 28)
                                .background(RoundedRectangle(cornerRadius: 7).fill(chrome.penWidth == w ? Color.symAccent.opacity(0.18) : Color.symRaised.opacity(0.6)))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(chrome.penWidth == w ? Color.symAccent : Color.clear))
                        }
                        .buttonStyle(.plainHit)
                    }
                }
            }
            .padding(12)
            .floatingCapsule(radius: 14)
            .fixedSize()
        }
    }
}
