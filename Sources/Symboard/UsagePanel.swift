import Charts
import SwiftUI
import SymboardCore

/// 로컬 로그를 훑어 에이전트별 토큰 사용량과 통계를 모은다. 로그는 이 맥 밖으로 나가지 않는다.
@MainActor
final class UsageStore: ObservableObject {
    @Published var records: [AgentKind: [UsageRecord]] = [:]
    @Published var stats: [AgentKind: UsageStats] = [:]
    @Published var scanning = false
    @Published var note = ""
    @Published var scannedAt: Date?
    /// claude `/usage` 에서 읽은 요금제 한도(세션·주간 %, 초기화 시각).
    @Published var limits: [PlanLimit] = []
    @Published var limitsNote = ""
    @Published var limitsAt: Date?
    let probe = PlanUsageProbe()
    /// codex `/status`(없으면 마지막 세션 로그) 의 한도.
    @Published var codexLimits: [PlanLimit] = []
    @Published var codexLimitsNote = ""
    @Published var codexLimitsAt: Date?
    /// "/status" 또는 "session log".
    @Published var codexLimitsSource = ""
    let codexProbe = CodexStatusProbe()
    /// 알약이 보일 CLI. 팝오버에서 codex 탭을 고르면 원본처럼 알약도 codex 한도로 바뀐다.
    @Published var pillAgent: AgentKind = .claude
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

    /// claude 를 화면 없이 띄워 `/usage` 를 읽는다. 질문을 보내지 않는다.
    func refreshLimits() {
        guard !probe.running else { return }
        let ws = model.selectedWorkspace
        // 신뢰 확인이 이미 끝난 폴더여야 하므로 지금 프로젝트 폴더에서 띄운다.
        let cwd = ws.projectPath ?? NSHomeDirectory()
        let profile = model.profiles.active(for: .claude).flatMap { id in model.state.profiles.first { $0.id == id } }
        limitsNote = "reading claude /usage…"
        probe.run(cwd: cwd, configDir: profile?.configDir) { [weak self] limits, error in
            guard let self else { return }
            if !limits.isEmpty { self.limits = limits; self.limitsAt = Date() }
            self.limitsNote = error ?? ""
        }
    }

    /// codex 를 화면 없이 띄워 `/status` 를 읽는다. 못 읽으면 가장 최근 세션 로그의 rate_limits 를 쓴다.
    func refreshCodexLimits() {
        guard !codexProbe.running, AgentCatalog.shared.installed.contains("codex") else { return }
        let cwd = model.selectedWorkspace.projectPath ?? NSHomeDirectory()
        let profile = model.profiles.active(for: .codex).flatMap { id in model.state.profiles.first { $0.id == id } }
        codexLimitsNote = "reading codex /status…"
        codexProbe.run(cwd: cwd, configDir: profile?.configDir) { [weak self] limits, error in
            guard let self else { return }
            if !limits.isEmpty {
                self.codexLimits = limits; self.codexLimitsAt = Date(); self.codexLimitsSource = "/status"; self.codexLimitsNote = ""
                return
            }
            let roots = [profile?.configDir ?? NSHomeDirectory() + "/.codex"]
            Task.detached(priority: .utility) {
                let r = Self.latestCodexLog(roots: roots)
                await MainActor.run {
                    if !r.limits.isEmpty {
                        self.codexLimits = r.limits; self.codexLimitsAt = r.at; self.codexLimitsSource = "session log"
                        self.codexLimitsNote = (error ?? "") + " · showing the last session log"
                    } else {
                        self.codexLimitsNote = error ?? "no codex limits found"
                    }
                }
            }
        }
    }

    nonisolated static func latestCodexLog(roots: [String]) -> (limits: [PlanLimit], at: Date?) {
        let fm = FileManager.default
        var files: [(String, Date)] = []
        for root in roots {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: root + "/sessions"), includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let u as URL in e where u.pathExtension == "jsonl" {
                files.append((u.path, (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast))
            }
        }
        for (path, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(10) {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let r = CodexLimitParser.parseLog(text)
            if !r.limits.isEmpty { return r }
        }
        return ([], nil)
    }

    /// 15분이 지났거나 세션 초기화 시각이 지났으면 /usage 를 다시 읽는다. claude 가 없으면 하지 않는다.
    func refreshLimitsIfStale() {
        guard AgentCatalog.shared.installed.contains("claude") else { return }
        let age = limitsAt.map { Date().timeIntervalSince($0) } ?? .infinity
        if age > 900 || (limitsAt != nil && !pill.fromCLI) { refreshLimits() }
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        let r = roots()
        let started = Date()
        Task.detached(priority: .utility) {
            let result = Self.scan(claudeRoots: r.claude, codexRoots: r.codex, days: 365)
            var grouped: [AgentKind: [UsageRecord]] = [:]
            for rec in result.records { grouped[rec.agent, default: []].append(rec) }
            var stats: [AgentKind: UsageStats] = [:]
            for (k, v) in grouped { stats[k] = UsageStats.compute(v) }
            await MainActor.run {
                self.records = grouped
                self.stats = stats
                self.note = "\(result.files) log files · \(String(format: "%.1f", Date().timeIntervalSince(started)))s"
                self.scannedAt = Date()
                self.scanning = false
                if let end = stats.values.compactMap(\.blockEnd).max() {
                    Prefs.shared.set(String(end.timeIntervalSince1970), for: "usage.blockEnd")
                }
            }
        }
    }

    nonisolated static func scan(claudeRoots: [String], codexRoots: [String], days: Int) -> (records: [UsageRecord], files: Int) {
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
        var perFile: [[UsageRecord]] = []
        var paths = Set<String>()
        func stamp(_ path: String, _ m: Date) -> UsageFileCache.Stamp {
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            return .init(modified: m, size: size)
        }
        for root in claudeRoots {
            for (path, m) in files(under: root + "/projects") {
                paths.insert(path)
                perFile.append(fileCache.records(path: path, stamp: stamp(path, m)) {
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return [] }
                    var seen = Set<String>()
                    return UsageParser.claude(data: data, fallbackDay: fmt.string(from: m), seen: &seen)
                })
            }
        }
        for root in codexRoots {
            for (path, m) in files(under: root + "/sessions") {
                paths.insert(path)
                perFile.append(fileCache.records(path: path, stamp: stamp(path, m)) {
                    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
                    return UsageParser.codex(jsonl: text, fallbackDay: fmt.string(from: m), session: path)
                })
            }
        }
        fileCache.prune(keeping: paths)
        return (UsageFileCache.merge(perFile), paths.count)
    }

    /// 로그 파일별로 읽은 결과(바뀌지 않은 파일은 다시 읽지 않는다).
    nonisolated static let fileCache = UsageFileCache()

    /// 위쪽 알약: claude `/usage` 의 세션 % 와 초기화 시각. 그 값이 없거나 지났으면 가장 가까운 5시간 묶음 끝(짐작).
    /// 아직 훑기 전이면 지난번에 구한 묶음 끝(prefs.json)을 쓴다.
    var pill: UsagePill.Display {
        var ends = stats.values.compactMap(\.blockEnd)
        if scannedAt == nil, let cached = Prefs.shared.string("usage.blockEnd").flatMap(Double.init) {
            ends.append(Date(timeIntervalSince1970: cached))
        }
        if pillAgent == .codex, let l = codexLimits.first(where: { PlanUsageParser.isSession($0.name) }) ?? codexLimits.first {
            return UsagePill.Display(text: "resets " + PlanUsageParser.shortReset(l.resets ?? "–"), percent: l.percent, fromCLI: true)
        }
        return UsagePill.display(limits: limits, readAt: limitsAt, blockEnds: ends)
    }
}

/// 위쪽 사용량 알약에서 여는 팝오버.
struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    var close: () -> Void
    @State private var agent: AgentKind = .claude
    @State private var page = "overview"
    @State private var metric = "All tokens"
    @State private var allTime = false

    var stats: UsageStats { store.stats[agent] ?? UsageStats() }
    var choice: AgentChoice { AgentCatalog.choice(for: TerminalSpec(agent: agent, cwd: "/")) }
    var tint: Color { Color(hex: choice.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.symBorder)
            if store.scanning && store.stats.isEmpty {
                loading
            } else if page == "tokens" {
                tokens
            } else {
                overview
            }
            Divider().overlay(Color.symBorder)
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(footerSource).font(.system(size: 10, design: .monospaced))
                Spacer()
                Text(store.note).font(.system(size: 10))
            }
            .foregroundStyle(Color.symDim)
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 420)
        .background(Color.symSurface)
        .environment(\.locale, Locale(identifier: "en_US"))
        .onReceive(NotificationCenter.default.publisher(for: .usagePage)) { n in if let p = n.object as? String { page = p } }
        .onAppear {
            if store.stats.isEmpty || (store.scannedAt.map { Date().timeIntervalSince($0) > 120 } ?? true) { store.refresh() }
            if store.limitsAt.map({ Date().timeIntervalSince($0) > 120 }) ?? true { store.refreshLimits() }
        }
        .onDisappear { store.pillAgent = .claude }
        .onChange(of: agent) { _, a in
            store.pillAgent = a
            if a == .codex, store.codexLimitsSource != "/status" || (store.codexLimitsAt.map { Date().timeIntervalSince($0) > 120 } ?? true) {
                store.refreshCodexLimits()
            }
        }
    }

    var footerSource: String {
        if agent == .claude { return store.limits.isEmpty ? "local session logs" : "claude · /usage · local session logs" }
        switch store.codexLimitsSource {
        case "/status": return "codex · /status · local session logs"
        case "session log": return "codex · last session log · local session logs"
        default: return "local session logs"
        }
    }

    var header: some View {
        HStack(spacing: 8) {
            if page == "tokens" {
                Button { page = "overview" } label: { Image(systemName: "chevron.left") }.buttonStyle(.plainHit).tip("Back to overview")
                Text("tokens").font(.system(size: 15, weight: .semibold))
            } else {
                Text("usage").font(.system(size: 15, weight: .semibold))
                ForEach([AgentKind.claude, .codex], id: \.self) { a in
                    Button { agent = a } label: { AgentBadge(choice: AgentCatalog.choice(for: TerminalSpec(agent: a, cwd: "/")), size: 22) }.tip("Show \(a.rawValue) usage")
                        .buttonStyle(.plainHit)
                        .opacity(agent == a ? 1 : 0.45)
                        .overlay(alignment: .bottom) { if agent == a { Circle().fill(Color.symAccent).frame(width: 4, height: 4).offset(y: 6) } }
                }
            }
            Spacer()
            Button { page = page == "tokens" ? "overview" : "tokens" } label: { Image(systemName: "chart.bar.fill") }
                .buttonStyle(.plainHit).tip("Token details")
            Button { store.refresh(); if agent == .codex { store.refreshCodexLimits() } else { store.refreshLimits() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plainHit).tip("Rescan logs and /usage")
            Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plainHit)
        }
        .foregroundStyle(Color.symText)
        .padding(14)
    }

    var loading: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading local session logs").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.symText)
            Text("Counting tokens straight from each agent's own transcripts on this Mac. Nothing leaves your machine.")
                .font(.system(size: 11)).foregroundStyle(Color.symDim).multilineTextAlignment(.center)
        }
        .padding(30).frame(maxWidth: .infinity, minHeight: 300)
    }

    func label(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(Color.symDim)
    }

    var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let limits = agent == .claude ? store.limits : store.codexLimits
                // 큰 링: claude 는 세션, codex 는 세션(5h)이 없으면 첫 한도(주간·월간).
                let session = limits.first { PlanUsageParser.isSession($0.name) } ?? (agent == .codex ? limits.first : nil)
                let note = agent == .claude ? store.limitsNote : store.codexLimitsNote
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Color.symBorder, lineWidth: 5)
                        Circle().trim(from: 0, to: max(0.02, Double(session?.percent ?? 0) / 100))
                            .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(session.map { "\($0.percent)%" } ?? "?").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.symText)
                            Text(session == nil ? "limit" : "used").font(.system(size: 9)).foregroundStyle(Color.symDim)
                        }
                    }
                    .frame(width: 62, height: 62)
                    .hint(session == nil ? "Plan limits are read from \(agent == .claude ? "claude /usage" : "codex /status"). Open this once the project folder is trusted." : (agent == .claude ? "From claude /usage" : "From codex \(store.codexLimitsSource)"))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent == .codex ? (session?.name ?? "Current session") : "Current session").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.symText)
                        if let r = session?.resets {
                            Text("Resets \(r)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                        } else if let end = stats.blockEnd {
                            Text("\(UsageStats.short(stats.blockTokens)) tokens · resets \(end.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Self.en))) (estimated)")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                        } else {
                            Text("No activity in the last 5 hours").font(.system(size: 11)).foregroundStyle(Color.symDim)
                        }
                        if session == nil || (agent == .codex && store.codexLimitsSource == "session log") {
                            Text(note.isEmpty ? (agent == .claude ? "Limit % comes from claude /usage" : "Limit % comes from codex /status") : note)
                                .font(.system(size: 10)).foregroundStyle(Color.symDim.opacity(0.7))
                        }
                    }
                }
                // 주간 한도(모든 모델, 모델별): 원본처럼 이름 · % · 막대 · 초기화 시각.
                ForEach(limits.filter { $0 != session }, id: \.name) { l in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symText)
                            Spacer()
                            Text("\(l.percent)%").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.symText)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.symRaised)
                                Capsule().fill(tint).frame(width: g.size.width * min(1, Double(l.percent) / 100))
                            }
                        }
                        .frame(height: 5)
                        if let r = l.resets {
                            Text("Resets \(r)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.symDim)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last 7 days").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symText)
                        Spacer()
                        Text(UsageStats.short(stats.weekTokens)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.symText)
                    }
                    GeometryReader { g in
                        let frac = stats.totalTokens > 0 ? min(1, Double(stats.weekTokens) / Double(max(stats.byDay.values.max() ?? 1, 1) * 7)) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.symRaised)
                            Capsule().fill(tint).frame(width: g.size.width * frac)
                        }
                    }
                    .frame(height: 5)
                }
                label("ACTIVITY")
                Heatmap(byDay: stats.byDay, tint: tint)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                    GridRow { stat("Favorite model", stats.favoriteModel.map(Self.prettyModel) ?? "-"); stat("Total tokens", UsageStats.short(stats.totalTokens)) }
                    GridRow { stat("Sessions", "\(stats.sessions)"); stat("Active days", "\(stats.activeDays)/365") }
                    GridRow { stat("Most active day", stats.mostActiveDay.map(Self.prettyDay) ?? "-"); stat("Longest session", Self.duration(stats.longestSession)) }
                    GridRow { stat("Longest streak", "\(stats.longestStreak) days"); stat("Current streak", "\(stats.currentStreak) days") }
                }
                label("LAST 30D")
                shareBar("At >150k context", stats.bigContextShare, "Long sessions cost more per message.")
                shareBar("While 4+ sessions ran in parallel", stats.parallelShare, "Several busy sessions at once use limits faster.")
            }
            .padding(14)
        }
        .frame(height: 560)
    }

    func stat(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color.symDim)
            Spacer()
            Text(v).foregroundStyle(Color.symText).font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity)
    }

    func shareBar(_ title: String, _ v: Double, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symText)
                Spacer()
                Text("\(Int((v * 100).rounded()))%").font(.system(size: 12, design: .monospaced)).foregroundStyle(tint)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.symRaised)
                    Capsule().fill(tint).frame(width: g.size.width * v)
                }
            }
            .frame(height: 5)
            Text(sub).font(.system(size: 10)).foregroundStyle(Color.symDim)
        }
    }

    // MARK: 토큰 상세

    struct Bar: Identifiable {
        var day: Date
        var agent: String
        var tokens: Int
        var id: String { "\(day.timeIntervalSince1970)\(agent)" }
    }

    func value(_ c: TokenCounts) -> Int {
        switch metric {
        case "In + out": return c.input + c.output
        case "Output": return c.output
        default: return c.total
        }
    }

    var bars: [Bar] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let cutoff = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-29 * 86400)
        var out: [Bar] = []
        for (a, recs) in store.records {
            var byDay: [String: Int] = [:]
            for r in recs { byDay[r.day, default: 0] += value(r.counts) }
            for (d, v) in byDay { if let date = fmt.date(from: d), date >= cutoff { out.append(Bar(day: date, agent: a.displayName, tokens: v)) } }
        }
        return out
    }

    var tokens: some View {
        let b = bars
        let total = b.reduce(0) { $0 + $1.tokens }
        var dayTotals: [Date: Int] = [:]
        for x in b { dayTotals[x.day, default: 0] += x.tokens }
        let peak = dayTotals.max { $0.value < $1.value }
        let perAgent: [(AgentKind, Int)] = [AgentKind.claude, .codex].map { a in
            let recs = store.records[a] ?? []
            let cutoff = Date().addingTimeInterval(-30 * 86400)
            return (a, recs.filter { allTime || ($0.time.map { $0 >= cutoff } ?? false) }.reduce(0) { $0 + value($1.counts) })
        }
        let agentSum = max(perAgent.reduce(0) { $0 + $1.1 }, 1)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    kpi("Last 30 days", UsageStats.short(total))
                    kpi("Busiest day", peak.map { $0.key.formatted(Date.FormatStyle().month(.abbreviated).day().locale(Self.en)) } ?? "-")
                    kpi("Top agent", perAgent.max { $0.1 < $1.1 }.map { "\($0.0.displayName) · \(Int(Double($0.1) / Double(agentSum) * 100))%" } ?? "-")
                }
                HStack {
                    label("LAST 30 DAYS")
                    Spacer()
                    ForEach(["All tokens", "In + out", "Output"], id: \.self) { m in
                        Button(m) { metric = m }.buttonStyle(ChipStyle(on: metric == m))
                    }
                }
                Chart(b) { x in
                    BarMark(x: .value("Day", x.day, unit: .day), y: .value("Tokens", x.tokens))
                        .foregroundStyle(by: .value("Agent", x.agent))
                }
                .chartForegroundStyleScale(["Claude Code": Color(hex: "#E8704A"), "Codex": Color(hex: "#6C7BFF")])
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: Date.FormatStyle().month(.abbreviated).day().locale(Self.en)) } }
                .chartYAxis { AxisMarks { v in AxisValueLabel { Text(UsageStats.short(v.as(Int.self) ?? 0)) } } }
                .frame(height: 150)
                HStack {
                    label("BY AGENT")
                    Spacer()
                    Button("Last 30 days") { allTime = false }.buttonStyle(ChipStyle(on: !allTime)).axName("Last 30 days")
                    Button("All time") { allTime = true }.buttonStyle(ChipStyle(on: allTime)).axName("All time")
                }
                ForEach(perAgent, id: \.0) { a, v in
                    let c = AgentCatalog.choice(for: TerminalSpec(agent: a, cwd: "/"))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            AgentBadge(choice: c, size: 18)
                            Text(c.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.symText)
                            Spacer()
                            Text(UsageStats.short(v)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.symText)
                            Text("\(Int(Double(v) / Double(agentSum) * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.symRaised)
                                Capsule().fill(Color(hex: c.colorHex)).frame(width: g.size.width * Double(v) / Double(agentSum))
                            }
                        }
                        .frame(height: 5)
                    }
                }
                Text("Read from each agent's local session logs. Agents that do not keep token counts on disk are not shown.")
                    .font(.system(size: 10)).foregroundStyle(Color.symDim)
            }
            .padding(14)
        }
        .frame(height: 560)
    }

    func kpi(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.system(size: 10)).foregroundStyle(Color.symDim)
            Text(v).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(Color.symText)
        }
    }

    static let en = Locale(identifier: "en_US")

    static func prettyModel(_ m: String) -> String {
        var t = m.replacingOccurrences(of: "claude-", with: "")
        // "opus-5-5" → "opus 5.5", 날짜 꼬리(-20250101)는 뺀다.
        t = t.replacingOccurrences(of: "-\\d{8}$", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "-(\\d+)-(\\d+)$", with: " $1.$2", options: .regularExpression)
        return t.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func prettyDay(_ d: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: d) else { return d }
        return date.formatted(Date.FormatStyle().month(.abbreviated).day().locale(en))
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h \(m % 60)m" }
        return "\(h / 24)d \(h % 24)h"
    }
}

extension Notification.Name {
    /// 디버그 통로가 사용량 팝오버 쪽을 바꿀 때. object 는 "overview" 또는 "tokens".
    static let usagePage = Notification.Name("symboard.usagePage")
}

/// 지난 12개월 하루 단위 활동 칸.
struct Heatmap: View {
    var byDay: [String: Int]
    var tint: Color

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weeks = 52
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1) - (cal.component(.weekday, from: today) - 1), to: today)!
        let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
        let maxV = max(byDay.values.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<(weeks + 1), id: \.self) { w in
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let v = byDay[fmt.string(from: day)] ?? 0
                            let level = v == 0 ? 0 : min(4, 1 + Int(4 * Double(v) / Double(maxV)))
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(day > today ? Color.clear : (level == 0 ? Color.symRaised : tint.opacity(0.25 + 0.19 * Double(level))))
                                .frame(width: 5.5, height: 5.5)
                        }
                    }
                }
            }
            HStack(spacing: 3) {
                Spacer()
                Text("Less").font(.system(size: 9)).foregroundStyle(Color.symDim)
                ForEach(0..<5, id: \.self) { l in
                    RoundedRectangle(cornerRadius: 1.5).fill(l == 0 ? Color.symRaised : tint.opacity(0.25 + 0.19 * Double(l))).frame(width: 7, height: 7)
                }
                Text("More").font(.system(size: 9)).foregroundStyle(Color.symDim)
            }
        }
    }
}
