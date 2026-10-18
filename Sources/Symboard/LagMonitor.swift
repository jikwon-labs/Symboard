import Foundation

/// 시험용: SYMBOARD_LAGLOG=1 이면 0.1초마다 메인 스레드에 일을 넣고 실제로 돌기까지 걸린 시간을 잰다.
/// 5초마다 p50·p95·최대를 표준 오류에 남긴다. 타이핑·끌기가 늦어지는지를 숫자로 보려는 것이다.
final class LagMonitor: @unchecked Sendable {
    static let shared = LagMonitor()
    private let queue = DispatchQueue(label: "symboard.lag")
    private var samples: [Double] = []
    private let lock = NSLock()

    func startIfRequested() {
        guard ProcessInfo.processInfo.environment["SYMBOARD_LAGLOG"] == "1" else { return }
        tick()
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.report() }
    }

    private func tick() {
        let sent = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.main.async { [weak self] in
            let ms = Double(DispatchTime.now().uptimeNanoseconds - sent) / 1e6
            guard let self else { return }
            self.lock.lock(); self.samples.append(ms); self.lock.unlock()
            self.queue.asyncAfter(deadline: .now() + 0.1) { self.tick() }
        }
    }

    private func report() {
        lock.lock(); let s = samples.sorted(); samples.removeAll(); lock.unlock()
        if !s.isEmpty {
            let p = { (q: Double) in s[min(s.count - 1, Int(Double(s.count) * q))] }
            FileHandle.standardError.write(String(format: "LAG n=%d p50=%.1fms p95=%.1fms max=%.1fms\n", s.count, p(0.5), p(0.95), s.last!).data(using: .utf8)!)
        } else {
            FileHandle.standardError.write("LAG n=0 (main thread blocked for 5s)\n".data(using: .utf8)!)
        }
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.report() }
    }
}
