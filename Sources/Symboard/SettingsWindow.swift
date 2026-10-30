import AppKit
import SymboardCore

/// 톱니 단추로 여는 설정 창(7차). 지금은 Terminal 칸 하나: 영문 글꼴, 한글 글꼴, 크기, 미리보기.
/// 고르는 즉시 떠 있는 모든 콘솔에 적용하고 prefs.json 에 남긴다(따로 저장 단추 없음).
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let latin = NSPopUpButton()
    private let hangul = NSPopUpButton()
    private let size = NSPopUpButton()
    private let preview = NSTextField(labelWithString: TerminalFontSetting.previewText)
    /// 8차 3번: claude 가 보드에 콘솔을 띄우는 도구를 붙일지.
    private let boardTools = NSButton(checkboxWithTitle: L("Let agents open consoles on the board"), target: nil, action: nil)
    /// 9차 5번: 에이전트가 이어 띄울 수 있는 단계와 연 콘솔 수. 넘으면 아래 확인 띠로 묻는다.
    /// 10차: 화면 모드·언어.
    private let appearance = NSPopUpButton()
    private let language = NSPopUpButton()
    private let maxDepth = NSPopUpButton()
    private let maxOpened = NSPopUpButton()
    private static let systemLatin = "System Mono (SF Mono)"
    private static let systemHangul = "System default (Apple SD Gothic Neo)"

    init() {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("Settings")
        w.backgroundColor = Theme.surface
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        super.init(window: w)
        build()
        load()
        // 언어를 바꾸면 창 글을 다시 만든다.
        NotificationCenter.default.addObserver(forName: L10n.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    private func rebuild() {
        window?.title = L("Settings")
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        for p in [latin, hangul, size, appearance, language, maxDepth, maxOpened] { p.removeAllItems() }
        build()
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(over parent: NSWindow?) {
        load()
        if let p = parent, let w = window, !w.isVisible {
            w.setFrameOrigin(NSPoint(x: p.frame.midX - w.frame.width / 2, y: p.frame.midY - w.frame.height / 2 + 120))
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        guard let content = window?.contentView else { return }
        let generalHeader = NSTextField(labelWithString: L("GENERAL"))
        generalHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        generalHeader.textColor = Theme.textDim
        for m in AppearanceMode.allCases {
            appearance.addItem(withTitle: L(Self.appearanceTitles[m]!))
            appearance.lastItem?.representedObject = m.rawValue
        }
        for m in LanguageMode.allCases {
            // 언어 이름은 그 언어로 쓴다(어느 언어로 보고 있어도 찾을 수 있게).
            language.addItem(withTitle: m == .system ? L("Follow system") : (m == .ko ? "한국어" : "English"))
            language.lastItem?.representedObject = m.rawValue
        }
        appearance.target = self; appearance.action = #selector(appearanceChanged); appearance.setAccessibilityLabel("Appearance")
        language.target = self; language.action = #selector(languageChanged); language.setAccessibilityLabel("Language")
        let general = NSGridView(views: [[label(L("Appearance")), appearance], [label(L("Language")), language]])
        general.rowSpacing = 10
        general.columnSpacing = 12
        general.column(at: 0).xPlacement = .trailing
        general.rowAlignment = .firstBaseline
        appearance.widthAnchor.constraint(equalToConstant: 200).isActive = true
        language.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let header = NSTextField(labelWithString: L("TERMINAL"))
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = Theme.textDim

        latin.addItem(withTitle: Self.systemLatin)
        latin.menu?.addItem(.separator())
        latin.addItems(withTitles: TerminalFont.monospacedFamilies)
        latin.setAccessibilityLabel(L("Terminal font"))

        hangul.addItem(withTitle: Self.systemHangul)
        hangul.menu?.addItem(.separator())
        hangul.addItems(withTitles: TerminalFont.allFamilies.hangul)
        hangul.menu?.addItem(.separator())
        hangul.addItems(withTitles: TerminalFont.allFamilies.other)
        hangul.setAccessibilityLabel(L("Korean font"))

        for s in Int(TerminalFontSetting.sizeRange.lowerBound)...Int(TerminalFontSetting.sizeRange.upperBound) {
            size.addItem(withTitle: "\(s) pt")
            size.lastItem?.tag = s
        }
        size.setAccessibilityLabel(L("Terminal font size"))

        for p in [latin, hangul, size] {
            p.target = self
            p.action = #selector(changed)
        }

        preview.textColor = Theme.terminalText
        preview.drawsBackground = true
        preview.backgroundColor = Theme.terminalBackground
        preview.lineBreakMode = .byClipping
        preview.setAccessibilityLabel(L("Terminal font preview"))
        let previewBox = NSView()
        previewBox.wantsLayer = true
        previewBox.layer?.backgroundColor = Theme.terminalBackground.cgColor
        previewBox.layer?.cornerRadius = 8
        Theme.paint { [weak previewBox] in previewBox?.layer?.borderColor = Theme.border.cgColor }
        previewBox.layer?.borderWidth = 1
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewBox.addSubview(preview)

        let grid = NSGridView(views: [
            [label(L("Font")), latin],
            [label(L("Korean font")), hangul],
            [label(L("Size")), size],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        latin.widthAnchor.constraint(equalToConstant: 300).isActive = true
        hangul.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let note = NSTextField(labelWithString: L("Korean font is used for Hangul only. Changes apply to all open consoles."))
        note.font = .systemFont(ofSize: 11)
        note.textColor = Theme.textDim

        let agentsHeader = NSTextField(labelWithString: L("AGENTS"))
        agentsHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        agentsHeader.textColor = Theme.textDim
        boardTools.title = L("Let agents open consoles on the board")
        boardTools.target = self
        boardTools.action = #selector(boardToolsChanged)
        boardTools.setAccessibilityLabel(L("Let agents open consoles on the board"))
        (boardTools.cell as? NSButtonCell)?.attributedTitle = NSAttributedString(string: boardTools.title, attributes: [.foregroundColor: Theme.text, .font: NSFont.systemFont(ofSize: 13)])
        let agentsNote = NSTextField(wrappingLabelWithString: L("Claude and Codex consoles get Symboard tools to open, hand off to, message, read and close consoles, and to add notes and diagrams. Applies to consoles started after the change."))
        agentsNote.font = .systemFont(ofSize: 11)
        agentsNote.textColor = Theme.textDim

        for (p, name) in [(maxDepth, "Max chain steps"), (maxOpened, "Max consoles opened by agents")] {
            for n in AgentLimits.choices { p.addItem(withTitle: "\(n)"); p.lastItem?.tag = n }
            p.target = self
            p.action = #selector(limitsChanged)
            p.setAccessibilityLabel(name)
        }
        let limits = NSGridView(views: [
            [label(L("Max chain steps")), maxDepth],
            [label(L("Max consoles opened by agents")), maxOpened],
        ])
        limits.rowSpacing = 8
        limits.columnSpacing = 12
        limits.rowAlignment = .firstBaseline
        let limitsNote = NSTextField(wrappingLabelWithString: L("Past a limit, Symboard asks you before an agent opens another console."))
        limitsNote.font = .systemFont(ofSize: 11)
        limitsNote.textColor = Theme.textDim

        let stack = NSStackView(views: [generalHeader, general, header, grid, previewBox, note, agentsHeader, boardTools, agentsNote, limits, limitsNote])
        stack.setCustomSpacing(22, after: general)
        stack.setCustomSpacing(22, after: note)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            previewBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            agentsNote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            limitsNote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewBox.heightAnchor.constraint(equalToConstant: 44),
            preview.leadingAnchor.constraint(equalTo: previewBox.leadingAnchor, constant: 12),
            preview.trailingAnchor.constraint(lessThanOrEqualTo: previewBox.trailingAnchor, constant: -12),
            preview.centerYAnchor.constraint(equalTo: previewBox.centerYAnchor),
        ])
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.textColor = Theme.text
        return l
    }

    private func load() {
        let s = TerminalFont.setting
        if s.latinFamily.isEmpty || latin.item(withTitle: s.latinFamily) == nil { latin.selectItem(at: 0) } else { latin.selectItem(withTitle: s.latinFamily) }
        if s.hangulFamily.isEmpty || hangul.item(withTitle: s.hangulFamily) == nil { hangul.selectItem(at: 0) } else { hangul.selectItem(withTitle: s.hangulFamily) }
        size.selectItem(withTag: Int(s.size))
        preview.font = TerminalFont.make(s)
        boardTools.state = BoardTools.enabled(Prefs.shared) ? .on : .off
        appearance.selectItem(at: AppearanceMode.allCases.firstIndex(of: UIPrefs.appearance(Prefs.shared)) ?? 0)
        language.selectItem(at: LanguageMode.allCases.firstIndex(of: UIPrefs.language(Prefs.shared)) ?? 0)
        maxDepth.selectItem(withTag: AgentLimits.maxDepth(Prefs.shared))
        maxOpened.selectItem(withTag: AgentLimits.maxOpened(Prefs.shared))
    }

    static let appearanceTitles: [AppearanceMode: String] = [.system: "Follow system", .dark: "Dark", .light: "Light"]

    @objc private func appearanceChanged() {
        guard let raw = appearance.selectedItem?.representedObject as? String, let m = AppearanceMode(rawValue: raw) else { return }
        UIPrefs.setAppearance(m, Prefs.shared)
        Theme.apply(m)
    }

    @objc private func languageChanged() {
        guard let raw = language.selectedItem?.representedObject as? String, let m = LanguageMode(rawValue: raw) else { return }
        UIPrefs.setLanguage(m, Prefs.shared)
        L10n.apply(m)
    }

    @objc private func limitsChanged() {
        AgentLimits.setMaxDepth(maxDepth.selectedTag(), Prefs.shared)
        AgentLimits.setMaxOpened(maxOpened.selectedTag(), Prefs.shared)
    }

    @objc private func boardToolsChanged() {
        BoardTools.setEnabled(boardTools.state == .on, Prefs.shared)
    }

    @objc private func changed() {
        let l = latin.indexOfSelectedItem <= 0 ? "" : latin.titleOfSelectedItem ?? ""
        let h = hangul.indexOfSelectedItem <= 0 ? "" : hangul.titleOfSelectedItem ?? ""
        let s = TerminalFontSetting(latinFamily: l, hangulFamily: h, size: Double(size.selectedTag()))
        TerminalFont.update(s)
        preview.font = TerminalFont.make(s)
    }
}
