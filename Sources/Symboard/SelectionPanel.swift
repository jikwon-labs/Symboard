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
                                Button { style(n.id) { $0.align = a.0 } } label: { Image(systemName: a.1) }
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
                                .buttonStyle(.plain)
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
                                Button { shape(n.id) { $0.dash = d.0 } } label: { Image(systemName: d.1) }.buttonStyle(ChipStyle(on: sp.dash == d.0)).help(d.0)
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
                                Button { shape(n.id) { $0.cornerRadius = 0 } } label: { Image(systemName: "square") }.buttonStyle(ChipStyle(on: sp.cornerRadius == 0))
                                Button { shape(n.id) { $0.cornerRadius = 14 } } label: { Image(systemName: "app") }.buttonStyle(ChipStyle(on: sp.cornerRadius > 0))
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
                .buttonStyle(.plain)
            }
            Button { ColorPanelBridge.shared.open(current: current ?? colors[0], pick: pick) } label: {
                Image(systemName: "eyedropper").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(hex: current ?? colors[0])))
            }
            .buttonStyle(.plain)
            .help("Custom color")
        }
    }

    func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(ChipStyle(on: on))
    }

    func action(_ symbol: String, _ tip: String, run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: symbol).frame(width: 34, height: 28) }
            .buttonStyle(ChipStyle(on: false))
            .help(tip)
    }
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
