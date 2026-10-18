import AppKit
import SwiftUI
import SymboardCore

/// 글자·스티키·이미지를 고르면 왼쪽 도구 막대 옆에 뜨는 속성 패널.
struct SelectionPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var chrome: ChromeModel
    let c: MainWindowController

    static let paper = ["#C9A227", "#C8662E", "#B23A3A", "#3E8E5A", "#2E8C88", "#3F63C9", "#7A45C2", "#2B2926"]
    static let ink = ["#ECE7E2", "#F05A38", "#E9C46A", "#6FCF97", "#56A8F5", "#B48CF2"]
    static let fills = ["#3A2420", "#3A3220", "#203A2A", "#20303A", "#2E243A", "#2B2926"]

    var node: BoardNode? {
        guard let id = chrome.selectedNodeID, let n = model.node(id), NodeView.isHeaderless(n.kind) else { return nil }
        return n
    }

    var body: some View {
        if let n = node {
            VStack(alignment: .leading, spacing: 10) {
                switch n.kind {
                case .sticky:
                    section("PAPER") { swatches(Self.paper, current: n.colorHex) { hex in update(n.id) { $0.colorHex = hex } } }
                case .text:
                    let st = n.style ?? NodeStyle()
                    section("COLOR") { swatches(Self.ink, current: st.textColorHex ?? Self.ink[0]) { hex in style(n.id) { $0.textColorHex = hex } } }
                    section("FONT") {
                        HStack(spacing: 4) {
                            ForEach(TextStyleFonts.fonts, id: \.0) { f in
                                chip(f.1, on: (st.font ?? "hand") == f.0) { style(n.id) { $0.font = f.0 } }
                            }
                        }
                    }
                    section("SIZE") {
                        HStack(spacing: 4) {
                            ForEach(TextStyleFonts.sizes, id: \.0) { sz in
                                chip(sz.0, on: (st.fontSize ?? 28) == sz.1) { style(n.id) { $0.fontSize = sz.1 } }
                            }
                            Divider().frame(height: 18)
                            ForEach([("left", "text.alignleft"), ("center", "text.aligncenter"), ("right", "text.alignright")], id: \.0) { a in
                                Button { style(n.id) { $0.align = a.0 } } label: { Image(systemName: a.1) }.tip("Align \(a.0)")
                                    .buttonStyle(ChipStyle(on: (st.align ?? "left") == a.0))
                            }
                        }
                    }
                    section("OPACITY") {
                        Slider(value: Binding(get: { st.opacity ?? 1 }, set: { v in style(n.id) { $0.opacity = v } }), in: 0.2...1)
                            .tint(Color.symAccent).frame(width: 200)
                    }
                case .shape:
                    let sp = n.shape ?? ShapeSpec()
                    let st = n.style ?? NodeStyle()
                    section("STROKE") { swatches(Self.ink, current: sp.strokeHex) { hex in shape(n.id) { $0.strokeHex = hex } } }
                    if sp.kind != "arrow" {
                        section("BACKGROUND") {
                            HStack(spacing: 6) {
                                Button { shape(n.id) { $0.fillHex = nil } } label: {
                                    Image(systemName: "nosign").font(.system(size: 11)).frame(width: 18, height: 18)
                                        .foregroundStyle(sp.fillHex == nil ? Color.symAccent : Color.symDim)
                                }
                                .buttonStyle(.plainHit)
                                swatches(Self.fills, current: sp.fillHex) { hex in shape(n.id) { $0.fillHex = hex } }
                            }
                        }
                    }
                    section("WIDTH · STYLE") {
                        HStack(spacing: 4) {
                            ForEach([(1.0, "S"), (2.0, "M"), (4.0, "L")], id: \.0) { w in
                                chip(w.1, on: sp.strokeWidth == w.0) { shape(n.id) { $0.strokeWidth = w.0 } }
                            }
                            Divider().frame(height: 18)
                            ForEach([("solid", "line.diagonal"), ("dashed", "line.3.horizontal"), ("dotted", "ellipsis")], id: \.0) { d in
                                Button { shape(n.id) { $0.dash = d.0 } } label: { Image(systemName: d.1) }.buttonStyle(ChipStyle(on: sp.dash == d.0)).tip(d.0)
                            }
                        }
                    }
                    section("SLOPPINESS · EDGES") {
                        HStack(spacing: 4) {
                            ForEach([(0.0, "Neat"), (1.0, "Sketch"), (2.0, "Rough")], id: \.0) { r in
                                chip(r.1, on: sp.roughness == r.0) { shape(n.id) { $0.roughness = r.0 } }
                            }
                            if sp.kind == "rect" {
                                Divider().frame(height: 18)
                                Button { shape(n.id) { $0.cornerRadius = 0 } } label: { Image(systemName: "square") }.buttonStyle(ChipStyle(on: sp.cornerRadius == 0)).tip("Square corners")
                                Button { shape(n.id) { $0.cornerRadius = 14 } } label: { Image(systemName: "app") }.buttonStyle(ChipStyle(on: sp.cornerRadius > 0)).tip("Rounded corners")
                            }
                        }
                    }
                    if sp.kind != "arrow" {
                        section("TEXT") {
                            HStack(spacing: 4) {
                                ForEach(TextStyleFonts.sizes, id: \.0) { sz in chip(sz.0, on: (st.fontSize ?? 20) == sz.1) { style(n.id) { $0.fontSize = sz.1 } } }
                            }
                            HStack(spacing: 4) {
                                ForEach(TextStyleFonts.fonts, id: \.0) { f in chip(f.1, on: (st.font ?? "hand") == f.0) { style(n.id) { $0.font = f.0 } } }
                            }
                        }
                    }
                    section("OPACITY") {
                        Slider(value: Binding(get: { st.opacity ?? 1 }, set: { v in style(n.id) { $0.opacity = v } }), in: 0.2...1)
                            .tint(Color.symAccent).frame(width: 200)
                    }
                default:
                    EmptyView()
                }
                if n.kind != .image { Divider().overlay(Color.symBorder) }
                HStack(spacing: 6) {
                    action("square.3.layers.3d.top.filled", "Bring to front") { model.moveLayer(n.id, toFront: true) }
                    action("square.3.layers.3d.bottom.filled", "Send to back") { model.moveLayer(n.id, toFront: false) }
                    action("plus.square.on.square", "Duplicate") { c.duplicateSelection() }
                    action("trash", "Delete") { c.deleteSelection() }
                }
            }
            .padding(12)
            .floatingCapsule(radius: 14)
            .fixedSize()
        }
    }

    func update(_ id: UUID, _ body: (inout BoardNode) -> Void) {
        model.mutateNode(id, body)
        c.currentCanvas?.nodeViews[id]?.syncFromModel()
    }

    func shape(_ id: UUID, _ body: (inout ShapeSpec) -> Void) {
        update(id) { n in
            var s = n.shape ?? ShapeSpec()
            body(&s)
            n.shape = s
        }
    }

    func style(_ id: UUID, _ body: (inout NodeStyle) -> Void) {
        update(id) { n in
            var s = n.style ?? NodeStyle()
            body(&s)
            n.style = s
        }
    }

    func section<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
            content()
        }
    }

    func swatches(_ colors: [String], current: String?, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(colors, id: \.self) { hex in
                Button { pick(hex) } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.white.opacity(current?.uppercased() == hex.uppercased() ? 0.9 : 0.12), lineWidth: current?.uppercased() == hex.uppercased() ? 2 : 1))
                }
                .buttonStyle(.plainHit)
            }
            Button { ColorPanelBridge.shared.open(current: current ?? colors[0], pick: pick) } label: {
                Image(systemName: "eyedropper").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(hex: current ?? colors[0])))
            }
            .buttonStyle(.plainHit)
            .tip("Custom color")
        }
    }

    func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(ChipStyle(on: on))
    }

    func action(_ symbol: String, _ tip: String, run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: symbol).frame(width: 34, height: 28) }
            .buttonStyle(ChipStyle(on: false))
            .tip(tip)
    }
}

extension View {
    /// 단추용: 마우스를 올리면 보이는 설명 + 접근성 이름. SwiftUI 단추 이름은 접근성 도구에 따라 안 읽히는 일이 있어,
    /// 같은 자리에 이름 붙은 AppKit 단추 대역(AccessibilityPressProxy)을 겹치고 원래 단추는 접근성에서 숨긴다.
    func tip(_ text: String) -> some View {
        help(text).accessibilityHidden(true).overlay(AccessibilityPressProxy(label: text))
    }

    /// 글자 단추용: 설명 없이 접근성 이름만(보이는 글자와 같은 이름).
    func axName(_ text: String) -> some View {
        accessibilityHidden(true).overlay(AccessibilityPressProxy(label: text))
    }

    /// 단추가 아닌 것(메뉴·글자)용: 설명 + 접근성 이름.
    func hint(_ text: String) -> some View { help(text).accessibilityLabel(text) }
}

/// 눌림을 받지 않는(hitTest nil) 투명 AppKit 뷰. 접근성에는 이름 있는 단추로 보이고,
/// 접근성 "누르기" 가 오면 자기 가운데를 실제 클릭처럼 눌러 밑의 SwiftUI 단추가 받게 한다.
struct AccessibilityPressProxy: NSViewRepresentable {
    var label: String
    func makeNSView(context: Context) -> ProxyView { ProxyView() }
    func updateNSView(_ v: ProxyView, context: Context) { v.label = label }

    final class ProxyView: NSView {
        var label = ""
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        // 마우스는 통과시키지만 접근성 위치 찾기에서는 자기 자신이 잡혀야 한다(안 그러면 그 자리에 창이 없는 것처럼 보인다).
        override func accessibilityHitTest(_ point: NSPoint) -> Any? { self }
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { label }
        override func accessibilityPerformPress() -> Bool {
            guard let w = window else { return false }
            let p = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(e, atStart: false)
                }
            }
            return true
        }
    }
}

/// .plain 과 같은 모양이지만 글자·아이콘 사이 빈틈까지 라벨 사각형 전체를 누를 수 있다.
/// .plain 은 그려진 부분만 눌려서, 축소된 캔버스에서 "+ New" 같은 작은 단추가 자주 빗나갔다.
struct PlainHitStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PlainHitStyle {
    static var plainHit: PlainHitStyle { PlainHitStyle() }
}

struct ChipStyle: ButtonStyle {
    var on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(on ? Color.symAccent : Color.symText.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.symAccent.opacity(0.14) : Color.symRaised.opacity(configuration.isPressed ? 1 : 0.7)))
    }
}

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

/// 시스템 색 패널로 사용자 색을 고른다.
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var pick: ((String) -> Void)?

    func open(current: String, pick: @escaping (String) -> Void) {
        self.pick = pick
        let p = NSColorPanel.shared
        p.showsAlpha = false
        p.color = NSColor(hex: current)
        p.setTarget(self)
        p.setAction(#selector(changed(_:)))
        p.orderFront(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) { pick?(sender.color.hexString) }
}
