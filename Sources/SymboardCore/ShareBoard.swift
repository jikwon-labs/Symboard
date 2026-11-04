import Foundation

/// 보기 전용 공유에서 브라우저가 앱과 같은 보드를 그리는 데 쓰는 작업공간 한 개(14차).
/// 콘솔의 폴더·인자·세션 id·계정, 이미지 파일 경로처럼 화면에 보이지 않는 값은 넣지 않는다.
/// 그룹 프레임과 다이어그램 화살표 길은 앱과 같은 규칙으로 여기서 계산해 보낸다(브라우저가 따로 흉내 내지 않게).
public struct ShareBoard: Codable, Equatable, Sendable {
    public struct Node: Codable, Equatable, Sendable {
        public var id: String
        public var kind: String
        public var x: Double, y: Double, w: Double, h: Double
        public var title: String
        public var role: String?
        public var text: String?
        public var colorHex: String?
        public var style: NodeStyle?
        public var checklist: [ChecklistItem]?
        public var kanban: [Column]?
        public var events: [CalendarEvent]?
        public var shape: ShapeSpec?
        /// 웹 타일이 지금 보이는 주소.
        public var url: String?
        /// 콘솔: CLI 글자 배지와 색.
        public var glyph: String?
        public var glyphHex: String?
        public var team: String?
        /// 접힌 그룹 안이라 보이지 않는다.
        public var hidden: Bool
    }

    public struct Column: Codable, Equatable, Sendable {
        public var title: String
        public var cards: [Card]
    }

    public struct Card: Codable, Equatable, Sendable {
        public var title: String
        public var done: Bool
        public var priority: String?
        public var due: Date?
    }

    public struct Group: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var colorHex: String
        public var collapsed: Bool
        public var count: Int
        /// 프레임 전체(머리 포함).
        public var x: Double, y: Double, w: Double, h: Double
        /// 그룹의 콘솔 id(머리의 "N running" 요약을 브라우저가 상태로 만든다).
        public var members: [String]
    }

    public struct Link: Codable, Equatable, Sendable {
        public var id: String
        /// 흐르는 점이 있는 곡선의 양 끝 상자.
        public var a: Rect
        public var b: Rect
        /// 에이전트가 띄운 콘솔 선(옅게).
        public var faint: Bool
        /// 다른 노드를 돌아가는 꺾은선(앱의 LinksView 와 같은 길). 없으면 브라우저가 a·b 곡선으로 그린다.
        public var points: [Point]? = nil
    }

    public struct Arrow: Codable, Equatable, Sendable {
        public var id: String
        public var points: [Point]
        public var labelAt: Point
        public var label: String?
        public var colorHex: String?
    }

    public var id: String
    public var name: String
    public var nodes: [Node]
    public var groups: [Group]
    public var links: [Link]
    public var arrows: [Arrow]
    public var strokes: [Stroke]
    public var viewport: Viewport

    public static let groupHeader = 30.0
    public static let groupPad = 14.0

    /// glyph: 콘솔 설정 → (글자, 색). 앱 쪽 CLI 목록을 쓴다.
    public static func make(_ ws: Workspace, lang: LanguageMode, glyph: (TerminalSpec) -> (String, String)) -> ShareBoard {
        var groups: [Group] = []
        var groupFrame: [UUID: (frame: Rect, body: Rect, collapsed: Bool)] = [:]
        var hiddenTeams = Set<UUID>()
        for team in ws.teams {
            let members = ws.nodes.filter { $0.teamID == team.id }
            guard let first = members.first else { continue }
            var minX = first.frame.x, minY = first.frame.y, maxX = first.frame.x + first.frame.w, maxY = first.frame.y + first.frame.h
            for m in members {
                minX = min(minX, m.frame.x); minY = min(minY, m.frame.y)
                maxX = max(maxX, m.frame.x + m.frame.w); maxY = max(maxY, m.frame.y + m.frame.h)
            }
            let collapsed = team.collapsed ?? false
            if collapsed { hiddenTeams.insert(team.id) }
            // 앱(CanvasView.layoutGroups)과 같은 크기.
            let frame = collapsed
                ? Rect(x: minX - groupPad, y: minY - groupPad - groupHeader, w: 320, h: groupHeader + 52)
                : Rect(x: minX - groupPad, y: minY - groupPad - groupHeader, w: maxX - minX + groupPad * 2, h: maxY - minY + groupPad * 2 + groupHeader)
            let body = Rect(x: frame.x, y: frame.y + groupHeader, w: frame.w, h: frame.h - groupHeader)
            groupFrame[team.id] = (frame, body, collapsed)
            groups.append(Group(id: team.id.uuidString, name: team.name, colorHex: team.colorHex, collapsed: collapsed,
                                count: members.count, x: frame.x, y: frame.y, w: frame.w, h: frame.h,
                                members: members.filter { $0.kind == .terminal }.map(\.id.uuidString)))
        }
        func isHidden(_ n: BoardNode) -> Bool { n.teamID.map { hiddenTeams.contains($0) } ?? false }

        let nodes = ws.nodes.map { n -> Node in
            let g = n.terminal.map(glyph)
            var url: String?
            if n.kind == .web, let tabs = n.tabs, !tabs.isEmpty {
                let i = n.activeTab ?? 0
                url = tabs.indices.contains(i) ? tabs[i] : tabs[0]
            }
            let columns = n.kanban?.map { col in
                Column(title: col.displayTitle(in: lang),
                       cards: col.allCards.map { Card(title: $0.title, done: $0.done, priority: $0.priority, due: $0.due) })
            }
            // 이미지 노드의 text 는 이 맥의 파일 경로라 보내지 않는다(그림은 따로 받는다).
            let text = n.kind == .image ? nil : n.text
            return Node(id: n.id.uuidString, kind: n.kind.rawValue, x: n.frame.x, y: n.frame.y, w: n.frame.w, h: n.frame.h,
                        title: n.displayTitle(in: lang), role: n.role, text: text, colorHex: n.colorHex, style: n.style,
                        checklist: n.checklist, kanban: columns, events: n.events, shape: n.shape, url: url,
                        glyph: g?.0, glyphHex: g?.1, team: n.teamID?.uuidString, hidden: isHidden(n))
        }

        // 앱(CanvasView.layoutLinks)과 같이: 그룹이면 접혔을 때 프레임, 펼쳤을 때 몸통에 붙는다. 숨은 노드는 선을 그리지 않는다.
        func rect(_ id: UUID) -> Rect? {
            if let g = groupFrame[id] { return g.collapsed ? g.frame : g.body }
            guard let n = ws.nodes.first(where: { $0.id == id }), !isHidden(n) else { return nil }
            return n.frame
        }
        let all = ws.links ?? []
        var links = all.filter { $0.style != "arrow" }.compactMap { l -> Link? in
            guard let a = rect(l.from), let b = rect(l.to) else { return nil }
            return Link(id: l.id.uuidString, a: a, b: b, faint: l.style == NodeLink.spawnedStyle)
        }
        if !links.isEmpty {
            let avoid = ws.nodes.filter { ArrowRouter.linkAvoids($0.kind) && !isHidden($0) }.map(\.frame)
            let edges = links.compactMap { l in UUID(uuidString: l.id).map { (id: $0, from: l.a, to: l.b) } }
            let routes = ArrowRouter.linkRoutes(edges, obstacles: avoid)
            for i in links.indices { links[i].points = UUID(uuidString: links[i].id).flatMap { routes[$0] } }
        }
        let arrowLinks = all.filter { $0.style == "arrow" }
        var arrows: [Arrow] = []
        if !arrowLinks.isEmpty {
            let edges = arrowLinks.compactMap { l -> (id: UUID, from: Rect, to: Rect)? in
                guard let a = rect(l.from), let b = rect(l.to) else { return nil }
                return (l.id, a, b)
            }
            // 보드의 도형이 장애물, 다른 도형을 품은 도형(다이어그램 그룹 테두리)은 뺀다.
            let shapes = ws.nodes.filter { $0.kind == .shape && !isHidden($0) }.map(\.frame)
            let obstacles = shapes.filter { r in !shapes.contains { $0 != r && contains(r, $0) } }
            let routes = ArrowRouter.route(edges, obstacles: obstacles)
            for l in arrowLinks {
                guard let r = routes[l.id] else { continue }
                arrows.append(Arrow(id: l.id.uuidString, points: r.points, labelAt: r.label, label: l.label, colorHex: l.colorHex))
            }
        }
        return ShareBoard(id: ws.id.uuidString, name: ws.name, nodes: nodes, groups: groups, links: links, arrows: arrows,
                          strokes: ws.strokes, viewport: ws.viewport)
    }

    static func contains(_ outer: Rect, _ inner: Rect) -> Bool {
        inner.x >= outer.x && inner.y >= outer.y && inner.x + inner.w <= outer.x + outer.w && inner.y + inner.h <= outer.y + outer.h
    }

    /// 브라우저로 보내는 JSON(날짜는 ISO 8601). 키 순서를 고정한다: 같은 보드면 같은 글이어야
    /// 서버가 "바뀌었을 때만" 보낼 수 있다(순서가 매번 달라 1초마다 다시 보내고, 브라우저가 다시 그리며 입력 포커스를 잃었다).
    public func json() -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
