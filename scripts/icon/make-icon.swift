// 앱 아이콘을 그린다. 사용: swift scripts/icon/make-icon.swift <출력.iconset 폴더>
// 점 격자 보드 위에 화살표로 이어진 카드 세 장. 하나는 강조색이고 작은 반짝임이 있다.
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    let g = ctx.cgContext
    g.scaleBy(x: s / 1024, y: s / 1024)
    // 1024 격자 기준. macOS 아이콘 판: 가장자리 100 여백, 둥근 사각형.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.45))
    g.addPath(path); g.setFillColor(color(0x15120F)); g.fillPath()
    g.restoreGState()
    g.saveGState()
    g.addPath(path); g.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x2A2420), color(0x110F0D)] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // 점 격자.
    g.setFillColor(color(0xFFFFFF, 0.09))
    var y: CGFloat = 140
    while y < 924 { var x: CGFloat = 140; while x < 924 { g.fillEllipse(in: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)); x += 62 }; y += 62 }
    // 카드 사이 화살표 선.
    func card(_ r: CGRect, fill: CGColor, stroke: CGColor, header: CGColor) {
        let p = CGPath(roundedRect: r, cornerWidth: 34, cornerHeight: 34, transform: nil)
        g.saveGState()
        g.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.5))
        g.addPath(p); g.setFillColor(fill); g.fillPath()
        g.restoreGState()
        g.addPath(p); g.setStrokeColor(stroke); g.setLineWidth(8); g.strokePath()
        // 머리 줄과 본문 줄.
        g.setFillColor(header)
        g.fillEllipse(in: CGRect(x: r.minX + 30, y: r.maxY - 56, width: 24, height: 24))
        g.fill(CGRect(x: r.minX + 66, y: r.maxY - 52, width: r.width * 0.42, height: 16).insetBy(dx: 0, dy: 0))
        g.setFillColor(color(0xFFFFFF, 0.16))
        for i in 0..<3 { g.fill(CGRect(x: r.minX + 30, y: r.maxY - 104 - CGFloat(i) * 34, width: r.width * (0.72 - CGFloat(i) * 0.14), height: 14)) }
    }
    let a = CGRect(x: 180, y: 560, width: 330, height: 250)
    let b = CGRect(x: 560, y: 470, width: 290, height: 220)
    let c = CGRect(x: 250, y: 210, width: 330, height: 240)
    g.setStrokeColor(color(0xECE7E2, 0.55)); g.setLineWidth(10); g.setLineCap(.round)
    g.move(to: CGPoint(x: a.maxX - 20, y: a.midY)); g.addCurve(to: CGPoint(x: b.minX, y: b.midY + 30), control1: CGPoint(x: 560, y: 700), control2: CGPoint(x: 520, y: 620)); g.strokePath()
    g.move(to: CGPoint(x: b.midX, y: b.minY)); g.addCurve(to: CGPoint(x: c.maxX, y: c.midY + 20), control1: CGPoint(x: 700, y: 380), control2: CGPoint(x: 660, y: 340)); g.strokePath()
    card(a, fill: color(0x221E1B), stroke: color(0xECE7E2, 0.5), header: color(0x6FCF97))
    card(c, fill: color(0x221E1B), stroke: color(0xECE7E2, 0.5), header: color(0x56A8F5))
    card(b, fill: color(0x3A1F15), stroke: color(0xE8704A), header: color(0xE8704A))
    // 반짝임(네 갈래 별).
    let cx: CGFloat = 820, cy: CGFloat = 800, R: CGFloat = 70, r: CGFloat = 16
    g.setFillColor(color(0xE8704A))
    g.move(to: CGPoint(x: cx, y: cy + R))
    for k in 1...8 {
        let ang = CGFloat.pi / 2 + CGFloat(k) * .pi / 4
        let rad = k % 2 == 0 ? R : r
        g.addLine(to: CGPoint(x: cx + cos(ang) * rad, y: cy + sin(ang) * rad))
    }
    g.closePath(); g.fillPath()
    g.restoreGState()
    // 판 가장자리 얇은 빛.
    g.addPath(path); g.setStrokeColor(color(0xFFFFFF, 0.08)); g.setLineWidth(3); g.strokePath()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(size: base * scale).write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
print("wrote \(out)")
