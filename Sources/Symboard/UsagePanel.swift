import Charts
import SwiftUI
import SymboardCore

/// 로컬 로그를 훑어 날짜별·에이전트별 토큰 사용량을 모은다.
@MainActor
final class UsageStore: ObservableObject {
    struct Row: Identifiable, Equatable {
        var day: String
        var claude: TokenCounts
        var codex: TokenCounts
        var id: String { day }
    }

    @Published var rows: [Row] = []
    @Published var scanning = false
    @Published var note = ""
    @Published var days = 14
    unowned let model: AppModel

    init(model: AppModel) { self.model = model }

    /// 기본 폴더와 계정 프로필 폴더.
    private func roots() -> (claude: [String], codex: [String]) {
        var claude = [NSHomeDirectory() + "/.claude"]
        var codex = [NSHomeDirectory() + "/.codex"]
        for p in model.state.profiles {
            if p.agent == .claude { claude.append(p.configDir) }
            if p.agent == .codex { codex.append(p.configDir) }
        }
        return (Array(Set(claude)), Array(Set(codex)))
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        let r = roots()
        let days = days
        let started = Date()
        Task.detached(priority: .utility) {
            let result = Self.scan(claudeRoots: r.claude, codexRoots: r.codex, days: days)
            await MainActor.run {
                self.rows = result.rows
                self.note = "\(result.files) log files, \(String(format: "%.1f", Date().timeIntervalSince(started)))s"
                self.scanning = false
            }
        }
    }

    nonisolated static func scan(claudeRoots: [String], codexRoots: [String], days: Int) -> (rows: [Row], files: Int) {
        let cutoff = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(-(days - 1)) * 86400)
        let fm = FileManager.default
        func files(under root: String) -> [(String, Date)] {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.contentModificationDateKey],
                                        options: [.skipsHiddenFiles]) else { return [] }
            var out: [(String, Date)] = []
            for case let u as URL in e where u.pathExtension == "jsonl" {
                let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if m >= cutoff { out.append((u.path, m)) }
            }
            return out
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var records: [UsageRecord] = []
        var seen = Set<String>()
        var count = 0
        for root in claudeRoots {
            for (path, m) in files(under: root + "/projects") {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { continue }
                count += 1
                records += UsageParser.claude(data: data, fallbackDay: fmt.string(from: m), seen: &seen)
            }
        }
        for root in codexRoots {
            for (path, m) in files(under: root + "/sessions") {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                count += 1
                records += UsageParser.codex(jsonl: text, fallbackDay: fmt.string(from: m))
            }
        }
        let agg = UsageParser.aggregate(records)
        let cutoffDay = fmt.string(from: cutoff)
        let rows = agg.keys.filter { $0 >= cutoffDay }.sorted(by: >).map { d in
            Row(day: d, claude: agg[d]?[.claude] ?? TokenCounts(), codex: agg[d]?[.codex] ?? TokenCounts())
        }
        return (rows, count)
    }
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000_000 { return String(format: "%.2fB", Double(n) / 1e9) }
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1e3) }
    return "\(n)"
}

struct UsagePanelView: View {
    @ObservedObject var store: UsageStore

    struct Bar: Identifiable {
        var day: String
        var agent: String
        var tokens: Int
        var id: String { day + agent }
    }

    var bars: [Bar] {
        store.rows.reversed().flatMap { r in
            [Bar(day: String(r.day.suffix(5)), agent: "Claude Code", tokens: r.claude.total),
             Bar(day: String(r.day.suffix(5)), agent: "Codex", tokens: r.codex.total)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $store.days) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: store.days) { _, _ in store.refresh() }
                Spacer()
                if store.scanning { ProgressView().controlSize(.small) }
                Button("Refresh") { store.refresh() }.controlSize(.small)
            }
            Chart(bars) { b in
                BarMark(x: .value("Day", b.day), y: .value("Tokens", b.tokens))
                    .foregroundStyle(by: .value("Agent", b.agent))
            }
            .chartForegroundStyleScale(["Claude Code": Color.orange, "Codex": Color.teal])
            .chartYAxis { AxisMarks { v in AxisValueLabel { Text(formatTokens(v.as(Int.self) ?? 0)) }; AxisGridLine() } }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 8)) } }
            .frame(height: 150)
            Text("Tokens include cache reads and writes. Read from local session logs only.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            List(store.rows) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.day).font(.system(size: 11, weight: .semibold))
                    usageLine("Claude", r.claude)
                    usageLine("Codex", r.codex)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            Text(store.note).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(8)
        .onAppear { if store.rows.isEmpty { store.refresh() } }
    }

    private func usageLine(_ name: String, _ c: TokenCounts) -> some View {
        HStack(spacing: 6) {
            Text(name).frame(width: 44, alignment: .leading)
            Text(formatTokens(c.total)).bold().frame(width: 52, alignment: .trailing)
            Text("out \(formatTokens(c.output))").foregroundStyle(.secondary).lineLimit(1)
        }
        .font(.system(size: 10, design: .monospaced))
        .help("input \(c.input), output \(c.output), cache read \(c.cacheRead), cache write \(c.cacheWrite)")
    }
}
