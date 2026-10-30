import AppKit
import SwiftUI
import SymboardCore

/// @ 자동완성 목록의 한 줄: 콘솔, all, 그룹.
struct MentionOption: Identifiable {
    enum Kind {
        case console(AgentChoice, NodeStatus)
        case all(Int)
        case group(count: Int, colorHex: String)
    }
    var name: String
    var kind: Kind
    var id: String { name.lowercased() }
}

/// 입력칸 하나의 자동완성 상태. 목록 뷰(SwiftUI)와 입력칸(AppKit)이 함께 본다.
@MainActor
final class MentionState: ObservableObject {
    /// 지금 좁혀진 줄. 비어 있으면 목록이 닫힌 것이다.
    @Published private(set) var options: [MentionOption] = []
    @Published var selected = 0
    var isOpen: Bool { !options.isEmpty }
    fileprivate var active: Mention.Active?
    fileprivate weak var field: MentionTextField?

    fileprivate func show(_ opts: [MentionOption], active: Mention.Active) {
        let keep = selected < options.count ? options[selected].id : nil
        self.active = active
        options = opts
        // 좁혀도 고르던 줄이 남아 있으면 그대로, 아니면 첫 줄.
        selected = keep.flatMap { k in opts.firstIndex { $0.id == k } } ?? 0
        if active.query.isEmpty { selected = 0 }
    }

    func close() {
        active = nil
        if !options.isEmpty { options = [] }
        selected = 0
    }

    func move(_ d: Int) {
        guard !options.isEmpty else { return }
        selected = (selected + d + options.count) % options.count
    }

    /// 마우스로 줄을 눌렀을 때.
    func pick(_ i: Int) {
        guard options.indices.contains(i) else { return }
        selected = i
        field?.insertSelected()
    }
}

/// 이름을 색칠하는 한 줄 입력칸(SwiftUI TextField 는 부분 색칠이 안 돼서 NSTextField 로 감쌌다).
/// Enter 보내기, 자리표시, 초점 요청, 입력기(한글) 조합을 그대로 지킨다.
struct MentionField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat = 13
    @ObservedObject var state: MentionState
    /// 지금 고를 수 있는 대상(콘솔 → all → 그룹 순). 글자가 바뀔 때마다 새로 읽는다.
    var options: () -> [MentionOption]
    var onSubmit: () -> Void
    /// 값이 바뀌면 이 입력칸에 초점을 주고 커서를 끝에 둔다.
    var focusRequest: Int = 0
    var axLabel: String = "Command"
    /// 보이는 줄 수 상한(8차). 그보다 길면 입력칸 안에서 스크롤한다. 0 이면 받은 높이를 다 쓴다(전체 화면 편집).
    var maxLines: Int = 3
    /// Cmd+Shift+E 로 이 입력칸의 글을 전체 화면 편집으로 연다.
    var onExpand: (() -> Void)? = nil

    func makeNSView(context: Context) -> MentionTextField {
        let f = MentionTextField()
        f.state = state
        state.field = f
        f.optionsSource = options
        f.onSubmit = onSubmit
        f.onText = { text = $0 }
        f.baseFont = .systemFont(ofSize: fontSize)
        f.setAccessibilityLabel(axLabel)
        f.stringValue = text
        f.setPlaceholder(placeholder)
        f.lastFocusRequest = focusRequest
        f.onExpand = onExpand
        return f
    }

    func updateNSView(_ f: MentionTextField, context: Context) {
        f.state = state
        state.field = f
        f.optionsSource = options
        f.onSubmit = onSubmit
        f.onText = { text = $0 }
        f.onExpand = onExpand
        f.setPlaceholder(placeholder)
        f.setExternal(text)
        if f.lastFocusRequest != focusRequest {
            f.lastFocusRequest = focusRequest
            DispatchQueue.main.async { f.focusAtEnd() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MentionTextField, context: Context) -> CGSize? {
        let w = proposal.width ?? 200
        if maxLines == 0 { return CGSize(width: w, height: proposal.height ?? 200) }
        // 글 줄 수(줄바꿈·자동 줄바꿈)만큼 자라되 maxLines 까지.
        let line = nsView.lineHeight
        let lines = min(maxLines, max(1, nsView.lineCount(width: w)))
        return CGSize(width: w, height: ceil(line * CGFloat(lines)) + 4)
    }
}

final class MentionTextField: NSTextField, NSTextFieldDelegate {
    weak var state: MentionState?
    var optionsSource: () -> [MentionOption] = { [] }
    var onSubmit: () -> Void = {}
    var onText: (String) -> Void = { _ in }
    var baseFont: NSFont = .systemFont(ofSize: 13) { didSet { font = baseFont } }
    var lastFocusRequest = 0
    var onExpand: (() -> Void)?
    private var placeholderText = ""
    private let editor = MentionEditor.make()

    static let mentionColor = NSColor(hex: "#FF8A5C")
    static let pillColor = Theme.accent.withAlphaComponent(0.2)

    override class var cellClass: AnyClass? {
        get { MentionFieldCell.self }
        set {}
    }

    init() {
        super.init(frame: .zero)
        (cell as? MentionFieldCell)?.editor = editor
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
        // 8차: 여러 줄(Shift+Enter). 자동 줄바꿈하고, 칸보다 길면 편집기가 칸 안에서 스크롤한다.
        usesSingleLineMode = false
        lineBreakMode = .byWordWrapping
        cell?.isScrollable = false
        cell?.wraps = true
        textColor = Theme.text
        font = baseFont
        delegate = self
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPlaceholder(_ s: String) {
        guard s != placeholderText else { return }
        placeholderText = s
        placeholderAttributedString = NSAttributedString(string: s, attributes: [.foregroundColor: Theme.textDim, .font: baseFont])
    }

    var lineHeight: CGFloat { ceil(baseFont.ascender - baseFont.descender + baseFont.leading) }

    /// 폭 w 에서 지금 글이 차지하는 줄 수.
    func lineCount(width w: CGFloat) -> Int {
        let text = activeEditor?.string ?? stringValue
        guard !text.isEmpty else { return 1 }
        // 끝 줄바꿈 뒤 빈 줄도 한 줄로 센다(커서가 거기 있다).
        let measured = text.hasSuffix("\n") ? text + " " : text
        let r = (measured as NSString).boundingRect(with: NSSize(width: max(20, w - 4), height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin], attributes: [.font: baseFont])
        return max(1, Int((r.height / lineHeight).rounded()))
    }

    /// 지금 편집 중인 글 편집기(초점이 없으면 nil).
    var activeEditor: MentionEditor? { currentEditor() as? MentionEditor }

    /// 바깥(SwiftUI 바인딩)에서 글이 바뀌었을 때만 반영한다. 조합 중에는 건드리지 않는다.
    func setExternal(_ text: String) {
        if let ed = activeEditor {
            guard ed.string != text, !ed.hasMarkedText() else { return }
            ed.string = text
            ed.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            restyle()
            state?.close()
        } else if stringValue != text {
            stringValue = text
            restyle()
        }
    }

    func focusAtEnd() {
        guard let w = window else { return }
        w.makeFirstResponder(self)
        if let ed = activeEditor { ed.setSelectedRange(NSRange(location: (ed.string as NSString).length, length: 0)) }
        restyle()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        // 초점을 받으면 편집기가 새 글을 받는다. 색칠을 다시 한다.
        if ok { DispatchQueue.main.async { [weak self] in self?.restyle() } }
        return ok
    }

    // MARK: 색칠

    private var names: [String] { optionsSource().map(\.name) }

    /// 알려진 @이름을 주황 글자 + 옅은 알약으로. 입력기 조합 중에는 하지 않는다(조합 밑줄이 깨진다).
    func restyle() {
        let names = self.names
        if let ed = activeEditor {
            guard !ed.hasMarkedText(), let lm = ed.layoutManager else { return }
            let full = NSRange(location: 0, length: (ed.string as NSString).length)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            for r in Mention.highlights(in: ed.string, names: names) + Mention.targets(in: ed.string, names: names) {
                lm.addTemporaryAttributes([.foregroundColor: Self.mentionColor, .backgroundColor: Self.pillColor], forCharacterRange: r)
            }
        } else {
            let s = NSMutableAttributedString(string: stringValue, attributes: [.font: baseFont, .foregroundColor: Theme.text])
            for r in Mention.highlights(in: stringValue, names: names) + Mention.targets(in: stringValue, names: names) {
                s.addAttributes([.foregroundColor: Self.mentionColor], range: r)
            }
            attributedStringValue = s
        }
    }

    // MARK: 목록

    private func refreshList() {
        guard let state else { return }
        guard let ed = activeEditor, !ed.hasMarkedText() else { return }
        let sel = ed.selectedRange()
        let opts = optionsSource()
        guard sel.length == 0, let a = Mention.active(in: ed.string, cursor: sel.location, names: opts.map(\.name))
                ?? Mention.activeInBody(in: ed.string, cursor: sel.location, names: opts.map(\.name)) else {
            state.close(); return
        }
        let hits = Mention.filter(opts.map(\.name), query: a.query)
        let shown = opts.filter { o in hits.contains(o.name) }
        if shown.isEmpty { state.close() } else { state.show(shown, active: a) }
    }

    func insertSelected() {
        guard let state, let a = state.active, state.options.indices.contains(state.selected) else { return }
        if window?.firstResponder !== activeEditor { window?.makeFirstResponder(self) }
        guard let ed = activeEditor else { return }
        let r = Mention.insert(state.options[state.selected].name, into: ed.string, replacing: a.range)
        ed.string = r.text
        ed.setSelectedRange(NSRange(location: r.cursor, length: 0))
        state.close()
        onText(r.text)
        restyle()
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        onText(stringValue)
        restyle()
        refreshList()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        state?.close()
        restyle()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        let open = state?.isOpen ?? false
        // Shift+Enter(Option+Enter 도)는 보내지 않고 줄을 바꾼다.
        if sel == #selector(NSResponder.insertNewline(_:)) || sel == #selector(NSResponder.insertLineBreak(_:)),
           let f = NSApp.currentEvent?.modifierFlags, f.contains(.shift) || f.contains(.option) {
            state?.close()
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        }
        switch sel {
        case #selector(NSResponder.moveUp(_:)) where open:
            state?.move(-1); return true
        case #selector(NSResponder.moveDown(_:)) where open:
            state?.move(1); return true
        case #selector(NSResponder.insertTab(_:)) where open,
             #selector(NSResponder.insertNewline(_:)) where open:
            insertSelected(); return true
        case #selector(NSResponder.insertNewline(_:)):
            onText(stringValue)
            onSubmit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc 는 목록만 닫는다. 목록이 없으면 아무것도 하지 않는다(글 편집기의 낱말 완성 창을 띄우지 않게).
            state?.close(); return true
        case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)),
             #selector(NSResponder.moveToBeginningOfLine(_:)), #selector(NSResponder.moveToEndOfLine(_:)):
            DispatchQueue.main.async { [weak self] in self?.refreshList() }
            return false
        default:
            return false
        }
    }

    /// 초점이 있는 입력칸(글 편집기 → 입력칸).
    static func focused(_ responder: NSResponder?) -> MentionTextField? {
        guard let tv = responder as? NSTextView else { return nil }
        return (tv.delegate as AnyObject?) as? MentionTextField
    }

    /// 이 입력칸의 목록이 열려 있는지(창의 Esc 처리가 목록을 먼저 닫게 한다).
    static func listOpen(for responder: NSResponder?) -> Bool {
        guard let tv = responder as? NSTextView, let f = (tv.delegate as AnyObject?) as? MentionTextField else { return false }
        return f.state?.isOpen ?? false
    }
}

/// 입력칸마다 자기 글 편집기를 쓰게 하는 칸. 편집기는 알약 모양 배경을 그린다.
final class MentionFieldCell: NSTextFieldCell {
    var editor: MentionEditor?
    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor ?? super.fieldEditor(for: controlView) }
}

/// 이름 배경을 둥근 알약으로 그리는 글 편집기.
final class MentionEditor: NSTextView {
    static func make() -> MentionEditor {
        let storage = NSTextStorage()
        let lm = PillLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        lm.addTextContainer(container)
        let ed = MentionEditor(frame: .zero, textContainer: container)
        container.widthTracksTextView = true
        ed.isFieldEditor = true
        ed.isRichText = false
        ed.allowsUndo = true
        ed.isAutomaticTextCompletionEnabled = false
        ed.isAutomaticQuoteSubstitutionEnabled = false
        ed.isAutomaticDashSubstitutionEnabled = false
        return ed
    }
}

final class PillLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        guard color == MentionTextField.pillColor else {
            super.fillBackgroundRectArray(rectArray, count: count, forCharacterRange: charRange, color: color)
            return
        }
        color.setFill()
        for i in 0..<count {
            let r = rectArray[i].insetBy(dx: -1, dy: 0)
            NSBezierPath(roundedRect: r, xRadius: min(5, r.height / 2), yRadius: min(5, r.height / 2)).fill()
        }
    }
}

/// 입력칸 바로 위에 뜨는 @ 목록. 줄마다 CLI 배지와 상태 점.
struct MentionList: View {
    @ObservedObject var state: MentionState
    var maxHeight: CGFloat = 260

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(state.options.enumerated()), id: \.element.id) { i, o in
                        row(o, selected: i == state.selected)
                            .id(o.id)
                            .contentShape(Rectangle())
                            .onTapGesture { state.pick(i) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("@" + o.name)
                            .accessibilityAction { state.pick(i) }
                    }
                }
                .padding(4)
            }
            .frame(height: min(maxHeight, CGFloat(state.options.count) * 31 + 8))
            .onChange(of: state.selected) { _, s in
                if state.options.indices.contains(s) { proxy.scrollTo(state.options[s].id) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.symSurface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.symBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    @ViewBuilder func row(_ o: MentionOption, selected: Bool) -> some View {
        HStack(spacing: 9) {
            switch o.kind {
            case .console(let choice, _):
                AgentBadge(choice: choice, size: 20)
            case .all:
                Image(systemName: "person.3.fill").font(.system(size: 10)).foregroundStyle(Color.symAccent)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.symAccent.opacity(0.15)))
            case .group(_, let hex):
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 10)).foregroundStyle(Color(hex: hex))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: hex).opacity(0.15)))
            }
            Text("@" + o.name).font(.system(size: 13, weight: .medium)).foregroundStyle(selected ? Color(nsColor: MentionTextField.mentionColor) : Color.symText)
            Spacer(minLength: 8)
            switch o.kind {
            case .console(let choice, let st):
                Text(choice.name).font(.system(size: 11)).foregroundStyle(Color.symDim)
                HStack(spacing: 4) {
                    Circle().fill(Color(nsColor: st.color)).frame(width: 6, height: 6)
                    Text(L(st.pillText)).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Color(nsColor: st.color))
                }
                .frame(width: 78, alignment: .leading)
            case .all(let n):
                Text(Ln(n, "%d console", "%d consoles")).font(.system(size: 11)).foregroundStyle(Color.symDim)
            case .group(let n, _):
                Text(L("group") + " · " + Ln(n, "%d console", "%d consoles")).font(.system(size: 11)).foregroundStyle(Color.symDim)
            }
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.symAccent.opacity(0.16) : Color.clear))
    }
}
