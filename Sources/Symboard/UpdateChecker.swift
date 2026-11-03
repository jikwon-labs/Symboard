import AppKit
import SymboardCore

/// 하루에 한 번 GitHub 최신 릴리스를 묻고, 지금보다 높으면 위쪽 막대 알약(ChromeModel.update)에 넣는다.
/// 받기·설치는 하지 않는다. 알약을 누르면 릴리스 페이지를 연다.
/// 새 버전을 처음 알게 되면 창에 안내 시트를 한 번 띄운다(버전마다 한 번, 그 뒤로는 알약만).
/// 시험용: SYMBOARD_NO_UPDATE_CHECK=1 이면 묻지 않는다(남겨 둔 결과만 보인다).
@MainActor
final class UpdateChecker {
    private weak var chrome: ChromeModel?
    /// 안내 시트를 붙일 창. 없으면 따로 뜨는 알림 창으로 묻는다.
    weak var window: NSWindow?
    private var prompting = false
    /// 안내가 떠 있는 동안 또 띄우지 않는다(자동 안내와 "지금 확인"이 겹칠 때).
    private var alertOpen = false
    private var timer: Timer?
    private var inFlight = false
    private let prefs: Prefs
    static let disabledByEnv = ProcessInfo.processInfo.environment["SYMBOARD_NO_UPDATE_CHECK"] == "1"

    init(chrome: ChromeModel, prefs: Prefs = .shared) {
        self.chrome = chrome
        self.prefs = prefs
        publish()
        // 창이 먼저 뜨게 조금 늦추고, 켜 둔 채로 며칠 가도 알도록 몇 시간마다 다시 본다(실제 요청은 하루 한 번).
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    /// 설정에서 켜고 끌 때 알약을 바로 맞춘다.
    func settingChanged() {
        publish()
        checkIfDue()
    }

    func checkIfDue() {
        guard !Self.disabledByEnv, UpdateCheck.enabled(prefs), UpdateCheck.isDue(prefs), !inFlight else { return }
        inFlight = true
        fetch { [weak self] _ in self?.inFlight = false }
    }

    enum Outcome { case newer(UpdateCheck.Release), upToDate, failed }

    /// 설정의 "지금 확인". 자동 확인을 꺼 두었거나 오늘 이미 물었어도 바로 묻는다.
    /// 새 버전이면 같은 버전을 전에 물었더라도 `window` 에 안내를 다시 띄운다.
    func checkNow(sheetOn window: NSWindow?, done: @escaping (Outcome) -> Void) {
        fetch { [weak self] release in
            guard let self else { return }
            guard let release else { done(.failed); return }
            guard UpdateCheck.isNewer(release.version, than: Symboard.version) else { done(.upToDate); return }
            done(.newer(release))
            self.showPrompt(release, on: window)
        }
    }

    /// GitHub 최신 릴리스를 묻는다. 받은 결과는 남기고 알약을 맞춘 뒤 메인 스레드에서 넘긴다.
    private func fetch(_ done: @escaping (UpdateCheck.Release?) -> Void) {
        var req = URLRequest(url: UpdateCheck.latestURL, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Symboard/\(Symboard.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            let release = ok ? data.flatMap(UpdateCheck.parse) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // 실패(오프라인·요청 제한)는 남기지 않아서 다음 차례에 다시 묻는다.
                    if let release { UpdateCheck.store(release, self.prefs) }
                    self.publish()
                    done(release)
                }
            }
        }.resume()
    }

    private func publish() {
        let r = UpdateCheck.available(prefs)
        if chrome?.update != r { chrome?.update = r }
        if UpdateCheck.pendingPrompt(prefs) != nil, !prompting {
            prompting = true
            // 창이 자리 잡은 뒤에 묻는다(켜자마자 남겨 둔 결과로 부를 때도 있다).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.prompt() }
        }
    }

    private func prompt() {
        guard let r = UpdateCheck.pendingPrompt(prefs) else { prompting = false; return }
        // 시트가 이미 떠 있으면(다른 물음) 끝날 때까지 미룬다.
        if let w = window, w.attachedSheet != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.prompt() }
            return
        }
        showPrompt(r, on: window)
    }

    private func showPrompt(_ r: UpdateCheck.Release, on target: NSWindow?) {
        guard !alertOpen else { return }
        UpdateCheck.markPrompted(r, prefs)
        alertOpen = true
        let a = NSAlert()
        a.messageText = L("Symboard %@ is available", r.version)
        a.informativeText = L("You have %@. Download the new version from the release page and replace the app in Applications.", Symboard.version)
        a.addButton(withTitle: L("Download"))
        a.addButton(withTitle: L("Later"))
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            self?.alertOpen = false
            self?.prompting = false
            if resp == .alertFirstButtonReturn { NSWorkspace.shared.open(r.url) }
        }
        if let w = target, w.isVisible, w.attachedSheet == nil {
            a.beginSheetModal(for: w, completionHandler: done)
        } else {
            done(a.runModal())
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(chrome?.update?.url ?? UpdateCheck.releasesPage)
    }
}
