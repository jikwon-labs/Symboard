import AppKit
import SymboardCore

/// 하루에 한 번 GitHub 최신 릴리스를 묻고, 지금보다 높으면 위쪽 막대 알약(ChromeModel.update)에 넣는다.
/// 새 버전을 처음 알게 되면 창에 안내 시트를 한 번 띄운다(버전마다 한 번, 그 뒤로는 알약만). 알약을 누르면 같은 안내가 다시 뜬다.
/// "설치하고 다시 열기" 를 고르면 UpdateInstaller 가 받아서 바꿔 끼우고 다시 연다. 못 하면 까닭을 알리고 릴리스 페이지로 보낸다.
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
    private var installing = false
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
        guard !alertOpen, !installing else { return }
        UpdateCheck.markPrompted(r, prefs)
        alertOpen = true
        let a = NSAlert()
        a.messageText = L("Symboard %@ is available", r.version)
        a.informativeText = KeepConsolesPrefs.enabled(prefs)
            ? L("You have %@. Symboard downloads the new version, replaces itself and opens again. Consoles keep running.", Symboard.version)
            : L("You have %@. Symboard downloads the new version, replaces itself and opens again. Running consoles stop and come back when it opens.", Symboard.version)
        a.addButton(withTitle: L("Install and Restart"))
        a.addButton(withTitle: L("Later"))
        a.addButton(withTitle: L("Release Page"))
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard let self else { return }
            self.alertOpen = false
            self.prompting = false
            switch resp {
            case .alertFirstButtonReturn: self.install(r)
            case .alertThirdButtonReturn: NSWorkspace.shared.open(r.url)
            default: break
            }
        }
        present(a, on: target, done)
    }

    private func present(_ a: NSAlert, on target: NSWindow?, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = target, w.isVisible, w.attachedSheet == nil {
            a.beginSheetModal(for: w, completionHandler: done)
        } else {
            done(a.runModal())
        }
    }

    /// 받기·검사가 끝나면 도우미를 띄우고 앱을 끈다. 남겨 둔 결과에 zip 주소가 없으면(예전 버전이 남긴 것) 먼저 다시 묻는다.
    private func install(_ r: UpdateCheck.Release) {
        guard !installing else { return }
        installing = true
        chrome?.updateInstalling = true
        Task { @MainActor [weak self] in
            var release = r
            if release.asset == nil, let fresh = await self?.fetchLatest() { release = fresh }
            do {
                let prepared = try await UpdateInstaller.prepare(release)
                try UpdateInstaller.launchSwap(prepared)
                AppDelegate.skipQuitConfirm = true
                NSApp.terminate(nil)
            } catch {
                guard let self else { return }
                self.installing = false
                self.chrome?.updateInstalling = false
                self.showFailure(error as? UpdateInstaller.Problem ?? .downloadFailed, release)
            }
        }
    }

    private func fetchLatest() async -> UpdateCheck.Release? {
        await withCheckedContinuation { cont in fetch { cont.resume(returning: $0) } }
    }

    private func showFailure(_ p: UpdateInstaller.Problem, _ r: UpdateCheck.Release) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = L("Couldn't install the update")
        a.informativeText = UpdateInstaller.message(p)
        a.addButton(withTitle: L("Open the release page"))
        a.addButton(withTitle: L("OK"))
        present(a, on: window) { resp in
            if resp == .alertFirstButtonReturn { NSWorkspace.shared.open(r.url) }
        }
    }

    /// 위쪽 막대 알약. 안내를 다시 띄운다(설치 중이면 아무것도 하지 않는다).
    func pillClicked() {
        guard let r = chrome?.update else { openReleasePage(); return }
        showPrompt(r, on: window)
    }

    func openReleasePage() {
        NSWorkspace.shared.open(chrome?.update?.url ?? UpdateCheck.releasesPage)
    }
}
