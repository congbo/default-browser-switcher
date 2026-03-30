import AppKit
import Foundation

struct IconRenderer {
    let canvasSize: CGFloat = 1024

    func drawIcon(in rect: NSRect, transparentBackground: Bool) {
        let scale = rect.width / canvasSize
        let iconRect = rect

        if !transparentBackground {
            drawBackdrop(in: iconRect, scale: scale)
        }

        let symbolRect = iconRect.insetBy(dx: 210 * scale, dy: 210 * scale)
        drawGlobe(in: symbolRect, scale: scale)
        drawArrow(in: symbolRect, scale: scale)

        if !transparentBackground {
            drawGloss(in: iconRect, scale: scale)
        }
    }

    private func drawBackdrop(in rect: NSRect, scale: CGFloat) {
        let radius = 236 * scale
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let gradient = NSGradient(
            colorsAndLocations:
                (NSColor(calibratedRed: 0.11, green: 0.39, blue: 0.82, alpha: 1), 0.00),
                (NSColor(calibratedRed: 0.07, green: 0.72, blue: 0.71, alpha: 1), 0.60),
                (NSColor(calibratedRed: 0.05, green: 0.58, blue: 0.55, alpha: 1), 1.00)
        )!
        gradient.draw(in: path, angle: -55)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        let auraRect = rect.insetBy(dx: 60 * scale, dy: 60 * scale).offsetBy(dx: 50 * scale, dy: 74 * scale)
        let auraGradient = NSGradient(
            starting: NSColor(calibratedWhite: 1.0, alpha: 0.22),
            ending: .clear
        )!
        auraGradient.draw(
            in: NSBezierPath(ovalIn: auraRect),
            relativeCenterPosition: NSPoint(x: -0.2, y: 0.5)
        )

        let shadowRect = rect.insetBy(dx: 80 * scale, dy: 80 * scale).offsetBy(dx: 0, dy: -100 * scale)
        let shadowGradient = NSGradient(
            starting: NSColor(calibratedRed: 0.03, green: 0.20, blue: 0.28, alpha: 0.30),
            ending: .clear
        )!
        shadowGradient.draw(
            in: NSBezierPath(ovalIn: shadowRect),
            relativeCenterPosition: NSPoint(x: 0, y: -0.7)
        )

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGlobe(in rect: NSRect, scale: CGFloat) {
        let strokeWidth = 44 * scale
        let globePath = NSBezierPath(ovalIn: rect)
        globePath.lineWidth = strokeWidth
        NSColor(calibratedWhite: 1.0, alpha: 0.96).setStroke()
        globePath.stroke()

        NSGraphicsContext.saveGraphicsState()
        globePath.addClip()

        let meridianWidth = 30 * scale
        let horizontalWidth = 28 * scale
        let inset = rect.width * 0.18

        let verticalOne = NSBezierPath()
        verticalOne.lineWidth = meridianWidth
        verticalOne.lineCapStyle = .round
        verticalOne.move(to: NSPoint(x: rect.midX - inset, y: rect.minY + 18 * scale))
        verticalOne.curve(
            to: NSPoint(x: rect.midX - inset, y: rect.maxY - 18 * scale),
            controlPoint1: NSPoint(x: rect.midX - inset - 54 * scale, y: rect.midY - 132 * scale),
            controlPoint2: NSPoint(x: rect.midX - inset - 54 * scale, y: rect.midY + 132 * scale)
        )
        verticalOne.stroke()

        let verticalTwo = NSBezierPath()
        verticalTwo.lineWidth = meridianWidth
        verticalTwo.lineCapStyle = .round
        verticalTwo.move(to: NSPoint(x: rect.midX + inset, y: rect.minY + 18 * scale))
        verticalTwo.curve(
            to: NSPoint(x: rect.midX + inset, y: rect.maxY - 18 * scale),
            controlPoint1: NSPoint(x: rect.midX + inset + 54 * scale, y: rect.midY - 132 * scale),
            controlPoint2: NSPoint(x: rect.midX + inset + 54 * scale, y: rect.midY + 132 * scale)
        )
        verticalTwo.stroke()

        let horizontalTop = NSBezierPath()
        horizontalTop.lineWidth = horizontalWidth
        horizontalTop.lineCapStyle = .round
        horizontalTop.move(to: NSPoint(x: rect.minX + 48 * scale, y: rect.midY + 110 * scale))
        horizontalTop.curve(
            to: NSPoint(x: rect.maxX - 48 * scale, y: rect.midY + 110 * scale),
            controlPoint1: NSPoint(x: rect.midX - 138 * scale, y: rect.midY + 190 * scale),
            controlPoint2: NSPoint(x: rect.midX + 138 * scale, y: rect.midY + 190 * scale)
        )
        horizontalTop.stroke()

        let horizontalBottom = NSBezierPath()
        horizontalBottom.lineWidth = horizontalWidth
        horizontalBottom.lineCapStyle = .round
        horizontalBottom.move(to: NSPoint(x: rect.minX + 48 * scale, y: rect.midY - 110 * scale))
        horizontalBottom.curve(
            to: NSPoint(x: rect.maxX - 48 * scale, y: rect.midY - 110 * scale),
            controlPoint1: NSPoint(x: rect.midX - 138 * scale, y: rect.midY - 190 * scale),
            controlPoint2: NSPoint(x: rect.midX + 138 * scale, y: rect.midY - 190 * scale)
        )
        horizontalBottom.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawArrow(in rect: NSRect, scale: CGFloat) {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = 74 * scale

        path.move(to: NSPoint(x: rect.minX - 6 * scale, y: rect.midY + 76 * scale))
        path.curve(
            to: NSPoint(x: rect.midX + 116 * scale, y: rect.maxY + 32 * scale),
            controlPoint1: NSPoint(x: rect.minX + 150 * scale, y: rect.maxY + 100 * scale),
            controlPoint2: NSPoint(x: rect.midX + 22 * scale, y: rect.maxY + 90 * scale)
        )

        let arrowHead = NSBezierPath()
        arrowHead.lineCapStyle = .round
        arrowHead.lineJoinStyle = .round
        arrowHead.lineWidth = 74 * scale
        arrowHead.move(to: NSPoint(x: rect.midX + 34 * scale, y: rect.maxY - 6 * scale))
        arrowHead.line(to: NSPoint(x: rect.midX + 118 * scale, y: rect.maxY + 34 * scale))
        arrowHead.line(to: NSPoint(x: rect.maxX + 16 * scale, y: rect.maxY - 42 * scale))

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedRed: 0.03, green: 0.20, blue: 0.28, alpha: 0.26)
        shadow.shadowBlurRadius = 22 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(calibratedRed: 0.96, green: 1.0, blue: 1.0, alpha: 0.98).setStroke()
        path.stroke()
        arrowHead.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGloss(in rect: NSRect, scale: CGFloat) {
        let glossPath = NSBezierPath(roundedRect: rect, xRadius: 236 * scale, yRadius: 236 * scale)
        glossPath.lineWidth = 6 * scale

        NSGraphicsContext.saveGraphicsState()
        glossPath.addClip()

        let glossRect = NSRect(
            x: rect.minX + 90 * scale,
            y: rect.midY + 40 * scale,
            width: rect.width - 180 * scale,
            height: rect.height * 0.40
        )

        let glossGradient = NSGradient(
            starting: NSColor(calibratedWhite: 1.0, alpha: 0.20),
            ending: .clear
        )!
        glossGradient.draw(
            in: NSBezierPath(roundedRect: glossRect, xRadius: 160 * scale, yRadius: 160 * scale),
            angle: 90
        )

        NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
        glossPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct IconAsset {
    let filename: String
    let size: CGFloat
}

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let appIconSetURL = rootURL
    .appendingPathComponent("App/Resources/Assets.xcassets", isDirectory: true)
    .appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let docsImageURL = rootURL
    .appendingPathComponent("docs/images", isDirectory: true)
    .appendingPathComponent("app-icon-preview.png")
let docsMasterURL = rootURL
    .appendingPathComponent("docs/images", isDirectory: true)
    .appendingPathComponent("app-icon-master.png")

try fileManager.createDirectory(at: appIconSetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: docsImageURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let renderer = IconRenderer()

let iconAssets: [IconAsset] = [
    .init(filename: "icon_16x16.png", size: 16),
    .init(filename: "icon_16x16@2x.png", size: 32),
    .init(filename: "icon_32x32.png", size: 32),
    .init(filename: "icon_32x32@2x.png", size: 64),
    .init(filename: "icon_128x128.png", size: 128),
    .init(filename: "icon_128x128@2x.png", size: 256),
    .init(filename: "icon_256x256.png", size: 256),
    .init(filename: "icon_256x256@2x.png", size: 512),
    .init(filename: "icon_512x512.png", size: 512),
    .init(filename: "icon_512x512@2x.png", size: 1024)
]

func renderPNG(to url: URL, size: CGFloat, transparentBackground: Bool) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "GenerateAppIcon", code: 1)
    }

    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "GenerateAppIcon", code: 2)
    }

    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

    renderer.drawIcon(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        transparentBackground: transparentBackground
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "GenerateAppIcon", code: 3)
    }

    try png.write(to: url)
}

for asset in iconAssets {
    try renderPNG(
        to: appIconSetURL.appendingPathComponent(asset.filename),
        size: asset.size,
        transparentBackground: false
    )
}

try renderPNG(to: docsMasterURL, size: 1024, transparentBackground: false)
try renderPNG(to: docsImageURL, size: 1024, transparentBackground: true)

print("Generated app icon assets at \(appIconSetURL.path)")
