import AppKit
import SwiftUI
import SymboardCore

/// 보관한 콘솔 카드 본문(17차): 마지막 보고, 보관 시각, 펼치기 단추.
final class ArchivedConsoleContent: NodeContent {
    let nodeID: UUID
    unowned let model: AppModel
    let host: NSView
    var view: NSView { host }

    init(node: BoardNode, model: AppModel) {
        nodeID = node.id
        self.model = model
        let rec = node.terminal?.archived
        let id = node.id
        host = CanvasHostingView(rootView: ArchivedConsoleCard(
            report: rec?.report ?? "", at: rec?.at ?? Date(), auto: rec?.auto == true,
            unarchive: { [weak model] in model?.sessions.unarchive(id) }
        ).localized())
    }

    func sync(node: BoardNode) {}

    func menuItems() -> [NSMenuItem] {
        [ClosureMenuItem(title: L("Unarchive")) { [weak self] in
             guard let self else { return }
             self.model.sessions.unarchive(self.nodeID)
         },
         ClosureMenuItem(title: L("Copy Report")) { [weak self] in
             guard let self, let report = self.model.node(self.nodeID)?.terminal?.archived?.report else { return }
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString(report, forType: .string)
         }]
    }
}

struct ArchivedConsoleCard: View {
    var report: String
    var at: Date
    var auto: Bool
    var unarchive: () -> Void

    private var when: String {
        let f = DateFormatter()
        f.dateStyle = Calendar.current.isDateInToday(at) ? .none : .short
        f.timeStyle = .short
        return f.string(from: at)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(report.isEmpty ? L("No report was left on the screen.") : report)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(report.isEmpty ? Color.symDim : Color.symText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("end")
                }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
            HStack(spacing: 8) {
                Image(systemName: "archivebox").foregroundStyle(Color.symDim)
                Text(auto ? L("Archived automatically at %@", when) : L("Archived at %@", when))
                    .font(.system(size: 11)).foregroundStyle(Color.symDim).lineLimit(1)
                Spacer(minLength: 4)
                Button(L("Unarchive"), action: unarchive)
                    .buttonStyle(PillButtonStyle(prominent: true)).axName("Unarchive")
                    .help(L("Reopen this console and continue the same conversation"))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.symSurface)
    }
}

extension MainWindowController {
    /// lead 머리에 붙일 하위 콘솔 요약(17차).
    func childSummary(of id: UUID) -> ConsoleArchive.ChildSummary {
        guard let wsID = model.workspaceID(containing: id), let ws = model.workspace(wsID), let links = ws.links, !links.isEmpty else {
            return ConsoleArchive.ChildSummary()
        }
        let kids = ConsoleArchive.children(of: id, links: links) { [model] in model.node($0)?.kind == .terminal }
        guard !kids.isEmpty else { return ConsoleArchive.ChildSummary() }
        return ConsoleArchive.summarize(kids.map { k in
            (archived: model.node(k)?.terminal?.archived != nil, status: model.sessions.status(of: k))
        })
    }

    /// 이 콘솔이 연 콘솔 가운데 일을 끝내고 쉬는 것을 모두 보관한다. 보관한 개수.
    @discardableResult
    func archiveFinishedChildren(of id: UUID) -> Int {
        guard let wsID = model.workspaceID(containing: id), let ws = model.workspace(wsID) else { return 0 }
        let kids = ConsoleArchive.children(of: id, links: ws.links ?? []) { [model] in model.node($0)?.kind == .terminal }
        var n = 0
        for k in kids {
            let st = model.sessions.status(of: k)
            guard model.node(k)?.terminal?.archived == nil, st == .idle || st == .done || st == .exited || st == nil else { continue }
            if model.sessions.archive(k) { n += 1 }
        }
        if n > 0 { chrome.flash(L("Archived %d consoles", n)) } else { chrome.flash(L("No finished consoles to archive")) }
        return n
    }
}
