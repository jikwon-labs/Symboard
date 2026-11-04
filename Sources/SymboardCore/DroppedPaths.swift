import Foundation

/// 콘솔 위에 끌어다 놓은 파일을 터미널 입력으로 바꾼다. 터미널 앱처럼 경로마다 셸 특수 글자 앞에 `\` 를 붙이고
/// 빈칸으로 잇고, 끝에 빈칸 하나를 둔다(이어서 치기 좋게). claude·codex 는 이렇게 들어온 그림 경로를 첨부로 받는다.
public enum DroppedPaths {
    static let special: Set<Character> = [" ", "\t", "\\", "'", "\"", "`", "$", "!", "&", "|", ";", "<", ">",
                                          "(", ")", "[", "]", "{", "}", "*", "?", "#", "~", "^", "="]

    public static func escape(_ path: String) -> String {
        var out = ""
        for c in path {
            if special.contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    public static func terminalText(_ paths: [String]) -> String {
        paths.isEmpty ? "" : paths.map(escape).joined(separator: " ") + " "
    }
}
