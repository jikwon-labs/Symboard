import AppKit
import SwiftUI
import SymboardCore

/// SwiftUI 본문이 보는 노드 사본. 편집은 save 로 모델에 되돌린다.
@MainActor
final class NodeBox: ObservableObject {
    @Published var node: BoardNode
    let save: (BoardNode) -> Void

    init(node: BoardNode, save: @escaping (BoardNode) -> Void) {
        self.node = node
        self.save = save
    }

    func update(_ body: (inout BoardNode) -> Void) {
        var n = node
        body(&n)
        node = n
        save(n)
    }

    func binding<T>(_ key: WritableKeyPath<BoardNode, T>) -> Binding<T> {
        Binding(get: { self.node[keyPath: key] }, set: { v in self.update { $0[keyPath: key] = v } })
    }
}

/// SwiftUI 뷰를 노드 본문으로 붙인다.
final class HostedContent: NodeContent {
    let box: NodeBox
    let host: NSView
    var view: NSView { host }
    private let extraMenu: (NodeBox) -> [NSMenuItem]

    init<V: View>(node: BoardNode, model: AppModel, menu: @escaping (NodeBox) -> [NSMenuItem] = { _ in [] },
                  @ViewBuilder make: (NodeBox) -> V) {
        let id = node.id
        box = NodeBox(node: node) { [weak model] n in
            model?.mutateNode(id) { cur in
                // 위치·크기는 NodeView 가 관리하므로 본문 편집으로 덮어쓰지 않는다.
                let frame = cur.frame
                cur = n
                cur.frame = frame
            }
        }
        extraMenu = menu
        host = CanvasHostingView(rootView: make(box).environment(\.colorScheme, .dark).environment(\.locale, Locale(identifier: "en_US")))
    }

    func sync(node: BoardNode) {
        var n = node
        n.frame = box.node.frame
        if n != box.node { box.node = node }
    }

    func menuItems() -> [NSMenuItem] { extraMenu(box) }
}

// MARK: 스티키·텍스트

/// 스티키: 헤더 없는 종이. 줄무늬·접힌 모서리·그림자, 손글씨.
struct StickyView: View {
    @ObservedObject var box: NodeBox
    var isSticky: Bool

    var paper: Color { Color(hex: box.node.colorHex ?? "#C9A227") }
    var ink: Color { (box.node.colorHex ?? "").uppercased() == "#2B2926" ? Color.symText : Color(hex: "#FFF8EC") }

    var body: some View {
        GeometryReader { geo in
            let fold: CGFloat = 22
            ZStack(alignment: .topLeading) {
                PaperShape(fold: fold)
                    .fill(LinearGradient(colors: [paper.opacity(0.92), paper], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 4)
                // 줄무늬
                Path { p in
                    var y: CGFloat = 34
                    while y < geo.size.height - 8 {
                        p.move(to: CGPoint(x: 10, y: y)); p.addLine(to: CGPoint(x: geo.size.width - 14, y: y))
                        y += 24
                    }
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .clipShape(PaperShape(fold: fold))
                // 접힌 모서리
                Path { p in
                    let w = geo.size.width - 6, h = geo.size.height - 8
                    p.move(to: CGPoint(x: w - fold, y: h)); p.addLine(to: CGPoint(x: w - fold, y: h - fold)); p.addLine(to: CGPoint(x: w, y: h - fold)); p.closeSubpath()
                }
                .fill(Color.black.opacity(0.28))
                TextEditor(text: Binding(get: { box.node.text ?? "" }, set: { v in box.update { $0.text = v } }))
                    .font(Font(Theme.handwriting(size: 17)))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .foregroundStyle(ink)
                    .lineSpacing(4)
                    .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, fold)
                    .frame(width: geo.size.width - 6, height: geo.size.height - 8)
            }
            .padding(.leading, 0).padding(.top, 0)
        }
    }
}

/// 오른쪽 아래가 접힌 종이 모양. 그림자 자리를 남기려고 오른쪽·아래를 조금 줄인다.
struct PaperShape: Shape {
    var fold: CGFloat
    func path(in r: CGRect) -> Path {
        let w = r.width - 6, h = r.height - 8
        var p = Path()
        p.move(to: CGPoint(x: 4, y: 0))
        p.addLine(to: CGPoint(x: w - 4, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: 4), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - fold))
        p.addLine(to: CGPoint(x: w - fold, y: h))
        p.addLine(to: CGPoint(x: 4, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - 4), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: 4))
        p.addQuadCurve(to: CGPoint(x: 4, y: 0), control: CGPoint(x: 0, y: 0))
        return p
    }
}

/// 캔버스 위 큰 글자. 바탕 없이 글자만 보인다.
struct TitleTextView: View {
    @ObservedObject var box: NodeBox

    var style: NodeStyle { box.node.style ?? NodeStyle() }

    var body: some View {
        TextEditor(text: Binding(get: { box.node.text ?? "" }, set: { v in box.update { $0.text = v } }))
            .font(Font(TextStyleFonts.font(style)))
            .multilineTextAlignment(TextStyleFonts.alignment(style))
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .foregroundStyle(Color(hex: style.textColorHex ?? "#ECE7E2"))
            .opacity(style.opacity ?? 1)
            .overlay(alignment: .topLeading) {
                if (box.node.text ?? "").isEmpty {
                    Text("Type something").font(Font(TextStyleFonts.font(style))).foregroundStyle(Color.symDim.opacity(0.5))
                        .padding(.leading, 5).allowsHitTesting(false)
                }
            }
            .background(Color.clear)
    }
}

enum TextStyleFonts {
    static let sizes: [(String, Double)] = [("S", 20), ("M", 28), ("L", 44), ("XL", 64)]
    static let fonts: [(String, String)] = [("hand", "Hand"), ("sans", "Sans"), ("serif", "Serif"), ("mono", "Mono")]

    static func font(_ s: NodeStyle) -> NSFont {
        let size = CGFloat(s.fontSize ?? 28)
        switch s.font ?? "hand" {
        case "sans": return .systemFont(ofSize: size, weight: .medium)
        case "serif": return NSFont(name: "NewYork-Regular", size: size) ?? NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        case "mono": return .monospacedSystemFont(ofSize: size, weight: .regular)
        default: return Theme.handwriting(size: size)
        }
    }

    static func alignment(_ s: NodeStyle) -> TextAlignment {
        switch s.align { case "center": return .center; case "right": return .trailing; default: return .leading }
    }
}

enum StickyColors {
    static let all: [(String, String)] = [("Yellow", "#FFD60A"), ("Pink", "#FF9FC6"), ("Green", "#9BE59B"), ("Blue", "#9CCBFF"), ("Purple", "#C9B3FF")]

    @MainActor
    static func menu(_ box: NodeBox) -> [NSMenuItem] {
        let item = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, hex) in all { sub.addItem(ClosureMenuItem(title: name) { box.update { $0.colorHex = hex } }) }
        item.submenu = sub
        return [item]
    }
}

// MARK: 체크리스트

struct ChecklistView: View {
    @ObservedObject var box: NodeBox
    @State private var draft = ""
    @State private var adding = false
    @FocusState private var focused: Bool

    var items: [ChecklistItem] { box.node.checklist ?? [] }

    var body: some View {
        let done = items.filter(\.done).count
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.symBorder, lineWidth: 3)
                    Circle().trim(from: 0, to: items.isEmpty ? 0 : CGFloat(done) / CGFloat(items.count))
                        .stroke(Color.symAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(items.count - done)").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color.symText)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(items.isEmpty ? "No objectives" : "\(done) of \(items.count) done").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                    Text(items.isEmpty ? "Add one to begin" : (done == items.count ? "All clear" : "\(items.count - done) left")).font(.system(size: 11)).foregroundStyle(Color.symDim)
                }
            }
            .padding(12)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if items.isEmpty {
                        ForEach([0.55, 0.4, 0.3], id: \.self) { w in
                            HStack(spacing: 10) {
                                Circle().stroke(Color.symBorder).frame(width: 14, height: 14)
                                RoundedRectangle(cornerRadius: 3).fill(Color.symBorder.opacity(0.7)).frame(width: 200 * w, height: 6)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 12)
                        }
                        .opacity(0.6)
                    }
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Button {
                                box.update { n in
                                    if let i = n.checklist?.firstIndex(where: { $0.id == item.id }) { n.checklist?[i].done.toggle() }
                                }
                            } label: {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.done ? Color.symAccent : Color.symDim)
                            }
                            .buttonStyle(.plainHit).tip(item.done ? "Mark not done" : "Mark done")
                            Text(item.text).strikethrough(item.done).foregroundStyle(item.done ? Color.symDim : Color.symText)
                            Spacer()
                            Button {
                                box.update { $0.checklist?.removeAll { $0.id == item.id } }
                            } label: { Image(systemName: "xmark").font(.system(size: 9)) }.tip("Delete objective")
                                .buttonStyle(.plainHit).foregroundStyle(Color.symDim)
                        }
                        .font(.system(size: 13))
                        .padding(.vertical, 6).padding(.horizontal, 12)
                    }
                }
            }
            if adding {
                TextField("", text: $draft, prompt: Text("New objective").foregroundColor(Color.symDim))
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Color.symText)
                    .focused($focused)
                    .padding(10).background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
                    .padding(8)
                    .onSubmit {
                        let t = draft.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { box.update { $0.checklist = ($0.checklist ?? []) + [ChecklistItem(text: t)] } }
                        draft = ""
                        if t.isEmpty { adding = false }
                    }
            } else {
                Button { adding = true; focused = true } label: {
                    Label("Add an objective", systemImage: "plus").font(.system(size: 12)).foregroundStyle(Color.symText.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(RoundedRectangle(cornerRadius: 9).fill(Color.symRaised))
                }
                .buttonStyle(.plainHit).axName("Add an objective").padding(8)
            }
        }
        .background(Color.symSurface)
    }
}

// MARK: 칸반

struct KanbanView: View {
    @ObservedObject var box: NodeBox
    /// 카드 모달: (열 id, 고치는 카드 id 또는 nil)
    @State private var editor: (UUID, UUID?)?
    @State private var dropTarget: UUID?

    var columns: [KanbanColumn] { box.node.kanban ?? [] }

    static func columnColor(_ i: Int, _ title: String) -> Color {
        switch title.lowercased() {
        case "backlog": return .symDim
        case "to do", "todo": return Color(hex: "#56A8F5")
        case "in progress", "doing": return Color(hex: "#E9C46A")
        case "done": return Color(hex: "#6FCF97")
        default: return [Color(hex: "#B48CF2"), Color(hex: "#F28AB2"), Color(hex: "#56C2C9")][i % 3]
        }
    }

    var body: some View {
        ZStack {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { ci, col in
                        column(ci, col)
                    }
                    Button { addColumn() } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 14))
                            Text("Column").font(.system(size: 11))
                        }
                        .foregroundStyle(Color.symDim)
                        .frame(width: 90, height: 90)
                    }
                    .buttonStyle(.plainHit).tip("Add column")
                }
                .padding(10)
            }
            if let (colID, cardID) = editor {
                Color.black.opacity(0.35).onTapGesture { editor = nil }
                CardEditor(card: cardID.flatMap { id in columns.flatMap(\.allCards).first { $0.id == id } }) { card in
                    save(card, in: colID)
                    editor = nil
                } cancel: { editor = nil } delete: {
                    if let id = cardID { box.update { n in for i in (n.kanban ?? []).indices { n.kanban?[i].items?.removeAll { $0.id == id } } } }
                    editor = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.symSurface)
        .onReceive(NotificationCenter.default.publisher(for: .openCardEditor)) { note in
            guard note.object as? UUID == box.node.id, let i = note.userInfo?["column"] as? Int, i < columns.count else { return }
            editor = (columns[i].id, nil)
        }
    }

    func column(_ ci: Int, _ col: KanbanColumn) -> some View {
        let cards = col.allCards
        let color = Self.columnColor(ci, col.title)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(col.title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(Color.symText)
                Text("\(cards.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.symDim)
                Spacer()
                Menu {
                    Button("Rename...") {
                        if let t = Prompt.text(title: "Rename column", value: col.title), !t.isEmpty { box.update { $0.kanban?[ci].title = t } }
                    }
                    Button("Delete column", role: .destructive) { box.update { $0.kanban?.remove(at: ci) } }
                } label: { Image(systemName: "ellipsis") }.tip("Column actions")
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20).foregroundStyle(Color.symDim)
            }
            ScrollView {
                VStack(spacing: 6) {
                    if cards.isEmpty {
                        VStack(spacing: 4) {
                            Image(systemName: "tray").font(.system(size: 16))
                            Text("No cards").font(.system(size: 11))
                        }
                        .foregroundStyle(Color.symDim.opacity(0.7))
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    ForEach(cards) { card in
                        CardView(card: card) {
                            box.update { n in
                                guard var cols = n.kanban else { return }
                                Board.move(card: card.id, to: col.id, at: nil, in: &cols)
                                if let i = cols[ci].items?.firstIndex(where: { $0.id == card.id }) { cols[ci].items?[i].done.toggle() }
                                n.kanban = cols
                            }
                        }
                        .onTapGesture { editor = (col.id, card.id) }
                        .draggable(card.id.uuidString)
                        .dropDestination(for: String.self) { ids, _ in drop(ids, to: col.id, before: card.id) }
                    }
                }
            }
            Button { editor = (col.id, nil) } label: {
                Label("Add card", systemImage: "plus").font(.system(size: 12)).foregroundStyle(Color.symDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
            }
            .buttonStyle(.plainHit).axName("Add card to \(col.title)")
        }
        .padding(10)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.symRaised.opacity(dropTarget == col.id ? 1 : 0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(dropTarget == col.id ? Color.symAccent.opacity(0.6) : Color.symBorder))
        .dropDestination(for: String.self) { ids, _ in drop(ids, to: col.id, before: nil) } isTargeted: { on in
            dropTarget = on ? col.id : (dropTarget == col.id ? nil : dropTarget)
        }
    }

    func drop(_ ids: [String], to col: UUID, before: UUID?) -> Bool {
        guard let s = ids.first, let id = UUID(uuidString: s), id != before else { return false }
        box.update { n in
            guard var cols = n.kanban else { return }
            var at: Int?
            if let b = before, let ci = cols.firstIndex(where: { $0.id == col }) { at = cols[ci].allCards.firstIndex { $0.id == b } }
            Board.move(card: id, to: col, at: at, in: &cols)
            n.kanban = cols
        }
        return true
    }

    func addColumn() {
        if let t = Prompt.text(title: "New column", value: "Review"), !t.isEmpty {
            box.update { $0.kanban = ($0.kanban ?? []) + [KanbanColumn(title: t, items: [])] }
        }
    }

    func save(_ card: KanbanCard, in col: UUID) {
        box.update { n in
            guard var cols = n.kanban else { return }
            for i in cols.indices where cols[i].items == nil { cols[i].items = cols[i].allCards; cols[i].cards = [] }
            if let ci = cols.firstIndex(where: { $0.items!.contains { $0.id == card.id } }),
               let j = cols[ci].items!.firstIndex(where: { $0.id == card.id }) {
                cols[ci].items![j] = card
            } else if let ci = cols.firstIndex(where: { $0.id == col }) {
                cols[ci].items!.append(card)
            }
            n.kanban = cols
        }
    }
}

extension Notification.Name {
    /// 디버그 통로가 칸반 카드 모달을 열 때. object 는 노드 id.
    static let openCardEditor = Notification.Name("symboard.openCardEditor")
}

enum Priority {
    static func color(_ p: String?) -> Color {
        switch p { case "high": return Color(hex: "#E8564A"); case "med": return Color(hex: "#E9C46A"); case "low": return Color(hex: "#6FCF97"); default: return .symDim }
    }
    static func label(_ p: String?) -> String {
        switch p { case "high": return "High"; case "med": return "Med"; case "low": return "Low"; default: return "None" }
    }
}

struct CardView: View {
    var card: KanbanCard
    var toggle: () -> Void

    var dueText: String? {
        guard let d = card.due else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: toggle) {
                Image(systemName: card.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(card.done ? Color(hex: "#6FCF97") : Color.symDim)
            }
            .buttonStyle(.plainHit).tip(card.done ? "Mark not done" : "Mark done")
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title).font(.system(size: 12, weight: .medium)).foregroundStyle(card.done ? Color.symDim : Color.symText)
                    .strikethrough(card.done).fixedSize(horizontal: false, vertical: true)
                if dueText != nil || card.priority != nil {
                    HStack(spacing: 4) {
                        if let d = dueText {
                            Label(d, systemImage: "calendar").font(.system(size: 10))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Color.symAccent.opacity(0.12))).foregroundStyle(Color.symAccent)
                        }
                        if card.priority != nil {
                            HStack(spacing: 3) { Circle().fill(Priority.color(card.priority)).frame(width: 5, height: 5); Text(Priority.label(card.priority)) }
                                .font(.system(size: 10))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Priority.color(card.priority).opacity(0.12))).foregroundStyle(Priority.color(card.priority))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .padding(.leading, 3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.symSurface))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Priority.color(card.priority).opacity(card.priority == nil ? 0.3 : 0.9)).frame(width: 3).padding(.vertical, 6) }
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.symBorder))
        .contentShape(Rectangle())
    }
}

/// 카드 추가·고치기 모달.
struct CardEditor: View {
    @State private var title: String
    @State private var notes: String
    @State private var due: Date?
    @State private var priority: String?
    let editing: KanbanCard?
    var save: (KanbanCard) -> Void
    var cancel: () -> Void
    var delete: () -> Void

    init(card: KanbanCard?, save: @escaping (KanbanCard) -> Void, cancel: @escaping () -> Void, delete: @escaping () -> Void) {
        editing = card
        _title = State(initialValue: card?.title ?? "")
        _notes = State(initialValue: card?.notes ?? "")
        _due = State(initialValue: card?.due)
        _priority = State(initialValue: card?.priority)
        self.save = save; self.cancel = cancel; self.delete = delete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editing == nil ? "NEW CARD" : "EDIT CARD").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(Color.symDim)
                Spacer()
                Button(action: cancel) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Close")
            }
            HStack(spacing: 8) {
                Circle().fill(Priority.color(priority)).frame(width: 7, height: 7)
                TextField("", text: $title, prompt: Text("Card title").foregroundColor(Color.symDim))
                    .textFieldStyle(.plain).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.symText)
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised))
            TextField("", text: $notes, prompt: Text("Notes (optional)").foregroundColor(Color.symDim), axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.symText).lineLimit(2...4)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.symRaised))
            HStack(spacing: 6) {
                Image(systemName: "calendar").foregroundStyle(Color.symDim)
                ForEach([("Today", 0), ("Tomorrow", 1), ("Next week", 7)], id: \.1) { item in
                    let d = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(item.1) * 86400))
                    Button(item.0) { due = d }.buttonStyle(ChipStyle(on: due.map { Calendar.current.isDate($0, inSameDayAs: d) } ?? false)).axName("Due \(item.0)")
                }
                Spacer()
                if let d = due {
                    Text(d, format: .dateTime.month(.twoDigits).day(.twoDigits).year()).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.symText)
                    Button { due = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plainHit).foregroundStyle(Color.symDim).tip("Clear due date")
                }
            }
            HStack(spacing: 6) {
                ForEach([nil, "low", "med", "high"] as [String?], id: \.self) { p in
                    Button { priority = p } label: {
                        HStack(spacing: 4) {
                            if p != nil { Circle().fill(Priority.color(p)).frame(width: 6, height: 6) }
                            Text(Priority.label(p))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ChipStyle(on: priority == p)).axName("Priority \(Priority.label(p))")
                }
            }
            HStack {
                if editing != nil {
                    Button(action: delete) { Image(systemName: "trash") }.buttonStyle(.plainHit).foregroundStyle(Color.symAccent).tip("Delete card")
                }
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.plainHit).foregroundStyle(Color.symDim).axName("Cancel")
                Button(editing == nil ? "Add card" : "Save") {
                    var c = editing ?? KanbanCard(title: "")
                    c.title = title.trimmingCharacters(in: .whitespaces)
                    c.notes = notes; c.due = due; c.priority = priority
                    save(c)
                }
                .buttonStyle(PillButtonStyle(prominent: true)).axName(editing == nil ? "Add card" : "Save")
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.symSurface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.symBorder))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 6)
    }
}
