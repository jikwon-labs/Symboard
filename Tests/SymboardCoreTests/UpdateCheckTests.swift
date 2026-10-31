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

    /// 앱 번들의 Info.plist 버전은 bundle.sh 가 이 값을 읽어 넣는다. 형식이 깨지면 그 스크립트가 엉뚱한 값을 넣는다.
    @Test func appVersionIsSemver() {
        let parts = Symboard.version.split(separator: ".")
        #expect(parts.count == 3 && parts.allSatisfy { Int($0) != nil }, "\(Symboard.version)")
    }
}
