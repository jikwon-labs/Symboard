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

    /// 자리를 정해 주지 않고 만든 노드(New console·Spawn·에이전트가 띄운 콘솔)를 놓을 자리.
    /// 기준 노드(reference, 없으면 마지막 장애물)와 같은 줄 오른쪽의 첫 빈 칸, 줄이 maxRowWidth 를 넘으면 아래 줄 왼쪽부터.
    /// 보드가 비어 있으면 nil(부르는 쪽이 화면 가운데에 놓는다).
    public static func besideSlot(w: Double, h: Double, reference: Rect?, obstacles: [Rect],
                                  gap: Double = 40, maxRowWidth: Double = 2100) -> Rect? {
        guard let ref = reference ?? obstacles.last else { return nil }
        let clearance = 24.0
        func blockers(_ f: Rect) -> [Rect] {
            obstacles.filter { o in
                f.x < o.x + o.w + clearance && o.x < f.x + f.w + clearance && f.y < o.y + o.h + clearance && o.y < f.y + f.h + clearance
            }
        }
        func band(_ y: Double, _ hh: Double) -> [Rect] { obstacles.filter { $0.y < y + hh && y < $0.y + $0.h } }
        let firstRow = band(ref.y, ref.h)
        let rowLeft = min(firstRow.map(\.x).min() ?? ref.x, ref.x)
        var y = ref.y
        var x = ref.x + ref.w + gap
        for _ in 0..<12 {
            var tries = 0
            while x + w - rowLeft <= maxRowWidth || x == rowLeft, tries < 30 {
                let f = Rect(x: x, y: y, w: w, h: h)
                let b = blockers(f)
                if b.isEmpty { return f }
                x = (b.map { $0.x + $0.w }.max() ?? x) + gap
                tries += 1
            }
            // 이 줄은 찼다. 이 줄에 걸친 것들의 아래로 내려가 왼쪽부터 다시.
            let row = band(y, max(h, y == ref.y ? ref.h : h))
            y = (row.map { $0.y + $0.h }.max() ?? (y + h)) + gap
            x = rowLeft
        }
        return nearestFree(Rect(x: rowLeft, y: y, w: w, h: h), avoiding: obstacles)
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
    /// 콘솔 안 macOS 터미널 관례 키(단어·줄 이동과 지우기)를 터미널에 보낼 바이트로.
    /// Option+←/→ 단어 이동(ESC b / ESC f), Cmd+←/→ 줄 처음·끝(Ctrl+A / Ctrl+E),
    /// Option+Backspace 앞 단어 지우기(ESC DEL), Cmd+Backspace 줄 처음까지 지우기(Ctrl+U). 해당 없으면 nil.
    /// 키 코드로 보므로 입력 소스(한글·영문)와 상관없다.
    public static func editBytes(keyCode: UInt16, command: Bool, option: Bool, control: Bool, shift: Bool) -> [UInt8]? {
        guard !control, !shift, command != option else { return nil }
        switch (keyCode, command) {
        case (123, false): return [0x1b, 0x62]   // ESC b
        case (124, false): return [0x1b, 0x66]   // ESC f
        case (51, false): return [0x1b, 0x7f]    // ESC DEL
        case (123, true): return [0x01]          // Ctrl+A
        case (124, true): return [0x05]          // Ctrl+E
        case (51, true): return [0x15]           // Ctrl+U
        default: return nil
        }
    }

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

/// 키보드로 콘솔 사이를 옮겨 다닐 때의 순서(Ctrl+Tab·Cmd+1~9).
public enum ConsoleOrder {
    /// 화면 위치 순: 위 → 아래 줄, 줄 안에서 왼 → 오른쪽. 윗변 차이가 rowTolerance 안이면 같은 줄로 본다.
    public static func order(_ items: [(id: UUID, frame: Rect)], rowTolerance: Double = 120) -> [UUID] {
        let byY = items.sorted { $0.frame.y < $1.frame.y }
        var rows: [[(id: UUID, frame: Rect)]] = []
        for it in byY {
            if let top = rows.last?.first, it.frame.y - top.frame.y < rowTolerance { rows[rows.count - 1].append(it) }
            else { rows.append([it]) }
        }
        return rows.flatMap { $0.sorted { $0.frame.x < $1.frame.x }.map(\.id) }
    }

    /// 지금 콘솔에서 다음(또는 이전) 콘솔. 끝에서는 처음으로 돈다. 지금 것이 목록에 없으면 처음(이전이면 끝).
    public static func step(from current: UUID?, in ids: [UUID], forward: Bool) -> UUID? {
        guard !ids.isEmpty else { return nil }
        guard let c = current, let i = ids.firstIndex(of: c) else { return forward ? ids.first : ids.last }
        return ids[(i + (forward ? 1 : ids.count - 1)) % ids.count]
    }

    /// Cmd+1~9 의 키 코드(ANSI 자판 숫자 줄) → 1~9.
    public static func digit(keyCode: UInt16) -> Int? {
        [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][keyCode]
    }
}
