import AppKit
import SwiftUI
import SymboardCore

/// 에이전트 생성 팝오버에 보이는 CLI 하나.
struct AgentChoice: Identifiable, Hashable {
    var id: String
    var name: String
    var subtitle: String
    /// 배지 글자(로고 대신).
    var glyph: String
    var colorHex: String
    var agent: AgentKind
    /// custom 일 때 실행 파일 이름.
    var command: String?

    func spec(cwd: String) -> TerminalSpec {
        TerminalSpec(agent: agent, executable: agent == .custom ? command : nil, cwd: cwd)
    }
}

/// 알려진 CLI 목록과 이 맥에 깔린 것 찾기.
@MainActor
final class AgentCatalog: ObservableObject {
    static let shared = AgentCatalog()

    static let known: [AgentChoice] = [
        AgentChoice(id: "claude", name: "Claude Code", subtitle: "claude", glyph: "C", colorHex: "#E8704A", agent: .claude),
        AgentChoice(id: "codex", name: "Codex", subtitle: "codex", glyph: "X", colorHex: "#6C7BFF", agent: .codex),
        AgentChoice(id: "gemini", name: "Gemini CLI", subtitle: "gemini", glyph: "G", colorHex: "#4C9AFF", agent: .custom, command: "gemini"),
        AgentChoice(id: "aider", name: "Aider", subtitle: "aider", glyph: "A", colorHex: "#3FB27F", agent: .custom, command: "aider"),
        AgentChoice(id: "cursor", name: "Cursor Agent", subtitle: "cursor-agent", glyph: "Cu", colorHex: "#C9C3BC", agent: .custom, command: "cursor-agent"),
        AgentChoice(id: "qwen", name: "Qwen Code", subtitle: "qwen", glyph: "Q", colorHex: "#8A6CFF", agent: .custom, command: "qwen"),
        AgentChoice(id: "opencode", name: "OpenCode", subtitle: "opencode", glyph: "O", colorHex: "#D9A441", agent: .custom, command: "opencode"),
        AgentChoice(id: "shell", name: "Shell", subtitle: "default shell", glyph: ">_", colorHex: "#9A938C", agent: .shell),
    ]

    @Published private(set) var installed: Set<String> = ["shell"]
    @Published var lastChoiceID: String {
        didSet { Prefs.shared.set(lastChoiceID, for: "lastAgentChoice") }
    }

    init() {
        lastChoiceID = Prefs.shared.string("lastAgentChoice") ?? "claude"
        detect()
    }

    var available: [AgentChoice] { Self.known.filter { installed.contains($0.id) } }
    var lastChoice: AgentChoice { Self.choice(id: lastChoiceID) ?? Self.known[0] }

    static func choice(id: String) -> AgentChoice? { known.first { $0.id == id } }

    /// 노드 사양에 맞는 CLI 표시.
    static func choice(for spec: TerminalSpec?) -> AgentChoice {
        guard let spec else { return known.last! }
        switch spec.agent {
        case .claude: return known[0]
        case .codex: return known[1]
        case .shell: return known.last!
        case .custom:
            let exe = ((spec.executable ?? "") as NSString).lastPathComponent
            return known.first { $0.command == exe }
                ?? AgentChoice(id: "custom", name: exe.isEmpty ? "Custom" : exe, subtitle: exe, glyph: String(exe.prefix(1)).uppercased(),
                               colorHex: "#9A938C", agent: .custom, command: spec.executable)
        }
    }

    /// 앱 PATH(시작할 때 로그인 셸에서 얻은 것)에서 깔린 CLI 를 찾는다.
    func detect() {
        let names = Self.known.compactMap { $0.agent == .shell ? nil : ($0.command ?? $0.id) }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let found = Set(names.filter { LoginPath.which($0, path: path, isExecutable: FileManager.default.isExecutableFile(atPath:)) != nil })
        var ids: Set<String> = ["shell"]
        for c in Self.known where found.contains(c.command ?? c.id) { ids.insert(c.id) }
        installed = ids
    }
}

/// 로고 대신 쓰는 글자 배지.
struct AgentBadge: View {
    var choice: AgentChoice
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(hex: choice.colorHex).opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).stroke(Color(hex: choice.colorHex).opacity(0.55), lineWidth: 1))
            .overlay(
                Text(choice.glyph)
                    .font(.system(size: size * (choice.glyph.count > 1 ? 0.36 : 0.48), weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: choice.colorHex))
            )
            .frame(width: size, height: size)
    }
}

/// 팝오버 머리·컴포저에 쓰는 CLI 아이콘 줄. 이 맥에 없는 CLI 는 흐리게 사선을 긋고, 눌러도 띄우지 않고 onNote 로 안내만 보낸다.
struct CLIIconStrip: View {
    @ObservedObject var catalog = AgentCatalog.shared
    let ids: [String]
    let supported: Set<String>
    var selected: String?
    var size: CGFloat = 22
    let feature: String
    let onPick: (AgentChoice) -> Void
    let onNote: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ids, id: \.self) { id in
                if let ch = AgentCatalog.choice(id: id) {
                    let state = CLIIconState.of(id, installed: catalog.installed, supported: supported)
                    Button {
                        if let note = CLIIconState.note(for: state, name: ch.name, command: ch.command ?? ch.id, feature: feature) { onNote(note) }
                        else { onPick(ch) }
                    } label: {
                        AgentBadge(choice: ch, size: size)
                            .saturation(state == .missing ? 0 : 1)
                            .opacity(state == .missing ? 0.3 : (selected == nil || selected == id ? 1 : 0.5))
                            .overlay {
                                if state == .missing {
                                    Rectangle().fill(Color.symDim).frame(width: size * 1.1, height: 1.2).rotationEffect(.degrees(-45))
                                }
                            }
                            .padding(3)
                            .background(Circle().fill(selected == id ? Color.symAccent.opacity(0.16) : .clear))
                    }
                    .buttonStyle(.plainHit)
                    .tip(state == .missing ? "\(ch.name) is not installed" : ch.name)
                    .axName(state == .missing ? "\(ch.name) (not installed)" : ch.name)
                }
            }
        }
    }
}
