import Foundation
import Testing
@testable import SymboardCore

@Suite struct CanvasInputTests {
    /// 배율 0.51 에서 원점 (100, 500) 인 flipped 뷰의 로컬 (911, 272) 을 누른 경우:
    /// SwiftUI 가 (창 x − 원점 x, 원점 y − 창 y) 를 계산했을 때 (911, 272) 가 나와야 한다.
    @Test func flippedViewRoundTrip() {
        let p = CanvasInput.unscaledWindowPoint(localX: 911, localY: 272, originX: 100, originY: 500, flipped: true)
        #expect(p.x - 100 == 911)
        #expect(500 - p.y == 272)
    }

    @Test func unflippedView() {
        let p = CanvasInput.unscaledWindowPoint(localX: 10, localY: 20, originX: 5, originY: 5, flipped: false)
        #expect(p.x == 15 && p.y == 25)
    }
}

@Suite struct ComposerResizeTests {
    @Test func growUsesLastFillChoice() {
        // Fill all Shell 뒤 마지막 타일만 Claude 로 돌렸어도 새 타일은 Shell.
        let t = Composer.resize(tiles: ["shell", "shell", "shell", "claude"], to: 6, fill: "shell", fallback: "claude")
        #expect(t == ["shell", "shell", "shell", "claude", "shell", "shell"])
    }

    @Test func growWithoutFillUsesPreviousTile() {
        #expect(Composer.resize(tiles: ["codex"], to: 3, fill: nil, fallback: "claude") == ["codex", "codex", "codex"])
    }

    @Test func shrinkAndClamp() {
        #expect(Composer.resize(tiles: ["a", "b", "c"], to: 0, fill: nil, fallback: "x") == ["a"])
        #expect(Composer.resize(tiles: [], to: 2, fill: nil, fallback: "x") == ["x", "x"])
        #expect(Composer.resize(tiles: ["a"], to: 99, fill: nil, fallback: "x").count == Composer.maxNodes)
    }
}

@Suite struct ShellStatusTests {
    let t0 = Date(timeIntervalSince1970: 1000)

    @Test func shellAtPromptIsReadyEvenWhilePromptRedraws() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteOutput(at: t0.addingTimeInterval(1))
        // 방금 출력이 있었어도(프롬프트 다시 그리기) 셸이 앞에 있으면 READY.
        #expect(t.status(now: t0.addingTimeInterval(1.5), shellAtPrompt: true) == .idle)
    }

    @Test func runningCommandIsWorkingEvenWhenQuiet() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteOutput(at: t0.addingTimeInterval(1))
        #expect(t.status(now: t0.addingTimeInterval(60), shellAtPrompt: false) == .working)
    }

    @Test func startingUntilFirstOutput() {
        let t = StatusTracker(usesHooks: false, startedAt: t0)
        #expect(t.status(now: t0.addingTimeInterval(0.5), shellAtPrompt: true) == .starting)
        #expect(t.status(now: t0.addingTimeInterval(5), shellAtPrompt: true) == .idle)
    }

    @Test func withoutShellInfoFallsBackToOutputTiming() {
        var t = StatusTracker(usesHooks: false, startedAt: t0)
        t.noteOutput(at: t0.addingTimeInterval(1))
        #expect(t.status(now: t0.addingTimeInterval(2)) == .working)
        #expect(t.status(now: t0.addingTimeInterval(10)) == .idle)
    }
}

@Suite struct CanvasLayoutTests {
    let safe = Rect(x: 0, y: 0, w: 1000, h: 600)

    @Test func insideStaysPut() {
        let f = Rect(x: 100, y: 100, w: 300, h: 200)
        #expect(CanvasLayout.fit(f, in: safe) == f)
    }

    @Test func leftAndBottomEdgesArePulledIn() {
        let f = CanvasLayout.fit(Rect(x: -150, y: 500, w: 300, h: 200), in: safe)
        #expect(f.x == 0 && f.y == 400)
    }

    @Test func tooBigAlignsToStart() {
        let f = CanvasLayout.fit(Rect(x: 400, y: -50, w: 1200, h: 200), in: safe)
        #expect(f.x == 0 && f.y == 0)
    }
}

@Suite struct PrefsTests {
    @Test func valuesLiveInsideTheGivenFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("prefs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = Prefs(directory: dir)
        #expect(a.string("lastCwd") == nil)
        a.set("/tmp/x", for: "lastCwd")
        a.set(12.5, for: "docTiming.quick")
        let b = Prefs(directory: dir)
        #expect(b.string("lastCwd") == "/tmp/x")
        #expect(b.double("docTiming.quick") == 12.5)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("prefs.json").path))
        // 다른 폴더에는 따라가지 않는다.
        let other = dir.appendingPathComponent("other")
        #expect(Prefs(directory: other).string("lastCwd") == nil)
    }
}

@Suite struct UsagePillTests {
    let utc = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00 UTC

    @Test func unknownShowsPlaceholderInSameShape() {
        #expect(UsagePill.text(blockEnds: [], now: now) == UsagePill.placeholder)
        #expect(UsagePill.placeholder.hasPrefix("resets "))
    }

    @Test func pastBlocksAreIgnored() {
        #expect(UsagePill.text(blockEnds: [now.addingTimeInterval(-60)], now: now) == UsagePill.placeholder)
    }

    @Test func nearestFutureEnd() {
        let t = UsagePill.text(blockEnds: [now.addingTimeInterval(9 * 3600), now.addingTimeInterval(3600)], now: now, timeZone: utc)
        #expect(t == "resets 9:00am")
    }
}

@Suite struct KanbanDropTests {
    let a = UUID(), b = UUID(), c1 = UUID(), c2 = UUID()
    var cols: [(id: UUID, frame: Rect)] { [(a, Rect(x: 0, y: 0, w: 200, h: 400)), (b, Rect(x: 210, y: 0, w: 200, h: 400))] }

    @Test func emptyColumnAppends() {
        let r = Board.dropTarget(x: 300, y: 100, columns: cols, cards: [:])
        #expect(r?.column == b && r?.index == nil)
    }

    @Test func aboveACardInsertsBeforeIt() {
        let cards: [UUID: [(id: UUID, minY: Double, maxY: Double)]] = [a: [(c1, 40, 80), (c2, 90, 130)]]
        #expect(Board.dropTarget(x: 50, y: 95, columns: cols, cards: cards)?.index == 1)
        #expect(Board.dropTarget(x: 50, y: 20, columns: cols, cards: cards)?.index == 0)
        #expect(Board.dropTarget(x: 50, y: 300, columns: cols, cards: cards)?.index == nil)
    }

    @Test func outsideColumnsIsNil() {
        #expect(Board.dropTarget(x: 205, y: 100, columns: cols, cards: [:]) == nil)
    }

    @Test func movedCardLandsInTarget() {
        var columns = [KanbanColumn(title: "Doing", cards: []), KanbanColumn(title: "Done", cards: [])]
        columns[0].items = [KanbanCard(title: "Write tests")]
        let id = columns[0].items![0].id
        Board.move(card: id, to: columns[1].id, at: nil, in: &columns)
        #expect(columns[0].allCards.isEmpty && columns[1].allCards.map(\.title) == ["Write tests"])
    }
}
