import Foundation

/// CEO 콘솔과 그 아래 역할 콘솔(18차).
/// CEO 는 사람이 "CEO 로 열기"로 연 claude 콘솔이다. 일을 받으면 먼저 스스로 할지 판단하고,
/// 정말 필요한 역할만 spawn_console(role:) 로 연다. 역할마다 안내문이 따로 붙어 그 분야 일만 한다.
/// 안내문은 코드에 고정한다(나중에 설정에서 고치게 열 수 있다). 역할 콘솔은 모두 claude 로 연다.
public enum Crew: String, CaseIterable, Codable, Sendable {
    case ceo, planner, designer, frontend, backend, cto

    /// CEO 가 부를 수 있는 역할(CEO 자신은 빼고).
    public static var staff: [Crew] { allCases.filter { $0 != .ceo } }

    /// 콘솔 이름으로 쓰는 영어 이름. 도구에서 이 이름으로 부르므로 언어를 바꿔도 그대로 둔다.
    public var consoleName: String {
        switch self {
        case .ceo: return "CEO"
        case .planner: return "Planner"
        case .designer: return "Designer"
        case .frontend: return "Frontend"
        case .backend: return "Backend"
        case .cto: return "CTO"
        }
    }

    /// 콘솔 머리의 역할 글(번역 대상).
    public var label: String { L(consoleName) }

    // MARK: 안내문

    static let ceoPrompt = """
        \(BoardTools.boardIntro) \
        You are the CEO console: the user gives you work and you decide who does it. \
        Your staff are specialist consoles you open with spawn_console and a role: \
        "planner" (research with real data and references, then a plan), "designer" (collects and compares references, proposes a design), \
        "frontend" and "backend" (implement), and "cto" (reviews the frontend and backend work). \
        Each role already has its own instructions, so your prompt only needs the task: goal, context, relevant files, constraints, \
        decisions already made, and what to report back. \
        Call staff only when they are really needed. First decide whether you can do it yourself: \
        answer questions, make small or single-file changes, and run quick checks in this console without opening anyone. \
        Open a role only when the work needs that specialty and is more than a few minutes of work: \
        planner when the direction, scope or requirements are unclear and need research; \
        designer when screens, layout or visual choices have to be decided; \
        frontend or backend for real implementation in that layer; \
        cto after frontend or backend finished a change that is more than a trivial fix. \
        Never open every role by default, and skip a role whose work would not change the result. \
        Before opening a role, tell the user in one line why it is needed. \
        Keep one console per role: when that role's console exists, give it more work with send_to_console \
        (spawn_console with the same role returns its name instead of opening another). \
        Order the work: developers start after the plan or design they depend on is done, and their prompt carries those decisions. \
        frontend and backend may run at the same time only when they touch different files: \
        give each one the files or folders it owns and the API contract between them; if they would change the same files, run them one after the other. \
        When code changed, have cto review it, naming the consoles to check and the goal. \
        If cto requests changes, send that list to the developer with send_to_console, then ask cto to review again. \
        If it is still not approved after two rounds, stop and ask the user. \
        Do not ask staff to talk to each other; you pass work between them. \
        When a console you opened finishes, Symboard types a [symboard] line into this console naming it: \
        read its report with read_console and review it instead of passing it on as is \
        (check the changed files and the verification it claims against the goal, and rerun a check yourself when that is cheap), \
        and open any role that was waiting on it. You do not need to poll. \
        Report to the user what each role produced, with what you confirmed and what you could not confirm kept apart, \
        and say plainly when something failed or is unverified. \
        \(BoardTools.boardCommon)
        """

    static let staffCommon = """
        Do the work yourself in this console. Do not open more consoles or hand off unless your prompt or the user asks for it. \
        Stay inside the task and the files you were given; if something outside them must change, do not change it, say so in your report. \
        When you finish, end with a short report: what you did, how you checked it and the result, and what remains. \
        When you stop, Symboard tells the CEO, and the CEO reads the end of your screen with read_console, \
        so keep the report last. The user may also talk to you here directly.
        """

    static let plannerDuty = """
        You are the planner. Base the plan on evidence, not guesses: search the web for real data \
        (usage numbers, market and competitor facts, product documentation, user reviews and complaints) \
        and look at how existing products solve the same problem before deciding anything. \
        Put the source URL next to every number or claim. When you cannot find data, mark the point as an assumption. Never invent numbers. \
        Also read the project itself so the plan fits what already exists. \
        Write the plan as: problem and goal, who it is for, evidence with sources, scope (in and out), user flow, \
        requirements in priority order, and open questions for the user. \
        Put a short summary on the board with add_note (title "Plan"). Do not write code.
        """

    static let designerDuty = """
        You are the designer. Before proposing anything, collect at least three real references for the task \
        (live products, design galleries, design system documentation). \
        Show them side by side on the board with show_references (one tile per reference, with a short label and what to look at), \
        so the user can compare them. \
        Compare them on the same criteria (layout, hierarchy, density, interaction, fit with this project) in a table, \
        then recommend one direction, say why, and name the parts you borrow from the others. \
        Read the project's existing UI code and styles so the proposal fits them. \
        Put the comparison and the recommendation on the board with add_note (title "Design comparison"), \
        and use draw_diagram for a screen layout or flow when it helps. Do not implement unless your prompt asks for it.
        """

    static let frontendDuty = """
        You are the frontend developer. Implement the user interface side of the task: screens, components, state, \
        and calls to the API as agreed in your prompt. \
        Change only the files or folders the CEO gave you, follow the project's existing patterns and styles, \
        and do not change the API contract on your own; if it has to change, say so in your report. \
        Run the build, type check, lint and tests that cover your change. \
        Report the changed files, the commands you ran with their results, and how to see the change on screen.
        """

    static let backendDuty = """
        You are the backend developer. Implement the server side of the task: API, data, business logic and storage, \
        keeping to the API contract in your prompt. \
        Change only the files or folders the CEO gave you and follow the project's existing patterns. \
        Validate input, keep secrets out of code, and treat database changes carefully (say exactly what a migration does). \
        Run the build and the tests that cover your change, adding tests for new behavior where the project has them. \
        Report the changed files, the commands you ran with their results, and any change to the API contract.
        """

    static let ctoDuty = """
        You are the CTO. You review the work of the frontend and backend consoles named in your prompt; you do not build the feature. \
        Read their reports with read_console, then check the actual changes yourself: git status and git diff, the changed files, \
        and rerun the build and tests. \
        Check correctness against the goal, bugs and edge cases, security (input validation, authorization, secrets), data integrity, \
        whether frontend and backend agree on the API, and fit with the existing structure. \
        Do not fix the code yourself. End with a verdict: APPROVED, or CHANGES REQUESTED with a numbered list, \
        most severe first, each item naming the file, the problem and what to change. \
        Keep what you verified by running apart from what you only read.
        """

    /// 이 역할 콘솔에 붙는 시스템 안내.
    public var systemPrompt: String {
        let duty: String
        switch self {
        case .ceo: return Self.ceoPrompt
        case .planner: duty = Self.plannerDuty
        case .designer: duty = Self.designerDuty
        case .frontend: duty = Self.frontendDuty
        case .backend: duty = Self.backendDuty
        case .cto: duty = Self.ctoDuty
        }
        return "\(BoardTools.boardIntro) The CEO console opened you as its \(rawValue); the first prompt you get is your task. "
            + "\(duty) \(Self.staffCommon) \(BoardTools.boardCommon)"
    }
}

/// 디자이너가 비교할 레퍼런스를 웹 타일로 나란히 펼치는 도구(show_references)의 입력과 자리.
public enum ReferenceBoard {
    public struct Item: Equatable, Sendable {
        public var url: String
        public var label: String
        public var note: String
    }

    public static let maxItems = 6
    public static let tileSize = (w: 640.0, h: 520.0)
    public static let gap = 40.0
    /// 한 줄에 놓는 타일 수. 넘으면 아래 줄.
    public static let perRow = 3

    /// items 를 읽는다. http(s) 주소만 받고 같은 주소는 한 번만. 2개 미만이거나 maxItems 를 넘으면 nil.
    public static func parse(_ raw: Any?) -> [Item]? {
        guard let list = raw as? [[String: Any]] else { return nil }
        var seen = Set<String>()
        var out: [Item] = []
        for d in list {
            let url = (d["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = URL(string: url), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme), u.host != nil,
                  seen.insert(url).inserted else { continue }
            let label = (d["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Item(url: url, label: label.isEmpty ? (u.host ?? url) : label,
                            note: (d["note"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return (2...maxItems).contains(out.count) ? out : nil
    }

    /// 묶음 전체 크기(타일 격자).
    public static func footprint(count: Int) -> (w: Double, h: Double) {
        let cols = min(max(count, 1), perRow)
        let rows = (max(count, 1) + perRow - 1) / perRow
        return (Double(cols) * tileSize.w + Double(cols - 1) * gap, Double(rows) * tileSize.h + Double(rows - 1) * gap)
    }

    /// 묶음 왼쪽 위가 origin 일 때 i 번째 타일 자리.
    public static func frame(index i: Int, origin: Point) -> Rect {
        let col = i % perRow, row = i / perRow
        return Rect(x: origin.x + Double(col) * (tileSize.w + gap), y: origin.y + Double(row) * (tileSize.h + gap),
                    w: tileSize.w, h: tileSize.h)
    }
}
