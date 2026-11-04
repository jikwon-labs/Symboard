import Foundation
import Testing
@testable import SymboardCore

@Suite struct UpdateCheckTests {
    func prefs() throws -> Prefs {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Prefs(directory: dir)
    }

    @Test func versionOrder() {
        #expect(UpdateCheck.isNewer("v0.2.0", than: "0.1.0"))
        #expect(UpdateCheck.isNewer("0.1.10", than: "0.1.9"))
        #expect(UpdateCheck.isNewer("1.0", than: "0.9.9"))
        #expect(!UpdateCheck.isNewer("0.1.0", than: "0.1.0"))
        #expect(!UpdateCheck.isNewer("v0.1", than: "0.1.0"))
        #expect(!UpdateCheck.isNewer("0.0.9", than: "0.1.0"))
        #expect(!UpdateCheck.isNewer("nightly", than: "0.1.0"))
        #expect(!UpdateCheck.isNewer("0.2.0-beta", than: "0.1.0"))
    }

    @Test func parsesLatestRelease() {
        let ok = #"{"tag_name":"v0.2.0","html_url":"https://github.com/jikwon-labs/Symboard/releases/tag/v0.2.0","draft":false,"prerelease":false}"#
        #expect(UpdateCheck.parse(Data(ok.utf8)) == .init(version: "0.2.0", url: URL(string: "https://github.com/jikwon-labs/Symboard/releases/tag/v0.2.0")!))
        #expect(UpdateCheck.parse(Data(#"{"tag_name":"v0.3.0","prerelease":true}"#.utf8)) == nil)
        #expect(UpdateCheck.parse(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
        #expect(UpdateCheck.parse(Data("not json".utf8)) == nil)
        // 주소가 없으면 릴리스 목록으로.
        #expect(UpdateCheck.parse(Data(#"{"tag_name":"0.4.0"}"#.utf8))?.url == UpdateCheck.releasesPage)
    }

    @Test func oncePerDayAndCached() throws {
        let p = try prefs()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateCheck.isDue(p, now: now))
        UpdateCheck.store(.init(version: "9.0.0", url: UpdateCheck.releasesPage), p, now: now)
        #expect(!UpdateCheck.isDue(p, now: now.addingTimeInterval(3600)))
        #expect(UpdateCheck.isDue(p, now: now.addingTimeInterval(UpdateCheck.interval)))
        #expect(UpdateCheck.isDue(p, now: now.addingTimeInterval(-60)))
        #expect(UpdateCheck.available(p, current: "0.1.0")?.version == "9.0.0")
        #expect(UpdateCheck.available(p, current: "9.0.0") == nil)
        UpdateCheck.setEnabled(false, p)
        #expect(UpdateCheck.available(p, current: "0.1.0") == nil)
        #expect(!UpdateCheck.enabled(p))
    }

    @Test func promptsOncePerVersion() throws {
        let p = try prefs()
        #expect(UpdateCheck.pendingPrompt(p, current: "0.1.0") == nil)
        UpdateCheck.store(.init(version: "0.2.0", url: UpdateCheck.releasesPage), p)
        let r = try #require(UpdateCheck.pendingPrompt(p, current: "0.1.0"))
        #expect(r.version == "0.2.0")
        #expect(UpdateCheck.pendingPrompt(p, current: "0.2.0") == nil)
        UpdateCheck.markPrompted(r, p)
        #expect(UpdateCheck.pendingPrompt(p, current: "0.1.0") == nil)
        #expect(UpdateCheck.available(p, current: "0.1.0") == r)
        UpdateCheck.store(.init(version: "0.3.0", url: UpdateCheck.releasesPage), p)
        #expect(UpdateCheck.pendingPrompt(p, current: "0.1.0")?.version == "0.3.0")
        UpdateCheck.setEnabled(false, p)
        #expect(UpdateCheck.pendingPrompt(p, current: "0.1.0") == nil)
    }

    /// 앱 번들의 Info.plist 버전은 bundle.sh 가 이 값을 읽어 넣는다. 형식이 깨지면 그 스크립트가 엉뚱한 값을 넣는다.
    @Test func appVersionIsSemver() {
        let parts = Symboard.version.split(separator: ".")
        #expect(parts.count == 3 && parts.allSatisfy { Int($0) != nil }, "\(Symboard.version)")
    }

    @Test func parsesInstallAsset() {
        let json = #"{"tag_name":"v0.7.0","html_url":"https://github.com/jikwon-labs/Symboard/releases/tag/v0.7.0","assets":[{"name":"notes.txt","browser_download_url":"https://example.com/notes.txt"},{"name":"Symboard.zip","browser_download_url":"https://github.com/jikwon-labs/Symboard/releases/download/v0.7.0/Symboard.zip"}]}"#
        #expect(UpdateCheck.parse(Data(json.utf8))?.asset == URL(string: "https://github.com/jikwon-labs/Symboard/releases/download/v0.7.0/Symboard.zip"))
        // zip 이 없거나 https 가 아니면 설치 주소는 비운다.
        #expect(UpdateCheck.parse(Data(#"{"tag_name":"v0.7.0","assets":[]}"#.utf8))?.asset == nil)
        #expect(UpdateCheck.parse(Data(#"{"tag_name":"v0.7.0","assets":[{"name":"Symboard.zip","browser_download_url":"http://x/Symboard.zip"}]}"#.utf8))?.asset == nil)
    }

    @Test func cachesAssetAndReadsOldFormat() throws {
        let p = try prefs()
        let zip = URL(string: "https://github.com/x/Symboard.zip")!
        UpdateCheck.store(.init(version: "0.7.0", url: UpdateCheck.releasesPage, asset: zip), p)
        #expect(UpdateCheck.cached(p)?.asset == zip)
        // 예전 버전이 남긴 두 칸짜리.
        p.set("0.6.0\t\(UpdateCheck.releasesPage.absoluteString)", for: UpdateCheck.latestKey)
        #expect(UpdateCheck.cached(p) == .init(version: "0.6.0", url: UpdateCheck.releasesPage))
    }

    @Test func readsTeamID() {
        let signed = "Executable=/Applications/Symboard.app/Contents/MacOS/Symboard\nIdentifier=local.symboard.app\nTeamIdentifier=K6599UJ4KM\nSealed Resources version=2"
        #expect(UpdateInstall.teamID(fromCodesign: signed) == "K6599UJ4KM")
        #expect(UpdateInstall.teamID(fromCodesign: "Signature=adhoc\nTeamIdentifier=not set") == nil)
        #expect(UpdateInstall.teamID(fromCodesign: "code object is not signed at all") == nil)
        #expect(UpdateInstall.isTranslocated("/private/var/folders/x/AppTranslocation/ABC/d/Symboard.app"))
        #expect(!UpdateInstall.isTranslocated("/Applications/Symboard.app"))
    }

    @Test func acceptsOnlySameDeveloperAndVersion() {
        func check(cur: String? = "T1", new: String? = "T1", valid: Bool = true, id: String? = "local.symboard.app", ver: String? = "0.7.0") -> UpdateInstall.Problem? {
            UpdateInstall.accept(currentTeam: cur, newTeam: new, signatureValid: valid,
                                 currentBundleID: "local.symboard.app", newBundleID: id,
                                 expectedVersion: "v0.7.0", newVersion: ver)
        }
        #expect(check() == nil)
        #expect(check(cur: nil) == .unsignedCurrent)
        #expect(check(new: "OTHER") == .signatureMismatch)
        #expect(check(new: nil) == .signatureMismatch)
        #expect(check(valid: false) == .signatureMismatch)
        #expect(check(id: "com.evil.app") == .badArchive)
        #expect(check(ver: "0.6.9") == .badArchive)
        #expect(check(ver: nil) == .badArchive)
    }

    /// 도우미 스크립트를 가짜 앱 폴더로 실제로 돌린다. `open` 은 기록만 하는 가짜로 바꾼다.
    @Test func swapScriptReplacesAndRestores() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let log = root.appendingPathComponent("opened.txt")
        let fakeOpen = bin.appendingPathComponent("open")
        try "#!/bin/sh\necho \"$1\" >> \"\(log.path)\"\n".write(to: fakeOpen, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeOpen.path)
        let script = root.appendingPathComponent("swap.sh")
        try UpdateInstall.swapScript.write(to: script, atomically: true, encoding: .utf8)

        func makeApp(_ url: URL, _ mark: String) throws {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try mark.write(to: url.appendingPathComponent("mark"), atomically: true, encoding: .utf8)
        }
        func swap(new: URL, dest: URL, work: URL) throws -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            // 이미 끝난 pid: 기다리지 않고 바로 바꾼다.
            let dead = Process()
            dead.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            try dead.run(); dead.waitUntilExit()
            p.arguments = [script.path, String(dead.processIdentifier), new.path, dest.path, work.path]
            p.environment = ["PATH": "\(bin.path):/usr/bin:/bin"]
            try p.run(); p.waitUntilExit()
            return p.terminationStatus
        }

        // 1) 새 앱으로 바꾸고 작업 폴더를 지운다.
        let dest = root.appendingPathComponent("Apps/Symboard.app")
        try makeApp(dest, "old")
        let work = root.appendingPathComponent("work")
        let new = work.appendingPathComponent("new/Symboard.app")
        try makeApp(new, "new")
        #expect(try swap(new: new, dest: dest, work: work) == 0)
        #expect(try String(contentsOf: dest.appendingPathComponent("mark"), encoding: .utf8) == "new")
        #expect(!fm.fileExists(atPath: work.path))
        #expect(try String(contentsOf: log, encoding: .utf8) == dest.path + "\n")

        // 2) 새 앱이 없으면 옛 앱을 되돌려 놓고 연다.
        let work2 = root.appendingPathComponent("work2")
        try fm.createDirectory(at: work2, withIntermediateDirectories: true)
        #expect(try swap(new: work2.appendingPathComponent("missing.app"), dest: dest, work: work2) != 0)
        #expect(try String(contentsOf: dest.appendingPathComponent("mark"), encoding: .utf8) == "new")
    }
}
