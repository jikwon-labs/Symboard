import AppKit
import SwiftUI
import SymboardCore

/// 캔버스를 클릭해 놓을 것.
enum Placement: Equatable {
    case agent(String)
    case text
    case sticky
    case checklist
    case kanban
    case web

    var size: CGSize {
        switch self {
        case .agent: return CGSize(width: 640, height: 400)
        case .text: return CGSize(width: 520, height: 90)
        case .sticky: return CGSize(width: 240, height: 220)
        case .checklist: return CGSize(width: 300, height: 320)
        case .kanban: return CGSize(width: 900, height: 420)
        case .web: return CGSize(width: 760, height: 520)
        }
    }

    var hint: String {
        switch self {
        case .agent: return "Click the canvas to drop the agent · Esc to cancel"
        case .text: return "Click the canvas to place text · Esc to cancel"
        default: return "Click the canvas to place it · Esc to cancel"
        }
    }
}

enum BoardTool: Equatable {
    case select
    case pen
    case eraser
    case place(Placement)
}

/// 떠 있는 막대들이 함께 보는 화면 상태. 저장하지 않는다.
@MainActor
final class ChromeModel: ObservableObject {
    @Published var tool: BoardTool = .select
    @Published var zoomPercent = 100
    @Published var liveCount = 0
    @Published var branch: String?
    @Published var changeCount = 0
    @Published var command = ""
    @Published var selectedNodeID: UUID?
    @Published var showingHome = false
    @Published var spawnMenuOpen = false
    @Published var panelOpen = false
    @Published var suggestion: String? = "Try \"@all git status\""
    @Published var toast: String?
    @Published var loopBadge = 0
    @Published var resetText = "usage"
    private var toastWork: DispatchWorkItem?

    func flash(_ text: String) {
        toast = text
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: w)
    }
}
