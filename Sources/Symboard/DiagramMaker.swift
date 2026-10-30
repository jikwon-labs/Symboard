import AppKit
import SwiftUI
import SymboardCore

/// 다이어그램 만들기: CLI 에 JSON 을 받아 보드 위에 도형·화살표·그룹·제목을 차례로 놓는다.
@MainActor
final class DiagramMaker: ObservableObject {
    unowned let c: MainWindowController
    @Published var open = false
    @Published var agent = "claude"
    @Published var style = "Ink"
    @Published var describe = ""
    /// 그리는 중이면 CLI 이름.
    @Published var drawing: String?
    @Published var error: String?
    private var job: AgentJob?
    private var placeholders: [UUID] = []

    init(c: MainWindowController) { self.c = c }

    static let palette = ["#56A8F5", "#6FCF97", "#E9C46A", "#B48CF2", "#F28AB2", "#56C2C9"]

    func generate(kind: String?) {
        guard drawing == nil else { return }
        let prompt = DiagramSpec.prompt(kind: kind, describe: kind == nil ? describe : nil, repoName: (c.projectPath as NSString).lastPathComponent)
        open = false
        error = nil
        drawing = AgentCatalog.choice(id: agent)?.name ?? agent
        let center = c.scrollView.visibleCenter
        placeholders = placeStarter("Flow", at: center, empty: true)
        let j = AgentJob(.init(agent: agent, prompt: prompt, cwd: c.projectPath, tools: "Read,Glob,Grep"))
        job = j
        j.onDone = { [weak self] text, ok in
            guard let self else { return }
            self.drawing = nil
            self.removePlaceholders()
            guard ok, let spec = DiagramSpec.parse(text) else {
                self.error = "The CLI did not return a diagram."
                self.c.chrome.flash("No diagram came back")
                return
            }
            self.draw(spec, center: center)
        }
        j.start()
    }

    func cancel() {
        job?.cancel()
        job = nil
        drawing = nil
        removePlaceholders()
    }

    private func removePlaceholders() {
        for id in placeholders { c.model.removeNode(id) }
        placeholders = []
    }

    /// 사양을 보드에 그린다. 그룹 → 제목 → 노드 → 화살표 순서로 조금씩 시차를 두고 나타난다.
    /// area 를 주면(보드 도구, 9차) 그 칸 안에 그린다. 칸은 `footprint` 크기로 미리 찾아 둔 빈 자리.
    /// completion 은 마지막 화살표까지 놓은 뒤 불린다(그 전에 다른 노드 자리를 찾으면 아직 없는 상자와 겹친다).
    func draw(_ spec: DiagramSpec, center: Point, area given: Rect? = nil, completion: (() -> Void)? = nil) {
        let est = spec.layout(origin: Point(x: 0, y: 0), nodeW: 250, nodeH: 120)
        let maxX = est.nodes.values.map { $0.x + $0.w }.max() ?? 0
        let maxY = est.nodes.values.map { $0.y + $0.h }.max() ?? 0
        var origin = Point(x: center.x - maxX / 2, y: center.y - maxY / 2)
        if let given {
            origin = Point(x: given.x + 40, y: given.y + 120)
        } else {
            // 원본은 빈 캔버스에 그린다. 그 자리에 이미 노드가 있으면 보드 오른쪽 빈 곳으로 옮긴다(겹쳐 그리지 않게).
            let area = Rect(x: origin.x - 40, y: origin.y - 120, w: maxX + 80, h: maxY + 160)
            let others = c.model.selectedWorkspace.nodes.map(\.frame)
            if others.contains(where: { $0.x < area.x + area.w && $0.x + $0.w > area.x && $0.y < area.y + area.h && $0.y + $0.h > area.y }) {
                let right = others.map { $0.x + $0.w }.max() ?? 0
                origin = Point(x: right + 200, y: center.y - maxY / 2)
            }
        }
        let lay = spec.layout(origin: origin, nodeW: 250, nodeH: 120)
        let wsID = c.model.selectedWorkspace.id
        var created: [String: UUID] = [:]
        // 이번에 그린 노드들. 끝나면 화면을 이것들에만 맞춘다(원본: 다이어그램만 담는다).
        var madeIDs: [UUID] = []
        var step = 0.0
        func later(_ body: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + step, execute: body)
            step += 0.09
        }
        let colorful = style == "Colorful"
        for (i, g) in (spec.groups ?? []).enumerated() {
            guard let r = lay.groups[g.id] else { continue }
            let tint = colorful ? Self.palette[i % Self.palette.count] : "#8F8882"
            later {
                self.c.addNode(kind: .shape, size: CGSize(width: r.w, height: r.h), title: g.label, at: Point(x: r.x, y: r.y)) {
                    $0.shape = ShapeSpec(kind: "rect", strokeHex: tint, fillHex: colorful ? Self.dim(tint) : nil, strokeWidth: 1, dash: "dashed", roughness: 1, cornerRadius: 14)
                    $0.text = ""
                    $0.role = Self.role
                    madeIDs.append($0.id)
                }
                self.c.addNode(kind: .text, size: CGSize(width: max(140, r.w - 20), height: 40), title: g.label, at: Point(x: r.x + 18, y: r.y + 8)) {
                    $0.text = g.label.uppercased()
                    $0.style = NodeStyle(fontSize: 18, font: "hand", textColorHex: tint)
                    $0.role = Self.role
                    madeIDs.append($0.id)
                }
            }
        }
        later {
            // 제목 칸은 실제 글꼴로 잰 크기. 글자 수로 어림하면 한글처럼 넓은 글자가 줄을 넘겨 둘째 줄이 잘렸다.
            let ts = Self.titleSize(spec.title)
            self.c.addNode(kind: .text, size: ts, title: spec.title, at: Point(x: lay.title.x, y: lay.title.y - 60 - (ts.height - 70))) {
                $0.text = spec.title
                $0.style = NodeStyle(fontSize: 40, font: "hand")
                $0.role = Self.role
                madeIDs.append($0.id)
            }
        }
        let groupIndex = Dictionary(uniqueKeysWithValues: (spec.groups ?? []).enumerated().map { ($0.element.id, $0.offset) })
        // 원본처럼 노드가 제목 아래 한 줄로 먼저 나타났다가 제자리로 미끄러진다.
        let perRow = 6
        for (i, n) in spec.nodes.enumerated() {
            guard let r = lay.nodes[n.id] else { continue }
            let tint = colorful ? Self.palette[(groupIndex[n.group ?? ""] ?? 0) % Self.palette.count] : "#ECE7E2"
            let start = Rect(x: lay.title.x + Double(i % perRow) * (r.w + 24), y: lay.title.y + 40 + Double(i / perRow) * (r.h + 24), w: r.w, h: r.h)
            later {
                var newID: UUID?
                self.c.addNode(kind: .shape, size: CGSize(width: r.w, height: r.h), title: n.label, at: Point(x: r.x, y: r.y)) {
                    newID = $0.id
                    self.c.currentCanvas?.quietAppear.insert($0.id)
                    $0.shape = ShapeSpec(kind: n.shape == "ellipse" ? "ellipse" : "rect", strokeHex: tint, fillHex: colorful ? Self.dim(tint) : nil,
                                         strokeWidth: 2, dash: "solid", roughness: 1, cornerRadius: 14)
                    $0.text = [n.label, n.sub].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
                    $0.style = NodeStyle(fontSize: 18, font: "hand", textColorHex: "#ECE7E2", align: "center")
                    $0.role = Self.role
                    madeIDs.append($0.id)
                }
                if let id = newID {
                    created[n.id] = id
                    self.c.currentCanvas?.slideNode(id, from: start)
                }
            }
        }
        // 마지막 노드가 자리에 닿은 뒤 화살표를 잇고 화면을 맞춘다.
        step += 0.45
        later {
            self.c.model.mutateWorkspace(wsID) { ws in
                var links = ws.links ?? []
                for e in spec.edges {
                    guard let a = created[e.from], let b = created[e.to] else { continue }
                    links.append(NodeLink(from: a, to: b, style: "arrow", label: e.label, colorHex: colorful ? "#ECE7E2" : "#ECE7E2"))
                }
                ws.links = links
            }
            self.c.currentCanvas?.select(nil)
            self.c.currentCanvas?.layoutLinks()
            let frames = madeIDs.compactMap { self.c.model.node($0)?.frame }
            if frames.isEmpty { self.c.zoomToFit(nil) } else { self.c.zoomToFit(frames: frames) }
            completion?()
        }
    }

    /// 다이어그램이 차지할 크기(제목·그룹 여백 포함). draw 의 area 와 같은 셈.
    static func footprint(_ spec: DiagramSpec) -> CGSize {
        let est = spec.layout(origin: Point(x: 0, y: 0), nodeW: 250, nodeH: 120)
        let maxX = est.nodes.values.map { $0.x + $0.w }.max() ?? 0
        let maxY = est.nodes.values.map { $0.y + $0.h }.max() ?? 0
        let ts = titleSize(spec.title)
        return CGSize(width: max(maxX, ts.width) + 80, height: maxY + 160 + (ts.height - 70))
    }

    /// 제목 글(손글씨 40pt)이 들어갈 칸. 한 줄로 1100pt 까지 넓히고, 넘으면 줄을 바꾸고 높이를 늘린다.
    static func titleSize(_ title: String) -> CGSize {
        let font = TextStyleFonts.font(NodeStyle(fontSize: 40, font: "hand"))
        let r = (title as NSString).boundingRect(with: NSSize(width: 1100, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                 attributes: [.font: font])
        return CGSize(width: max(560, ceil(r.width) + 60), height: max(70, ceil(r.height) + 24))
    }

    /// 다이어그램이 만든 노드 표시(BoardNode.role). 고르면 노드 편집 패널이 뜬다.
    static let role = "diagram"

    static func dim(_ hex: String) -> String {
        let c = NSColor(hex: hex).usingColorSpace(.sRGB)!
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255 * 0.22), Int(c.greenComponent * 255 * 0.22), Int(c.blueComponent * 255 * 0.22))
    }

    /// 시작 도형: 에이전트 없이 바로 놓는 틀. empty 면 글 없는 자리표시.
    @discardableResult
    func placeStarter(_ kind: String, at center: Point, empty: Bool = false) -> [UUID] {
        let spec: DiagramSpec
        switch kind {
        case "Steps":
            spec = DiagramSpec(title: "Steps", nodes: (1...4).map { .init(id: "s\($0)", label: "Step \($0)") },
                               edges: (1...3).map { .init(from: "s\($0)", to: "s\($0 + 1)") })
        case "Branch":
            spec = DiagramSpec(title: "Decision", nodes: [.init(id: "q", label: "Question?"), .init(id: "y", label: "Yes"), .init(id: "n", label: "No")],
                               edges: [.init(from: "q", to: "y", label: "yes"), .init(from: "q", to: "n", label: "no")])
        case "Mind map":
            spec = DiagramSpec(title: "Mind map", nodes: [.init(id: "c", label: "Idea", shape: "ellipse")] + (1...4).map { .init(id: "b\($0)", label: "Branch \($0)") },
                               edges: (1...4).map { .init(from: "c", to: "b\($0)") })
        default:
            spec = DiagramSpec(title: "Flow", nodes: [.init(id: "a", label: "Start"), .init(id: "b", label: "Then"), .init(id: "c", label: "Result")],
                               edges: [.init(from: "a", to: "c"), .init(from: "b", to: "c")])
        }
        if !empty { draw(spec, center: center); open = false; return [] }
        // 자리표시: 글 없는 흐린 상자와 화살표.
        let lay = spec.layout(origin: Point(x: center.x - 270, y: center.y - 200), nodeW: 200, nodeH: 90)
        var ids: [String: UUID] = [:]
        for n in spec.nodes {
            guard let r = lay.nodes[n.id] else { continue }
            c.addNode(kind: .shape, size: CGSize(width: r.w, height: r.h), title: "placeholder", at: Point(x: r.x, y: r.y)) {
                $0.shape = ShapeSpec(kind: "rect", strokeHex: "#5A5550", strokeWidth: 2, roughness: 1, cornerRadius: 14)
                $0.text = ""
            }
            ids[n.id] = c.model.selectedWorkspace.nodes.last?.id
        }
        let wsID = c.model.selectedWorkspace.id
        c.model.mutateWorkspace(wsID) { ws in
            ws.links = (ws.links ?? []) + spec.edges.compactMap { e in
                guard let a = ids[e.from], let b = ids[e.to] else { return nil }
                return NodeLink(from: a, to: b, style: "arrow", colorHex: "#5A5550")
            }
        }
        c.currentCanvas?.select(nil)
        c.currentCanvas?.layoutLinks()
        return Array(ids.values)
    }
}

struct DiagramPopover: View {
    @ObservedObject var maker: DiagramMaker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("MODEL")
            HStack(spacing: 6) {
                ForEach(["claude", "codex"], id: \.self) { a in
                    Button { maker.agent = a } label: { AgentBadge(choice: AgentCatalog.choice(id: a)!, size: 26) }
                        .buttonStyle(.plainHit)
                        .overlay(Circle().stroke(maker.agent == a ? Color.symAccent : .clear, lineWidth: 1.5).padding(-4))
                        .tip(AgentCatalog.choice(id: a)!.name)
                }
            }
            HStack {
                label("STYLE")
                Spacer()
                ForEach(["Ink", "Colorful"], id: \.self) { s in Button(s) { maker.style = s }.buttonStyle(ChipStyle(on: maker.style == s)) }
            }
            label("FROM YOUR PROJECT")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(DiagramSpec.kinds, id: \.id) { k in
                    Button { maker.generate(kind: k.id) } label: {
                        Label(k.title, systemImage: k.icon).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
                            .foregroundStyle(Color.symText)
                    }
                    .buttonStyle(.plainHit)
                }
            }
            HStack(spacing: 6) {
                TextField("", text: $maker.describe, prompt: Text("Describe a diagram...").foregroundColor(Color.symDim))
                    .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.symText)
                    .autoFocus()
                    .onSubmit { if !maker.describe.isEmpty { maker.generate(kind: nil) } }
                Button("Generate") { maker.generate(kind: nil) }.buttonStyle(PillButtonStyle(prominent: !maker.describe.isEmpty)).axName("Generate")
                    .disabled(maker.describe.isEmpty)
            }
            .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised.opacity(0.6)))
            label("STARTER SHAPES")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach([("Flow", "arrow.down"), ("Steps", "list.number"), ("Branch", "arrow.triangle.branch"), ("Mind map", "circle.hexagongrid")], id: \.0) { s in
                    Button { maker.placeStarter(s.0, at: maker.c.scrollView.visibleCenter) } label: {
                        Label(s.0, systemImage: s.1).font(.system(size: 12)).frame(maxWidth: .infinity)
                            .padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 9).stroke(Color.symBorder))
                            .foregroundStyle(Color.symText)
                    }
                    .buttonStyle(.plainHit)
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(Color.symSurface)
    }

    func label(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
    }
}

/// 위쪽 가운데 "<CLI> is drawing ×" 칩.
struct DrawingChip: View {
    @ObservedObject var maker: DiagramMaker
    var body: some View {
        if let who = maker.drawing {
            HStack(spacing: 8) {
                Circle().fill(Color.symAccent).frame(width: 6, height: 6)
                Text("\(who) is drawing").font(.system(size: 12)).foregroundStyle(Color.symText)
                Button { maker.cancel() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Cancel diagram")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .floatingCapsule(radius: 12)
            .fixedSize()
        }
    }
}
