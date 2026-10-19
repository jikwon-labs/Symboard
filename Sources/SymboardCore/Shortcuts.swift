import Foundation

/// 단축키 표(8차 6번). 왼쪽 아래 ? 단추와 ? 키로 연다. 앱에 있는 키를 코드에서 모두 찾아 묶음별로 적는다.
/// 키를 더하거나 바꾸면 여기도 고친다(V8Tests 가 이번 차수 키가 빠지지 않았는지 본다).
public enum ShortcutCatalog {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var keys: String
        public var action: String
        public var id: String { keys + action }
        public init(_ keys: String, _ action: String) { self.keys = keys; self.action = action }
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public var title: String
        public var entries: [Entry]
        public var id: String { title }
    }

    public static let sections: [Section] = [
        Section(title: "Canvas", entries: [
            Entry("Scroll · two-finger swipe", "Pan the board (outside consoles)"),
            Entry("⌘ + scroll", "Zoom in or out"),
            Entry("⌥ or ⌘ + scroll over a node", "Pan or zoom the board instead of the node"),
            Entry("⌘ =  /  ⌘ −", "Zoom in / out"),
            Entry("⌘ 0", "Actual size"),
            Entry("⇧⌘ 1", "Zoom to fit"),
            Entry("⇧⌘ ]  /  ⇧⌘ [", "Next / previous workspace"),
            Entry("Double-click empty board", "New console here"),
            Entry("Esc", "Close the open panel, or go back to the select tool"),
        ]),
        Section(title: "Consoles", entries: [
            Entry("⌃ Tab  /  ⌃⇧ Tab", "Next / previous console (top to bottom, left to right)"),
            Entry("⌘ 1 … ⌘ 9", "Go to console N and type into it"),
            Entry("Hold ⌘", "Show console numbers"),
            Entry("Scroll over a console", "Scroll its history (or the program's own view)"),
            Entry("Type anything · ↓ Bottom", "Jump back to the latest output"),
            Entry("⌥ ←  /  ⌥ →", "Move one word left / right"),
            Entry("⌘ ←  /  ⌘ →", "Start / end of line"),
            Entry("⌥ ⌫", "Delete the previous word"),
            Entry("⌘ ⌫", "Delete to the start of the line"),
            Entry("⌃ + letter", "Control key (⌃C, ⌃D …), also with Korean input"),
            Entry("Tab", "Sent to the program (completion)"),
            Entry("⌘ C  /  ⌘ V  /  ⌘ A", "Copy / paste / select all"),
            Entry("⌥⌘ O", "Toggle Option as Meta"),
        ]),
        Section(title: "Command bar", entries: [
            Entry("Enter", "Send"),
            Entry("⇧ Enter", "New line (grows to 3 lines, then scrolls)"),
            Entry("⇧⌘ E", "Full-screen prompt editor (again or Esc to close, text is kept)"),
            Entry("@name text @other text", "Send each console its own text"),
            Entry("@  then ↑ ↓", "Pick a console, all, or a group"),
            Entry("Tab  /  Enter", "Insert the picked @name"),
            Entry("Esc", "Close the @ list"),
        ]),
        Section(title: "Nodes and tools", entries: [
            Entry("⌘ T", "New terminal"),
            Entry("⌘ N", "New workspace"),
            Entry("⌫  /  Delete", "Delete the selected text, sticky or image"),
            Entry("⌘ Z  /  ⇧⌘ Z", "Undo / redo"),
            Entry("⌘ S", "Save (studio)"),
            Entry("⌘ Enter", "Save (loop and memory forms)"),
            Entry("?", "This list (outside text fields)"),
            Entry("⌘ W  /  ⌘ M  /  ⌘ H  /  ⌘ Q", "Close window / minimize / hide / quit"),
        ]),
    ]
}
