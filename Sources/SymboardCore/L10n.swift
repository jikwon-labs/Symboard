import Foundation
import Combine

/// 화면 글 언어(10차). 영어 원문을 열쇠로 한국어 표(`Strings.ko`)에서 찾는다. 표에 없으면 영어 그대로.
/// 에이전트에게 보내는 글(안내·도구 답)과 접근성 이름은 바꾸지 않는다(DECISIONS 10차-3).
@MainActor
public final class L10n: ObservableObject {
    public static let shared = L10n()
    /// 바뀔 때마다 하나씩 올라간다. SwiftUI 뿌리 뷰가 이 값으로 다시 그린다.
    @Published public private(set) var revision = 0
    public static let didChange = Notification.Name("symboard.languageDidChange")

    /// 지금 쓰는 언어(en 또는 ko). 어느 스레드에서나 읽는다.
    nonisolated(unsafe) public static var current: LanguageMode = .en

    public static func apply(_ mode: LanguageMode) {
        current = UIPrefs.resolvedLanguage(mode)
        shared.revision += 1
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// 화면 글. 영어 원문을 넣으면 지금 언어의 글을 돌려준다.
public func L(_ english: String) -> String { L10n.translate(english, to: L10n.current) }

extension L10n {
    /// 언어를 정해 찾는다(시험은 전역 언어를 바꾸지 않고 이것을 쓴다. 다른 시험과 동시에 돈다).
    public nonisolated static func translate(_ english: String, to lang: LanguageMode) -> String {
        guard lang == .ko else { return english }
        return Strings.ko[english] ?? english
    }
}

/// 값이 들어가는 글. 원문은 `%@`·`%d` 자리표시를 쓴다(예: L("Opened %d consoles", n)).
public func L(_ english: String, _ args: CVarArg...) -> String {
    String(format: L(english), arguments: args)
}

/// 개수에 따라 영어 단수·복수 원문을 고르고 %d 자리에 개수를 넣는다(한국어 표는 둘 다 같은 글).
public func Ln(_ n: Int, _ one: String, _ other: String) -> String {
    L(n == 1 ? one : other, n)
}
