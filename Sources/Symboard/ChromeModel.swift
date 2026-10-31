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
    case calendar
    case shape(String)

    var size: CGSize {
        switch self {
        case .agent: return CGSize(width: 640, height: 400)
        case .text: return CGSize(width: 520, height: 90)
        case .sticky: return CGSize(width: 240, height: 220)
        case .checklist: return CGSize(width: 300, height: 320)
        case .kanban: return CGSize(width: 990, height: 440)
        case .web: return CGSize(width: 820, height: 600)
        case .orchestrator: return CGSize(width: 380, height: 500)
        case .calendar: return CGSize(width: 560, height: 470)
        case .shape(let k): return k == "arrow" ? CGSize(width: 240, height: 60) : (k == "rect" ? CGSize(width: 220, height: 130) : CGSize(width: 180, height: 160))
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
    @Published var workingCount = 0
    @Published var branch: String?
    @Published var changeCount = 0
    @Published var command = ""
    /// 값이 바뀌면 명령 바 입력칸에 초점을 준다.
    @Published var focusCommand = 0
    /// 단축키 표(? 단추·? 키).
    @Published var shortcutsOpen = false
    @Published var selectedNodeID: UUID?
    @Published var showingHome = false
    @Published var spawnMenuOpen = false
    @Published var panelOpen = false
    @Published var suggestion: String? = "Try \"@all git status\""
    /// 모달·팝오버가 하나라도 열려 있으면 true. 안내 알약을 숨긴다.
    @Published var overlayOpen = false
    @Published var toast: String?
    @Published var loopBadge = 0
    @Published var resetText = UsagePill.placeholder
    /// CLI `/usage` 의 세션 % (없으면 nil, 로그 짐작값만 보일 때).
    @Published var sessionPercent: Int?
    @Published var sessionTint = "#E8704A"
    /// 이어하기 답을 기다리는 콘솔 수와 토스트를 닫았는지.
    @Published var missionOpen = false
    @Published var insertOpen = false
    @Published var shapeOpen = false
    /// 아래 왼쪽 브랜치 칩에서 여는 git 카드.
    @Published var gitCard: GitCardModel?
    @Published var gitOpen = false
    @Published var usageOpen = false
    @Published var accountsOpen = false
    /// 지금보다 높은 GitHub 릴리스(UpdateChecker). 있으면 위쪽 오른쪽에 알약을 띄운다.
    @Published var update: UpdateCheck.Release?
    @Published var penColor = "#F05A38"
    @Published var penWidth = 3.0
    /// 루프 모달: nil 이면 닫힘, "list"·"gallery"·"form".
    @Published var loopsPage: String?
    @Published var missionSelected: UUID?
    @Published var resumeCount = 0
    /// Connect 를 누른 오케스트레이터. 이때 보드의 콘솔을 누르면 연결/해제된다.
    @Published var connectingOrchestrator: UUID?
    @Published var resumeDismissed = false
    /// 확인을 기다리는 동작(여러 콘솔 닫기 등).
    @Published var confirm: PendingConfirm?
    /// 명령 바 THREAD 패널: 보드 명령과 그 결과(원본 voice 장면의 기록 자리).
    @Published var thread = CommandThread()
    @Published var threadOpen = false
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
    /// true 면 아래 확인 띠 대신 THREAD 안에 Confirm · Cancel 로 보인다.
    var inThread = false
    var onCancel: (() -> Void)? = nil
}
