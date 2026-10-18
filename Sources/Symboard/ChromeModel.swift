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
    case orchestrator

    var size: CGSize {
        switch self {
        case .agent: return CGSize(width: 640, height: 400)
        case .text: return CGSize(width: 520, height: 90)
        case .sticky: return CGSize(width: 240, height: 220)
        case .checklist: return CGSize(width: 300, height: 320)
        case .kanban: return CGSize(width: 900, height: 420)
        case .web: return CGSize(width: 760, height: 520)
        case .orchestrator: return CGSize(width: 380, height: 500)
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
    /// 이어하기 답을 기다리는 콘솔 수와 토스트를 닫았는지.
    @Published var missionOpen = false
    /// 루프 모달: nil 이면 닫힘, "list"·"gallery"·"form".
    @Published var loopsPage: String?
    @Published var missionSelected: UUID?
    @Published var resumeCount = 0
    /// Connect 를 누른 오케스트레이터. 이때 보드의 콘솔을 누르면 연결/해제된다.
    @Published var connectingOrchestrator: UUID?
    @Published var resumeDismissed = false
    /// 확인을 기다리는 동작(여러 콘솔 닫기 등).
    @Published var confirm: PendingConfirm?
    private var toastWork: DispatchWorkItem?

    func flash(_ text: String) {
        toast = text
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: w)
    }
}

struct PendingConfirm: Identifiable {
    let id = UUID()
    var message: String
    var button: String
    var action: () -> Void
}
