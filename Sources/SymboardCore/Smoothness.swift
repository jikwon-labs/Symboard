import Foundation

/// 같은 마우스 커서를 짧은 사이에 다시 거는 것을 거른다(성능 점검 2차).
///
/// 보드나 노드가 움직이는 프레임마다 AppKit 과 SwiftTerm 이 마우스 아래 커서를 다시 건다. 손쉬운 사용에서 포인터 색·크기를
/// 바꿔 둔 맥에서는 커서를 걸 때마다 시스템이 커서 그림을 새로 만들어서, 보드를 옮길 때 메인 스레드의 4분의 1 이상을 썼다.
/// 지금 걸린 커서와 같고 마지막으로 실제로 건 지 `window` 초가 안 됐으면 건너뛴다. 시간 제한을 둔 것은 다른 앱·창 가장자리가
/// 커서를 바꿔 두었는데 우리 쪽 기록만 같다고 믿고 계속 건너뛰는 일이 없게 하기 위해서다(길어야 `window` 초 뒤에 바로잡힌다).
public struct CursorDedupe<ID: Hashable>: Sendable where ID: Sendable {
    public static var window: TimeInterval { 0.25 }
    private var lastID: ID?
    private var lastAt: TimeInterval = -.infinity

    public init() {}

    /// true 면 건너뛴다. false 면 실제로 걸 차례이고, 그 시각을 적어 둔다.
    public mutating func shouldSkip(_ id: ID, isCurrent: Bool, now: TimeInterval) -> Bool {
        if isCurrent, id == lastID, now - lastAt < Self.window { return true }
        lastID = id
        lastAt = now
        return false
    }

    /// 앱이 앞으로 오거나 뒤로 갈 때처럼 커서가 바깥에서 바뀌었을 수 있으면 기록을 지운다.
    public mutating func reset() {
        lastID = nil
        lastAt = -.infinity
    }
}

/// 마지막 요청만 조금 뒤에 실행할지 정하는 시계(확대·축소가 멎었는지, 콘솔 크기 바꾸기를 모을지).
/// 실제 예약(DispatchWorkItem)은 앱이 하고, 여기서는 "언제 끝났다고 볼지" 만 계산한다.
public struct QuietTimer: Sendable {
    public let quiet: TimeInterval
    public private(set) var lastPoke: TimeInterval = -.infinity

    public init(quiet: TimeInterval) { self.quiet = quiet }

    /// 새 움직임. 이번이 시작(그전에는 조용했음)이면 true.
    @discardableResult
    public mutating func poke(now: TimeInterval) -> Bool {
        let started = now - lastPoke >= quiet
        lastPoke = now
        return started
    }

    /// 마지막 움직임 뒤로 충분히 조용했는지.
    public func isQuiet(now: TimeInterval) -> Bool { now - lastPoke >= quiet }

    /// 조용해지기까지 남은 시간.
    public func remaining(now: TimeInterval) -> TimeInterval { max(0, quiet - (now - lastPoke)) }
}
