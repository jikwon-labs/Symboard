import Foundation

/// 확대/축소된 캔버스 위 입력 좌표 계산.
public enum CanvasInput {
    /// SwiftUI 호스팅 뷰는 마우스 위치를 "창 좌표 − 자기 원점" 으로만 계산한다(배율 무시).
    /// 그 계산 결과가 실제 로컬 좌표 (localX, localY) 가 되도록 넘길 창 좌표를 돌려준다.
    /// - Parameters:
    ///   - localX, localY: 뷰 안의 실제 좌표(뷰 좌표계, flipped 면 아래로 증가).
    ///   - originX, originY: 뷰 좌표 (0,0) 의 창 좌표(창 좌표는 위로 증가).
    public static func unscaledWindowPoint(localX: Double, localY: Double, originX: Double, originY: Double,
                                           flipped: Bool) -> (x: Double, y: Double) {
        (originX + localX, flipped ? originY - localY : originY + localY)
    }
}

/// 새 노드를 화면에 보이는 자리로 옮기는 계산.
public enum CanvasLayout {
    /// frame 을 safe 안으로 옮긴다. 한 방향이 safe 보다 크면 그 방향은 safe 의 시작에 맞춘다.
    public static func fit(_ frame: Rect, in safe: Rect) -> Rect {
        var f = frame
        f.x = frame.w >= safe.w ? safe.x : min(max(frame.x, safe.x), safe.x + safe.w - frame.w)
        f.y = frame.h >= safe.h ? safe.y : min(max(frame.y, safe.y), safe.y + safe.h - frame.h)
        return f
    }

    /// 앱이 스스로 만든 노드처럼 자리를 옮기면 안 되는 것들을 보이게 할 때 쓴다.
    /// frames 를 모두 담는 사각형이 safe 안에 있으면 nil. 아니면 그 사각형 가운데로 화면을 옮길 중심과 배율.
    /// 배율은 지금보다 키우지 않고, 사각형이 safe 에 margin 을 두고 들어갈 만큼만 줄인다.
    public static func reveal(_ frames: [Rect], in safe: Rect, magnification: Double, margin: Double = 40) -> (center: Point, zoom: Double)? {
        guard let first = frames.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x + first.w, maxY = first.y + first.h
        for f in frames.dropFirst() {
            minX = min(minX, f.x); minY = min(minY, f.y); maxX = max(maxX, f.x + f.w); maxY = max(maxY, f.y + f.h)
        }
        if minX >= safe.x, minY >= safe.y, maxX <= safe.x + safe.w, maxY <= safe.y + safe.h { return nil }
        let fit = min(safe.w / (maxX - minX + margin * 2), safe.h / (maxY - minY + margin * 2))
        return (Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2), magnification * min(1, fit))
    }

    /// 보드 위에서 새 노드가 피해야 할 사각형들. 팀에 든 노드는 그룹 프레임(여백·머리 포함) 하나로, 나머지는 노드 하나씩.
    /// 접힌 팀은 접힌 프레임 크기만 차지한다. pad·head 는 GroupFrameView 와 같은 값.
    public static func obstacles(nodes: [BoardNode], teams: [Team], pad: Double = 14, head: Double = 30) -> [Rect] {
        var out: [Rect] = []
        let teamIDs = Set(teams.map(\.id))
        for n in nodes where n.teamID == nil || !teamIDs.contains(n.teamID!) { out.append(n.frame) }
        for t in teams {
            let members = nodes.filter { $0.teamID == t.id }
            guard let first = members.first else { continue }
            var minX = first.frame.x, minY = first.frame.y, maxX = first.frame.x + first.frame.w, maxY = first.frame.y + first.frame.h
            for m in members.dropFirst() {
                minX = min(minX, m.frame.x); minY = min(minY, m.frame.y)
                maxX = max(maxX, m.frame.x + m.frame.w); maxY = max(maxY, m.frame.y + m.frame.h)
            }
            if t.collapsed ?? false {
                out.append(Rect(x: minX - pad, y: minY - pad - head, w: 320, h: head + 52))
            } else {
                out.append(Rect(x: minX - pad, y: minY - pad - head, w: maxX - minX + pad * 2, h: maxY - minY + pad * 2 + head))
            }
        }
        return out
    }

    /// frame 이 obstacles 와 (gap 만큼 띄워서) 겹치지 않는 가장 가까운 자리. 겹치지 않으면 그대로.
    /// 후보는 원래 x·y 와 각 장애물의 네 변에 gap 을 두고 붙인 x·y 의 조합이라, 장애물 사이 틈도 찾는다.
    public static func nearestFree(_ frame: Rect, avoiding obstacles: [Rect], gap: Double = 24) -> Rect {
        func hits(_ f: Rect) -> Bool {
            obstacles.contains { o in
                f.x < o.x + o.w + gap && o.x < f.x + f.w + gap && f.y < o.y + o.h + gap && o.y < f.y + f.h + gap
            }
        }
        guard hits(frame) else { return frame }
        var xs = [frame.x], ys = [frame.y]
        for o in obstacles {
            xs.append(o.x + o.w + gap); xs.append(o.x - frame.w - gap)
            ys.append(o.y + o.h + gap); ys.append(o.y - frame.h - gap)
        }
        var best: Rect?
        var bestD = Double.infinity
        for x in xs {
            let dx = x - frame.x
            if dx * dx >= bestD { continue }
            for y in ys {
                let dy = y - frame.y
                let d = dx * dx + dy * dy
                if d >= bestD { continue }
                let f = Rect(x: x, y: y, w: frame.w, h: frame.h)
                if !hits(f) { best = f; bestD = d }
            }
        }
        return best ?? frame
    }
}

/// 키 입력 해석.
public enum KeyInput {
    /// Ctrl+글자에서 터미널로 보낼 제어 문자. 영문 자판처럼 SwiftTerm 이 스스로 처리할 수 있으면 nil.
    /// 한글 입력 소스에서는 charactersIgnoringModifiers 가 "ㅊ" 같은 자모로 와서 SwiftTerm 이 아무것도 보내지 않는다.
    /// 그때는 characters 에 든 제어 문자(Ctrl+C 면 3)를 쓴다.
    public static func controlByte(control: Bool, command: Bool, option: Bool, characters: String?, ignoringModifiers: String?) -> UInt8? {
        guard control, !command, !option else { return nil }
        if let raw = ignoringModifiers?.unicodeScalars.first, raw.isASCII { return nil }
        guard let scalars = characters?.unicodeScalars, scalars.count == 1,
              let v = scalars.first?.value, v < 0x20 else { return nil }
        return UInt8(v)
    }
}
