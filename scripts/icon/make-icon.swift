// 앱 아이콘을 그린다. 사용: swift scripts/icon/make-icon.swift <출력.iconset 폴더>
// 어두운 판 위에 노드 둘을 잇는 선 하나가 S 를 그린다. 시작 노드만 강조색이다.
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let ivory: UInt32 = 0xEFEBE4
let accent: UInt32 = 0xE8704A

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    let g = ctx.cgContext
    // 1024 격자, 위가 y=0 이 되도록 뒤집는다(시안 SVG 좌표를 그대로 쓴다).
    g.scaleBy(x: s / 1024, y: s / 1024)
    g.translateBy(x: 0, y: 1024)
    g.scaleBy(x: 1, y: -1)
    // macOS 아이콘 판: 가장자리 100 여백, 둥근 사각형.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.4))
    g.addPath(path); g.setFillColor(color(0x141416)); g.fillPath()
    g.restoreGState()
    g.saveGState()
    g.addPath(path); g.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x2B2B2E), color(0x141416)] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(grad, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    g.restoreGState()
    g.addPath(path); g.setStrokeColor(color(0xFFFFFF, 0.08)); g.setLineWidth(3); g.strokePath()

    // S 자 배선: 꺾이는 곳마다 반지름 100 으로 둥글린다.
    let r: CGFloat = 100
    g.move(to: CGPoint(x: 700, y: 300))
    g.addArc(tangent1End: CGPoint(x: 334, y: 300), tangent2End: CGPoint(x: 334, y: 512), radius: r)
    g.addArc(tangent1End: CGPoint(x: 334, y: 512), tangent2End: CGPoint(x: 690, y: 512), radius: r)
    g.addArc(tangent1End: CGPoint(x: 690, y: 512), tangent2End: CGPoint(x: 690, y: 724), radius: r)
    g.addArc(tangent1End: CGPoint(x: 690, y: 724), tangent2End: CGPoint(x: 324, y: 724), radius: r)
    g.addLine(to: CGPoint(x: 324, y: 724))
    g.setStrokeColor(color(ivory)); g.setLineWidth(40); g.setLineCap(.round); g.setLineJoin(.round)
    g.strokePath()

    // 양 끝 노드.
    g.setFillColor(color(accent)); g.fillEllipse(in: CGRect(x: 716 - 50, y: 300 - 50, width: 100, height: 100))
    g.setFillColor(color(ivory)); g.fillEllipse(in: CGRect(x: 308 - 50, y: 724 - 50, width: 100, height: 100))
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
