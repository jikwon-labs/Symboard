import AppKit
import SymboardCore

/// 하루에 한 번 GitHub 최신 릴리스를 묻고, 지금보다 높으면 위쪽 막대 알약(ChromeModel.update)에 넣는다.
/// 받기·설치는 하지 않는다. 알약을 누르면 릴리스 페이지를 연다.
/// 시험용: SYMBOARD_NO_UPDATE_CHECK=1 이면 묻지 않는다(남겨 둔 결과만 보인다).
@MainActor
final class UpdateChecker {
    private weak var chrome: ChromeModel?
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
        var req = URLRequest(url: UpdateCheck.latestURL, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Symboard/\(Symboard.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            let release = ok ? data.flatMap(UpdateCheck.parse) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.inFlight = false
                    // 실패(오프라인·요청 제한)는 남기지 않아서 다음 차례에 다시 묻는다.
                    if let release { UpdateCheck.store(release, self.prefs) }
                    self.publish()
                }
            }
        }.resume()
    }

    private func publish() {
        let r = UpdateCheck.available(prefs)
        if chrome?.update != r { chrome?.update = r }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(chrome?.update?.url ?? UpdateCheck.releasesPage)
    }
}
