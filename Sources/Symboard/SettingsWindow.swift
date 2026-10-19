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
    private let boardTools = NSButton(checkboxWithTitle: "Let agents open consoles on the board", target: nil, action: nil)
    private static let systemLatin = "System Mono (SF Mono)"
    private static let systemHangul = "System default (Apple SD Gothic Neo)"

    init() {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 318), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Settings"
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = Theme.surface
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        super.init(window: w)
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
        let header = NSTextField(labelWithString: "TERMINAL")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = Theme.textDim

        latin.addItem(withTitle: Self.systemLatin)
        latin.menu?.addItem(.separator())
        latin.addItems(withTitles: TerminalFont.monospacedFamilies)
        latin.setAccessibilityLabel("Terminal font")

        hangul.addItem(withTitle: Self.systemHangul)
        hangul.menu?.addItem(.separator())
        hangul.addItems(withTitles: TerminalFont.allFamilies.hangul)
        hangul.menu?.addItem(.separator())
        hangul.addItems(withTitles: TerminalFont.allFamilies.other)
        hangul.setAccessibilityLabel("Korean font")

        for s in Int(TerminalFontSetting.sizeRange.lowerBound)...Int(TerminalFontSetting.sizeRange.upperBound) {
            size.addItem(withTitle: "\(s) pt")
            size.lastItem?.tag = s
        }
        size.setAccessibilityLabel("Terminal font size")

        for p in [latin, hangul, size] {
            p.target = self
            p.action = #selector(changed)
        }

        preview.textColor = Theme.text
        preview.drawsBackground = true
        preview.backgroundColor = Theme.terminalBackground
        preview.lineBreakMode = .byClipping
        preview.setAccessibilityLabel("Terminal font preview")
        let previewBox = NSView()
        previewBox.wantsLayer = true
        previewBox.layer?.backgroundColor = Theme.terminalBackground.cgColor
        previewBox.layer?.cornerRadius = 8
        previewBox.layer?.borderColor = Theme.border.cgColor
        previewBox.layer?.borderWidth = 1
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewBox.addSubview(preview)

        let grid = NSGridView(views: [
            [label("Font"), latin],
            [label("Korean font"), hangul],
            [label("Size"), size],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        latin.widthAnchor.constraint(equalToConstant: 300).isActive = true
        hangul.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let note = NSTextField(labelWithString: "Korean font is used for Hangul only. Changes apply to all open consoles.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = Theme.textDim

        let agentsHeader = NSTextField(labelWithString: "AGENTS")
        agentsHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        agentsHeader.textColor = Theme.textDim
        boardTools.target = self
        boardTools.action = #selector(boardToolsChanged)
        boardTools.setAccessibilityLabel("Let agents open consoles on the board")
        (boardTools.cell as? NSButtonCell)?.attributedTitle = NSAttributedString(string: boardTools.title, attributes: [.foregroundColor: Theme.text, .font: NSFont.systemFont(ofSize: 13)])
        let agentsNote = NSTextField(wrappingLabelWithString: "Claude consoles get Symboard tools to open, message, read and close consoles here. Applies to consoles started after the change.")
        agentsNote.font = .systemFont(ofSize: 11)
        agentsNote.textColor = Theme.textDim

        let stack = NSStackView(views: [header, grid, previewBox, note, agentsHeader, boardTools, agentsNote])
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
