import AppKit
import SwiftUI
import SymboardCore

/// 손그림풍 선 만들기. 같은 노드는 같은 씨앗을 써서 다시 그려도 모양이 그대로다.
struct RoughPen {
    var seed: UInt64
    var roughness: Double

    private mutating func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) & 0xFFFF) / Double(0xFFFF) - 0.5
    }

    /// 두 점 사이를 살짝 휘게 그린다.
    mutating func line(_ a: CGPoint, _ b: CGPoint, into p: inout Path) {
        let len = hypot(b.x - a.x, b.y - a.y)
        let r = roughness * min(2.5, len / 60 + 0.6)
        let j = { (v: Double) in CGFloat(v * r * 2) }
        let s = CGPoint(x: a.x + j(next()), y: a.y + j(next()))
        let e = CGPoint(x: b.x + j(next()), y: b.y + j(next()))
        let mid = CGPoint(x: (s.x + e.x) / 2 + j(next()) * 1.6, y: (s.y + e.y) / 2 + j(next()) * 1.6)
        p.move(to: s)
        p.addQuadCurve(to: e, control: mid)
    }

    /// 닫힌 다각형. 거칠기가 있으면 두 번 겹쳐 그려 손으로 그린 느낌을 낸다.
    mutating func polygon(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard pts.count > 1 else { return p }
        if roughness == 0 {
            p.addLines(pts); p.closeSubpath(); return p
        }
        for _ in 0..<2 {
            for i in pts.indices { line(pts[i], pts[(i + 1) % pts.count], into: &p) }
        }
        return p
    }

    mutating func ellipse(in r: CGRect) -> Path {
        if roughness == 0 { return Path(ellipseIn: r) }
        var p = Path()
        for pass in 0..<2 {
            let n = 28
            let k = roughness * 3
            var first: CGPoint?
            for i in 0...n {
                let t = Double(i) / Double(n) * 2 * .pi + Double(pass) * 0.3
                let dx = CGFloat(next() * k), dy = CGFloat(next() * k)
                let pt = CGPoint(x: r.midX + (r.width / 2 + dx) * CGFloat(cos(t)),
                                 y: r.midY + (r.height / 2 + dy) * CGFloat(sin(t)))
                if first == nil { p.move(to: pt); first = pt } else { p.addLine(to: pt) }
            }
        }
        return p
    }
}

struct ShapeNodeView: View {
    @ObservedObject var box: NodeBox

    var spec: ShapeSpec { box.node.shape ?? ShapeSpec() }
    var style: NodeStyle { box.node.style ?? NodeStyle(fontSize: 20, font: "hand", align: "center") }

    var seed: UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in box.node.id.uuidString.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    func outline(in size: CGSize) -> Path {
        let inset = CGFloat(spec.strokeWidth) + 4
        let r = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        var pen = RoughPen(seed: seed, roughness: spec.roughness)
        switch spec.kind {
        case "ellipse": return pen.ellipse(in: r)
        case "diamond": return pen.polygon([CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)])
        case "arrow":
            var p = Path()
            let y = r.midY
            pen.line(CGPoint(x: r.minX, y: y), CGPoint(x: r.maxX, y: y), into: &p)
            let head = min(18, r.width / 4)
            pen.line(CGPoint(x: r.maxX, y: y), CGPoint(x: r.maxX - head, y: y - head * 0.6), into: &p)
            pen.line(CGPoint(x: r.maxX, y: y), CGPoint(x: r.maxX - head, y: y + head * 0.6), into: &p)
            return p
        default:
            if spec.roughness == 0 {
                return Path(roundedRect: r, cornerRadius: CGFloat(spec.cornerRadius))
            }
            let c = min(CGFloat(spec.cornerRadius), min(r.width, r.height) / 3)
            // 둥근 모서리는 모서리를 깎은 팔각형으로 흉내 낸다.
            let pts = c > 2 ? [CGPoint(x: r.minX + c, y: r.minY), CGPoint(x: r.maxX - c, y: r.minY), CGPoint(x: r.maxX, y: r.minY + c),
                               CGPoint(x: r.maxX, y: r.maxY - c), CGPoint(x: r.maxX - c, y: r.maxY), CGPoint(x: r.minX + c, y: r.maxY),
                               CGPoint(x: r.minX, y: r.maxY - c), CGPoint(x: r.minX, y: r.minY + c)]
                            : [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            return pen.polygon(pts)
        }
    }

    var dash: [CGFloat] {
        switch spec.dash {
        case "dashed": return [CGFloat(spec.strokeWidth) * 4, CGFloat(spec.strokeWidth) * 3]
        case "dotted": return [1, CGFloat(spec.strokeWidth) * 2.5]
        default: return []
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let fill = spec.fillHex, spec.kind != "arrow" {
                    // 채움은 반듯한 모양으로 깔고 선만 흔든다.
                    fillShape(geo.size).fill(Color(hex: fill).opacity(0.85))
                }
                outline(in: geo.size)
                    .stroke(Color(hex: spec.strokeHex), style: StrokeStyle(lineWidth: CGFloat(spec.strokeWidth), lineCap: .round, lineJoin: .round, dash: dash))
                if spec.kind != "arrow" {
                    TextEditor(text: Binding(get: { box.node.text ?? "" }, set: { v in box.update { $0.text = v } }))
                        .font(Font(TextStyleFonts.font(style)))
                        .multilineTextAlignment(TextStyleFonts.alignment(style))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .foregroundStyle(Color(hex: style.textColorHex ?? "#ECE7E2"))
                        .frame(width: geo.size.width * (spec.kind == "rect" ? 0.86 : 0.68), height: textHeight(geo.size))
                }
            }
            .opacity(style.opacity ?? 1)
        }
    }

    /// 줄바꿈까지 어림해서 글 높이를 정한다(가운데 정렬용).
    func textHeight(_ size: CGSize) -> CGFloat {
        let fs = CGFloat(style.fontSize ?? 20)
        let perLine = max(4, Int(size.width * (spec.kind == "rect" ? 0.86 : 0.68) / (fs * 0.55)))
        let lines = (box.node.text ?? "").split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(perLine)))) }
        return min(size.height * 0.86, CGFloat(max(lines, 1)) * fs * 1.4 + 10)
    }

    func fillShape(_ size: CGSize) -> Path {
        let inset = CGFloat(spec.strokeWidth) + 4
        let r = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        switch spec.kind {
        case "ellipse": return Path(ellipseIn: r)
        case "diamond":
            var p = Path()
            p.addLines([CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)])
            p.closeSubpath(); return p
        default: return Path(roundedRect: r, cornerRadius: CGFloat(spec.cornerRadius))
        }
    }
}

/// 왼쪽 막대 도형 버튼의 팝오버.
struct ShapePicker: View {
    var pick: (String) -> Void
    var body: some View {
        HStack(spacing: 4) {
            ForEach([("rect", "rectangle"), ("ellipse", "circle"), ("diamond", "diamond"), ("arrow", "arrow.right")], id: \.0) { k in
                Button { pick(k.0) } label: { Image(systemName: k.1).font(.system(size: 16)).frame(width: 40, height: 36) }
                    .buttonStyle(ChipStyle(on: false))
                    .help(k.0.capitalized)
            }
        }
        .padding(8)
        .background(Color.symSurface)
    }
}
