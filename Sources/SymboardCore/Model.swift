import Foundation

/// 캔버스 좌표계의 사각형. 원점은 캔버스 중앙, y 는 아래로 증가한다.
public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

public struct Point: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum NodeKind: String, Codable, Sendable, CaseIterable {
    case terminal
    case sticky
    case text
    case checklist
    case kanban
    case image
    case web
    case git
    case file
    case orchestrator
    case calendar
    case shape
}

/// 글자·도형 노드의 겉모양. 비어 있는 값은 노드 종류의 기본값을 쓴다.
public struct NodeStyle: Codable, Equatable, Sendable {
    public var fontSize: Double?
    /// "hand" 손글씨, "sans", "serif", "mono".
    public var font: String?
    public var textColorHex: String?
    public var align: String?
    public var opacity: Double?
    public init(fontSize: Double? = nil, font: String? = nil, textColorHex: String? = nil,
                align: String? = nil, opacity: Double? = nil) {
        self.fontSize = fontSize; self.font = font; self.textColorHex = textColorHex
        self.align = align; self.opacity = opacity
    }
}

/// 터미널 노드가 실행하는 프로그램 종류.
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case shell
    case claude
    case codex
    case custom

    public var displayName: String {
        switch self {
        case .shell: return "Shell"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .custom: return "Custom"
        }
    }

    /// 앱이 훅으로 상태를 받을 수 있는 CLI 인지.
    public var supportsHooks: Bool { self == .claude }
}

public struct TerminalSpec: Codable, Equatable, Sendable {
    public var agent: AgentKind
    /// custom 일 때 실행 파일 경로.
    public var executable: String?
    public var extraArgs: [String]
    public var cwd: String
    /// claude 는 앱이 정한 UUID, codex 는 세션 파일에서 찾은 id.
    public var sessionID: String?
    /// 한 번이라도 실행된 적이 있는지. 재실행 시 이어하기 옵션을 쓸지 판단한다.
    public var hasLaunched: Bool
    public var profileID: UUID?

    public init(agent: AgentKind, executable: String? = nil, extraArgs: [String] = [], cwd: String,
                sessionID: String? = nil, hasLaunched: Bool = false, profileID: UUID? = nil) {
        self.agent = agent
        self.executable = executable
        self.extraArgs = extraArgs
        self.cwd = cwd
        self.sessionID = sessionID
        self.hasLaunched = hasLaunched
        self.profileID = profileID
    }
}

public struct ChecklistItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var done: Bool
    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id; self.text = text; self.done = done
    }
}

public struct KanbanColumn: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// 1차의 글자 카드. 2차에서는 items 를 쓰고, items 가 없을 때만 읽어서 옮긴다.
    public var cards: [String]
    public var items: [KanbanCard]?
    public init(id: UUID = UUID(), title: String, cards: [String] = [], items: [KanbanCard]? = nil) {
        self.id = id; self.title = title; self.cards = cards; self.items = items
    }

    /// 화면에 쓸 카드 목록(1차 글자 카드도 포함).
    public var allCards: [KanbanCard] { items ?? cards.map { KanbanCard(title: $0) } }
}

public struct KanbanCard: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var due: Date?
    /// "low", "med", "high" 또는 nil.
    public var priority: String?
    public var done: Bool
    public init(id: UUID = UUID(), title: String, notes: String = "", due: Date? = nil, priority: String? = nil, done: Bool = false) {
        self.id = id; self.title = title; self.notes = notes; self.due = due; self.priority = priority; self.done = done
    }
}

public struct CalendarEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// 그날 0시(현지).
    public var day: Date
    public var allDay: Bool
    public var colorHex: String
    public var notes: String
    public init(id: UUID = UUID(), title: String, day: Date, allDay: Bool = true, colorHex: String = "#F05A38", notes: String = "") {
        self.id = id; self.title = title; self.day = day; self.allDay = allDay; self.colorHex = colorHex; self.notes = notes
    }
}

/// 도형 노드 모양.
public struct ShapeSpec: Codable, Equatable, Sendable {
    /// "rect", "ellipse", "diamond", "arrow"
    public var kind: String
    public var strokeHex: String
    public var fillHex: String?
    public var strokeWidth: Double
    /// "solid", "dashed", "dotted"
    public var dash: String
    /// 0 이면 반듯, 1·2 로 갈수록 손그림처럼 흔들린다.
    public var roughness: Double
    public var cornerRadius: Double
    public init(kind: String = "rect", strokeHex: String = "#ECE7E2", fillHex: String? = nil, strokeWidth: Double = 2,
                dash: String = "solid", roughness: Double = 1, cornerRadius: Double = 12) {
        self.kind = kind; self.strokeHex = strokeHex; self.fillHex = fillHex; self.strokeWidth = strokeWidth
        self.dash = dash; self.roughness = roughness; self.cornerRadius = cornerRadius
    }
}

/// 펜 획. 좌표는 그 획이 속한 곳(보드 또는 이미지 노드)의 좌표계.
public struct Stroke: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var points: [Point]
    public var colorHex: String
    public var width: Double
    public init(id: UUID = UUID(), points: [Point], colorHex: String = "#FF3B30", width: Double = 3) {
        self.id = id; self.points = points; self.colorHex = colorHex; self.width = width
    }
}

public struct BoardNode: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: NodeKind
    public var frame: Rect
    public var title: String

    public var terminal: TerminalSpec?
    /// sticky·text 본문, web 주소, git 레포 경로, file 경로, image 경로 등 단일 문자열 내용.
    public var text: String?
    public var colorHex: String?
    public var checklist: [ChecklistItem]?
    public var kanban: [KanbanColumn]?
    /// image 노드 위에 그린 표시.
    public var strokes: [Stroke]?

    public var teamID: UUID?
    public var role: String?
    public var style: NodeStyle?
    public var events: [CalendarEvent]?
    public var shape: ShapeSpec?

    public init(id: UUID = UUID(), kind: NodeKind, frame: Rect, title: String,
                terminal: TerminalSpec? = nil, text: String? = nil, colorHex: String? = nil,
                checklist: [ChecklistItem]? = nil, kanban: [KanbanColumn]? = nil,
                strokes: [Stroke]? = nil, teamID: UUID? = nil, role: String? = nil) {
        self.id = id; self.kind = kind; self.frame = frame; self.title = title
        self.terminal = terminal; self.text = text; self.colorHex = colorHex
        self.checklist = checklist; self.kanban = kanban; self.strokes = strokes
        self.teamID = teamID; self.role = role
    }
}

public struct Viewport: Codable, Equatable, Sendable {
    /// 화면 중앙에 오는 캔버스 좌표.
    public var center: Point
    public var zoom: Double
    public init(center: Point = Point(x: 0, y: 0), zoom: Double = 1) {
        self.center = center; self.zoom = zoom
    }
}

public struct Team: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    /// 그룹 프레임을 접었는지(접으면 노드를 숨기고 머리만 보인다).
    public var collapsed: Bool?
    public init(id: UUID = UUID(), name: String, colorHex: String = "#5E5CE6", collapsed: Bool? = nil) {
        self.id = id; self.name = name; self.colorHex = colorHex; self.collapsed = collapsed
    }
}

/// 보드 위 두 노드를 잇는 곡선. to 가 팀이면 그룹 프레임으로 잇는다.
public struct NodeLink: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var from: UUID
    public var to: UUID
    public init(id: UUID = UUID(), from: UUID, to: UUID) { self.id = id; self.from = from; self.to = to }
}

public enum LoopTrigger: Codable, Equatable, Sendable {
    /// 지정 초마다.
    case interval(seconds: Double)
    /// 노드가 이 초 이상 유휴 상태가 되면.
    case idle(seconds: Double)
    /// 출력에 이 문구가 나오면.
    case output(pattern: String)
}

public struct LoopRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// 1차 규칙의 대상 노드. 2차에서는 targetAll·targetIDs 가 없을 때만 쓴다.
    public var nodeID: UUID
    public var message: String
    public var trigger: LoopTrigger
    /// 출력에 이 문구가 나오면 루프를 끈다. 비어 있으면 끄지 않는다(goalMode 가 nil·"text" 일 때).
    public var goal: String
    public var enabled: Bool
    public var maxRuns: Int
    public var runCount: Int

    // 2차에서 더한 값. 없으면 1차와 같이 동작한다.
    public var name: String?
    /// 작업공간의 모든 콘솔(나중에 열리는 것 포함).
    public var targetAll: Bool?
    public var targetIDs: [UUID]?
    /// 횟수로 멈추기를 켰는지. nil 이면 켠 것으로 본다(1차 호환).
    public var useMaxRuns: Bool?
    /// 켜고 나서 이 초가 지나면 멈춘다.
    public var timeLimit: Double?
    /// 목표 판정: "text"(출력 문구), "command"(명령 성공), "agent"(에이전트 판단). nil 이면 "text".
    public var goalMode: String?
    public var goalCommand: String?
    /// agent 판정에 쓸 CLI id(claude, codex).
    public var goalAgent: String?
    /// 다른 작업공간을 보고 있어도 계속 돌지. nil 이면 계속.
    public var background: Bool?

    public init(id: UUID = UUID(), nodeID: UUID, message: String, trigger: LoopTrigger,
                goal: String = "", enabled: Bool = true, maxRuns: Int = 50, runCount: Int = 0) {
        self.id = id; self.nodeID = nodeID; self.message = message; self.trigger = trigger
        self.goal = goal; self.enabled = enabled; self.maxRuns = maxRuns; self.runCount = runCount
    }

    /// 실제로 보낼 콘솔: 전체면 지금 작업공간의 모든 터미널.
    public func targets(in ws: Workspace) -> [UUID] {
        let terminals = ws.nodes.filter { $0.kind == .terminal }.map(\.id)
        if targetAll == true { return terminals }
        let ids = targetIDs ?? [nodeID]
        return ids.filter { terminals.contains($0) }
    }
}

public struct Workspace: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var nodes: [BoardNode]
    public var viewport: Viewport
    public var teams: [Team]
    public var strokes: [Stroke]
    public var loops: [LoopRule]
    /// 이 작업공간이 속한 프로젝트 폴더. 1차 상태 파일에는 없다.
    public var projectPath: String?
    public var links: [NodeLink]?

    public init(id: UUID = UUID(), name: String, nodes: [BoardNode] = [], viewport: Viewport = Viewport(),
                teams: [Team] = [], strokes: [Stroke] = [], loops: [LoopRule] = [], projectPath: String? = nil) {
        self.id = id; self.name = name; self.nodes = nodes; self.viewport = viewport
        self.teams = teams; self.strokes = strokes; self.loops = loops; self.projectPath = projectPath
    }
}

/// 같은 CLI 를 다른 계정으로 돌리기 위한 설정 폴더 지정.
public struct AccountProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var agent: AgentKind
    public var configDir: String
    public init(id: UUID = UUID(), name: String, agent: AgentKind, configDir: String) {
        self.id = id; self.name = name; self.agent = agent; self.configDir = configDir
    }
}

public struct MemoryNote: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// nil 이면 전역, 아니면 레포 경로.
    public var repoPath: String?
    public var title: String
    public var body: String
    public init(id: UUID = UUID(), repoPath: String? = nil, title: String, body: String) {
        self.id = id; self.repoPath = repoPath; self.title = title; self.body = body
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var workspaces: [Workspace]
    public var selectedWorkspaceID: UUID?
    public var profiles: [AccountProfile]
    public var memories: [MemoryNote]

    public init(version: Int = AppState.currentVersion, workspaces: [Workspace] = [],
                selectedWorkspaceID: UUID? = nil, profiles: [AccountProfile] = [], memories: [MemoryNote] = []) {
        self.version = version; self.workspaces = workspaces; self.selectedWorkspaceID = selectedWorkspaceID
        self.profiles = profiles; self.memories = memories
    }

    public static func initial() -> AppState {
        let ws = Workspace(name: "Main")
        return AppState(workspaces: [ws], selectedWorkspaceID: ws.id)
    }

    public var selectedIndex: Int? {
        guard let id = selectedWorkspaceID else { return workspaces.isEmpty ? nil : 0 }
        return workspaces.firstIndex { $0.id == id } ?? (workspaces.isEmpty ? nil : 0)
    }
}
