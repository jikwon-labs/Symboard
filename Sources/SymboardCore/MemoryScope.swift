import Foundation

/// 메모리 범위: 전역 또는 레포(가장 가까운 .git 이 있는 폴더).
public enum MemoryScope {
    public static func repoRoot(for path: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        var dir = (path as NSString).standardizingPath
        while true {
            if fileExists(dir + "/.git") { return dir }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return nil }
            dir = parent
        }
    }

    /// 노드에 보낼 글. 제목이 있으면 맨 위에 둔다.
    public static func text(for note: MemoryNote) -> String {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = note.title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? body : "\(title)\n\(body)"
    }
}
