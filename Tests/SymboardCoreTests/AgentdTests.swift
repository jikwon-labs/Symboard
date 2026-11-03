import Foundation
import Testing
@testable import SymboardCore

@Suite struct AgentdTests {
    @Test func frameRoundTrip() throws {
        let id = UUID()
        let frames = [
            AgentdFrame(.hello),
            AgentdFrame(.input, id: id, payload: Data("ls\r".utf8)),
            AgentdFrame(.spawn, id: id, json: AgentdSpawn(executable: "/bin/zsh", args: ["-l"], env: ["A=1"], cwd: "/tmp", cols: 80, rows: 24)),
        ]
        var reader = AgentdFrameReader()
        let got = try reader.feed(frames.map { $0.encoded() }.reduce(Data(), +))
        #expect(got == frames)
        #expect(got[2].decode(AgentdSpawn.self)?.cols == 80)
        #expect(got[0].id == AgentdFrame.noID)
    }

    @Test func readerHandlesSplitChunks() throws {
        let f = AgentdFrame(.output, id: UUID(), payload: Data(repeating: 0x41, count: 5000))
        let bytes = f.encoded() + AgentdFrame(.exit, id: f.id, json: AgentdExit(code: 0)).encoded()
        var reader = AgentdFrameReader()
        var out: [AgentdFrame] = []
        var i = 0
        while i < bytes.count {
            let j = min(bytes.count, i + 7)
            out += try reader.feed(bytes[i..<j])
            i = j
        }
        #expect(out.count == 2)
        #expect(out[0] == f)
        #expect(out[1].decode(AgentdExit.self)?.code == 0)
    }

    @Test func unknownKindIsKeptButHasNoKind() throws {
        // 앞으로 더할 종류는 옛 쪽에서 kind == nil 로 보이고 버려진다(약속은 덧붙이기만 한다).
        var reader = AgentdFrameReader()
        let got = try reader.feed(AgentdFrame(rawKind: 200, id: UUID(), payload: Data([1, 2])).encoded())
        #expect(got.count == 1)
        #expect(got[0].kind == nil)
    }

    @Test func readerRejectsOversizedFrame() {
        var reader = AgentdFrameReader()
        #expect(throws: AgentdFrameReader.ReadError.self) { try reader.feed(Data([0x7f, 0xff, 0xff, 0xff, 1])) }
    }

    @Test func outputRingTrimsAtLineBreak() {
        var ring = AgentdOutputRing(capacity: 100)
        ring.append(Array(repeating: UInt8(ascii: "a"), count: 60))
        ring.append(Array("\nline2\n".utf8))
        ring.append(Array(repeating: UInt8(ascii: "b"), count: 60))
        #expect(ring.data.count <= 100)
        // 잘린 자리 다음 줄바꿈부터 남는다.
        #expect(ring.data.first == UInt8(ascii: "l") || ring.data.first == UInt8(ascii: "b"))
        #expect(String(decoding: ring.data, as: UTF8.self).hasSuffix(String(repeating: "b", count: 60)))
    }

    @Test func outputRingKeepsSmallOutput() {
        var ring = AgentdOutputRing(capacity: 100)
        ring.append(Array("hello".utf8))
        #expect(ring.data == Data("hello".utf8))
    }

    @Test func socketPathFallsBackWhenLong() {
        #expect(AgentdPaths.socket(directory: "/tmp/sb", temporary: "/var/t") == "/tmp/sb/agentd.sock")
        let long = "/Users/someone/Library/Application Support/" + String(repeating: "x", count: 80)
        let p = AgentdPaths.socket(directory: long, temporary: "/var/t")
        #expect(p.hasPrefix("/var/t/symboard-agentd-"))
        #expect(p == AgentdPaths.socket(directory: long, temporary: "/var/t"))
        #expect(AgentdPaths.installed(directory: "/s", build: "abc") == "/s/agentd/abc/symboard-agentd")
    }

    @Test func upgradeOnlyWhenIdle() {
        let old = AgentdHello(build: "old", pid: 1)
        #expect(AgentdUpgrade.decide(daemon: old, appBuild: "new", sessions: 0) == .replace)
        #expect(AgentdUpgrade.decide(daemon: old, appBuild: "new", sessions: 2) == .use)
        #expect(AgentdUpgrade.decide(daemon: old, appBuild: "old", sessions: 0) == .use)
    }

    @Test func keepConsolesDefaultsOn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let prefs = Prefs(directory: dir)
        #expect(KeepConsolesPrefs.enabled(prefs))
        KeepConsolesPrefs.setEnabled(false, prefs)
        #expect(!KeepConsolesPrefs.enabled(prefs))
        KeepConsolesPrefs.setEnabled(true, prefs)
        #expect(KeepConsolesPrefs.enabled(prefs))
    }
}
