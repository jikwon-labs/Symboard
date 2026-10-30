import AppKit
import Combine
import SwiftUI
import SymboardCore

/// Cmd+Shift+E 전체 화면 프롬프트 편집(8차 4번). 명령 바나 오케스트레이터 입력칸의 글을 큰 칸에서 고친다.
/// 닫으면(같은 키·Esc) 쓴 글이 원래 입력칸에 그대로 남는다. Enter 보내기, Shift+Enter 줄바꿈, @ 자동완성·색칠은 입력칸과 같다.
@MainActor
final class PromptEditorModel: ObservableObject {
    @Published var open = false
    @Published var text = ""
    @Published var focusRequest = 0
    let mention = MentionState()

    struct Target {
        var title: () -> String
        var read: () -> String
        var write: (String) -> Void
        var send: () -> Void
        var options: () -> [MentionOption]
    }

    private(set) var target: Target?

    func show(_ t: Target) {
        target = t
        text = t.read()
        open = true
        focusRequest += 1
    }

    /// 닫는다. 쓴 글은 원래 입력칸으로 돌려준다.
    func close() {
        guard open else { return }
        target?.write(text)
        mention.close()
        open = false
    }

    /// 보낸다. 원래 입력칸이 비워졌으면(보내기 성공) 닫는다.
    func send() {
        guard let t = target else { return }
        t.write(text)
        t.send()
        text = t.read()
        if text.isEmpty { mention.close(); open = false }
    }
}

struct PromptEditorView: View {
    @ObservedObject var editor: PromptEditorModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { editor.close() }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right.2").foregroundStyle(Color.symAccent)
                    Text(editor.target?.title() ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.symText)
                        .accessibilityIdentifier("PromptEditorTitle")
                    Spacer()
                    Button { editor.close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                        .buttonStyle(.plainHit).tip(L("Close (Esc · ⇧⌘E)")).axName("Close editor")
                }
                ZStack(alignment: .bottomLeading) {
                    MentionField(text: $editor.text, placeholder: L("Write a prompt · Shift+Enter for a new line · @ to direct"),
                                 fontSize: 15, state: editor.mention, options: { [weak editor] in editor?.target?.options() ?? [] },
                                 onSubmit: { [weak editor] in editor?.send() }, focusRequest: editor.focusRequest,
                                 axLabel: "Prompt editor", maxLines: 0)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.symRaised))
                    if editor.mention.isOpen {
                        MentionList(state: editor.mention).frame(width: 420).padding(14)
                    }
                }
                HStack {
                    Text(L("Enter to send · Shift+Enter new line · Esc or ⇧⌘E to close")).font(.system(size: 11)).foregroundStyle(Color.symDim)
                    Spacer()
                    Button(L("Send")) { editor.send() }.buttonStyle(PillButtonStyle(prominent: true)).axName("Send prompt")
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.symSurface))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.symBorder))
            .padding(.horizontal, 90).padding(.vertical, 70)
        }
    }
}

/// 단축키 표(8차 6번). 왼쪽 아래 ? 단추나 입력칸 밖 ? 키로 연다.
struct ShortcutsSheet: View {
    @ObservedObject var chrome: ChromeModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { chrome.shortcutsOpen = false }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(L("Keyboard shortcuts")).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.symText)
                    Spacer()
                    Button { chrome.shortcutsOpen = false } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                        .buttonStyle(.plainHit).tip(L("Close (Esc)")).axName("Close shortcuts")
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 18) {
                        ForEach(ShortcutCatalog.sections) { sec in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L(sec.title).uppercased()).font(.system(size: 10, weight: .bold)).kerning(1).foregroundStyle(Color.symAccent)
                                ForEach(sec.entries) { e in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(L(e.keys)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Color.symText)
                                            .frame(width: 170, alignment: .leading)
                                        Text(L(e.action)).font(.system(size: 12)).foregroundStyle(Color.symDim)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 900, maxHeight: 640)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.symSurface))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.symBorder))
            .padding(40)
        }
    }
}
