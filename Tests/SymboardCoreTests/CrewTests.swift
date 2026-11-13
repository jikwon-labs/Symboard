import Foundation
import Testing
@testable import SymboardCore

@Suite struct CrewTests {
    @Test func crewOverridesOpenerAndSetting() {
        for open in [true, false] {
            for lead in [true, false] {
                #expect(BoardTools.role(openedByAgent: open, leadDelegates: lead, crew: .ceo) == .ceo)
                #expect(BoardTools.role(openedByAgent: open, leadDelegates: lead, crew: .cto) == .crew(.cto))
            }
        }
        // 역할이 없으면 예전 그대로.
        #expect(BoardTools.role(openedByAgent: false, leadDelegates: true, crew: nil) == .lead)
        #expect(BoardTools.role(openedByAgent: true, leadDelegates: true, crew: nil) == .worker)
    }

    @Test func staffExcludesCEO() {
        #expect(Crew.staff == [.planner, .designer, .frontend, .backend, .cto])
        #expect(Set(Crew.allCases.map(\.consoleName)).count == Crew.allCases.count)
    }

    @Test func ceoCallsOnlyWhenNeeded() {
        let p = BoardTools.systemPrompt(for: .ceo)
        #expect(p == Crew.ceo.systemPrompt)
        #expect(p.contains("only when they are really needed") && p.contains("Never open every role"))
        #expect(p.contains("why it is needed") && p.contains("one console per role") && p.contains("two rounds"))
        #expect(p.contains(WorkerReport.tag) && p.contains("could not confirm") && p.contains("send_to_console"))
        for c in Crew.staff { #expect(p.contains("\"\(c.rawValue)\"")) }
    }

    @Test func staffPromptsCarryTheirSpecialty() {
        let planner = BoardTools.systemPrompt(for: .crew(.planner))
        #expect(planner.contains("search the web") && planner.contains("source URL") && planner.contains("Never invent numbers"))
        let designer = BoardTools.systemPrompt(for: .crew(.designer))
        #expect(designer.contains("at least three") && designer.contains("show_references") && designer.contains("recommend one"))
        let cto = BoardTools.systemPrompt(for: .crew(.cto))
        #expect(cto.contains("git diff") && cto.contains("APPROVED") && cto.contains("CHANGES REQUESTED") && cto.contains("Do not fix"))
        for c in [Crew.frontend, .backend] {
            let p = BoardTools.systemPrompt(for: .crew(c))
            #expect(p.contains("files or folders the CEO gave you") && p.contains("API contract"))
        }
        for c in Crew.staff {
            let p = c.systemPrompt
            #expect(p.contains("as its \(c.rawValue)") && p.contains("Do not open more consoles") && p.contains("tells the CEO"))
            #expect(p.contains("add_note") && p.contains("limit") && !p.contains("\\\n"))
        }
        #expect(BoardTools.claudeArgs(configPath: "/x", role: .crew(.cto)).last == Crew.cto.systemPrompt)
    }

    @Test func spawnToolOffersRolesAndReferencesTool() throws {
        let tools = BoardTools.toolDefinitions
        let spawn = try #require(tools.first { $0["name"] as? String == "spawn_console" })
        let schema = try #require(spawn["inputSchema"] as? [String: Any])
        let props = try #require(schema["properties"] as? [String: [String: Any]])
        #expect(props["role"]?["enum"] as? [String] == Crew.staff.map(\.rawValue))
        // 덧붙이기만: 필수 인자는 그대로.
        #expect(schema["required"] as? [String] == ["agent"])
        #expect(tools.contains { $0["name"] as? String == "show_references" })
        #expect(try JSONSerialization.data(withJSONObject: tools).count > 0)
    }

    @Test func crewDecodesFromOldState() throws {
        let old = #"{"agent":"claude","extraArgs":[],"cwd":"/tmp","hasLaunched":true}"#
        let spec = try JSONDecoder().decode(TerminalSpec.self, from: Data(old.utf8))
        #expect(spec.crew == nil)
        var s = spec; s.crew = Crew.designer.rawValue
        let back = try JSONDecoder().decode(TerminalSpec.self, from: JSONEncoder().encode(s))
        #expect(back.crew.flatMap(Crew.init(rawValue:)) == .designer)
    }

    @Test func referencesParseOnlyWebAddresses() {
        let ok = ReferenceBoard.parse([
            ["url": "https://a.example/x", "label": "A", "note": "header"],
            ["url": "ftp://b.example", "label": "B"],
            ["url": "https://a.example/x", "label": "dup"],
            ["url": "http://c.example", "label": " "],
        ])
        #expect(ok?.map(\.url) == ["https://a.example/x", "http://c.example"])
        #expect(ok?.last?.label == "c.example" && ok?.first?.note == "header")
        #expect(ReferenceBoard.parse([["url": "https://a.example", "label": "A"]]) == nil)
        let many = (0..<7).map { ["url": "https://e\($0).example", "label": "\($0)"] }
        #expect(ReferenceBoard.parse(many) == nil)
        #expect(ReferenceBoard.parse("nope") == nil)
    }

    @Test func referencesLayInRowsOfThree() {
        let t = ReferenceBoard.tileSize, g = ReferenceBoard.gap
        let two = ReferenceBoard.footprint(count: 2)
        #expect(two.w == t.w * 2 + g && two.h == t.h)
        let five = ReferenceBoard.footprint(count: 5)
        #expect(five.w == t.w * 3 + g * 2 && five.h == t.h * 2 + g)
        let o = Point(x: 100, y: 50)
        #expect(ReferenceBoard.frame(index: 1, origin: o).x == 100 + t.w + g)
        let fourth = ReferenceBoard.frame(index: 3, origin: o)
        #expect(fourth.x == 100 && fourth.y == 50 + t.h + g)
    }
}
