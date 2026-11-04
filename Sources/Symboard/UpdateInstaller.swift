import AppKit
import SymboardCore

/// 새 버전 zip 을 받아 풀고 서명을 확인한 뒤, 도우미 스크립트에 바꿔 끼우기를 맡기고 앱을 끈다(UpdateInstall).
enum UpdateInstaller {
    typealias Problem = UpdateInstall.Problem

    /// 바꿔 끼울 준비가 된 새 앱.
    struct Prepared {
        var newApp: URL
        var dest: URL
        var work: URL
    }

    /// 받기 전에 걸러낼 수 있는 것: 임시 위치에서 도는 앱, 쓸 수 없는 폴더, 서명 없는 개발 빌드.
    static func precheck() -> Problem? {
        let dest = Bundle.main.bundleURL
        if UpdateInstall.isTranslocated(dest.path) { return .translocated }
        let parent = dest.deletingLastPathComponent().path
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: parent), fm.isWritableFile(atPath: dest.path) else { return .notWritable(parent) }
        if currentTeam == nil { return .unsignedCurrent }
        return nil
    }

    static let currentTeam: String? = team(of: Bundle.main.bundleURL)

    /// 받기·풀기·검사. 메인 스레드 밖에서 돈다.
    static func prepare(_ r: UpdateCheck.Release) async throws -> Prepared {
        if let p = precheck() { throw p }
        guard let asset = r.asset else { throw Problem.noAsset }
        let dest = Bundle.main.bundleURL
        let fm = FileManager.default
        // 앱과 같은 볼륨의 임시 폴더라서 바꿔 끼울 때 복사 없이 옮겨진다.
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: dest, create: true)
        do {
            var req = URLRequest(url: asset, timeoutInterval: 120)
            req.setValue("Symboard/\(Symboard.version)", forHTTPHeaderField: "User-Agent")
            let (tmp, resp) = try await URLSession.shared.download(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Problem.downloadFailed }
            let zip = work.appendingPathComponent(UpdateCheck.assetName)
            try fm.moveItem(at: tmp, to: zip)
            let unpacked = work.appendingPathComponent("new", isDirectory: true)
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]).status == 0 else { throw Problem.badArchive }
            try? fm.removeItem(at: zip)
            let newApp = unpacked.appendingPathComponent("Symboard.app")
            guard fm.fileExists(atPath: newApp.path) else { throw Problem.badArchive }
            let valid = run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]).status == 0
            let info = Bundle(url: newApp)?.infoDictionary
            if let problem = UpdateInstall.accept(
                currentTeam: currentTeam, newTeam: team(of: newApp), signatureValid: valid,
                currentBundleID: Bundle.main.bundleIdentifier, newBundleID: info?["CFBundleIdentifier"] as? String,
                expectedVersion: r.version, newVersion: info?["CFBundleShortVersionString"] as? String
            ) { throw problem }
            return Prepared(newApp: newApp, dest: dest, work: work)
        } catch {
            try? fm.removeItem(at: work)
            if error is Problem { throw error }
            throw Problem.downloadFailed
        }
    }

    /// 도우미를 띄운다. 이 뒤에 앱이 끝나야 도우미가 바꿔 끼운다.
    static func launchSwap(_ p: Prepared) throws {
        let script = p.work.appendingPathComponent("swap.sh")
        try UpdateInstall.swapScript.write(to: script, atomically: true, encoding: .utf8)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), p.newApp.path, p.dest.path, p.work.path]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
    }

    private static func team(of app: URL) -> String? {
        // `codesign -dv` 는 정보를 stderr 로 낸다.
        UpdateInstall.teamID(fromCodesign: run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path]).output)
    }

    private static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func message(_ p: Problem) -> String {
        switch p {
        case .translocated: return L("Symboard is running from a temporary location macOS uses for apps opened from Downloads. Move it to the Applications folder, open it from there, and try again.")
        case .notWritable(let dir): return L("Symboard can't replace itself in %@. Download the new version from the release page.", dir)
        case .unsignedCurrent: return L("This build isn't signed with a Developer ID, so it can't update itself. Download the new version from the release page.")
        case .noAsset: return L("This release has no Symboard.zip to install. Download it from the release page.")
        case .downloadFailed: return L("The download failed. Check your connection and try again.")
        case .badArchive: return L("The downloaded file isn't the expected Symboard version.")
        case .signatureMismatch: return L("The downloaded app isn't signed by the same developer, so it wasn't installed.")
        }
    }
}
