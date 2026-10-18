import Foundation
import SymboardCore

/// 앱이 시작할 때 사용자 셸에서 PATH 를 얻어 이 프로세스 환경에 넣는다.
/// 이후 모든 자식 프로세스(감지, AgentJob, 루프, 사용량 읽기, git, 터미널)가 이 PATH 를 물려받는다.
enum LoginEnvironment {
    /// 얻은 결과. 진단·시험용.
    nonisolated(unsafe) private(set) static var fromShell = false
    nonisolated(unsafe) private(set) static var elapsed: TimeInterval = 0

    static func bootstrap(timeout: TimeInterval = 4) {
        let start = Date()
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let current = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let out = LoginPath.runProbe(shell: ProcessEnvironment.userShell, arguments: LoginPath.probeArguments(), timeout: timeout)
        let fm = FileManager.default
        let nvmDir = home + "/.nvm"
        let nvm = LoginPath.nvmBin(home: home,
                                   defaultAlias: try? String(contentsOfFile: nvmDir + "/alias/default", encoding: .utf8),
                                   versions: (try? fm.contentsOfDirectory(atPath: nvmDir + "/versions/node")) ?? [])
        var isDir: ObjCBool = false
        let r = LoginPath.resolve(shellOutput: out, currentPath: current, home: home, nvmBin: nvm) {
            fm.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue
        }
        setenv("PATH", r.path, 1)
        fromShell = r.fromShell
        elapsed = Date().timeIntervalSince(start)
        NSLog("Symboard PATH (%@, %.2fs): %@", r.fromShell ? "shell" : "fallback", elapsed, r.path)
    }
}
