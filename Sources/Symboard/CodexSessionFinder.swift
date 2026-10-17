import Foundation
import SymboardCore

/// codex 는 세션 id 를 미리 정할 수 없어서, 실행 뒤 생긴 세션 파일을 찾아 노드에 기록한다.
@MainActor
enum CodexSessionFinder {
    private static var claimed: Set<String> = []
    private static var timers: [UUID: Timer] = [:]

    static func watch(for nodeID: UUID, cwd: String, startedAfter: Date, configDir: String?, found: @escaping (String) -> Void) {
        timers[nodeID]?.invalidate()
        let root = CodexSessions.sessionsRoot(configDir: configDir)
        let deadline = Date().addingTimeInterval(30 * 60)
        let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { t in
            MainActor.assumeIsolated {
                if Date() > deadline { t.invalidate(); timers[nodeID] = nil; return }
                if let meta = CodexSessions.findSession(root: root, cwd: cwd, startedAfter: startedAfter, excluded: claimed) {
                    claimed.insert(meta.id)
                    t.invalidate(); timers[nodeID] = nil
                    found(meta.id)
                }
            }
        }
        timers[nodeID] = timer
    }
}
