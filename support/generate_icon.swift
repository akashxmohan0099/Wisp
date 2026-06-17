import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = root
    .appending(path: "support", directoryHint: .isDirectory)
    .appending(path: "WispIcon.iconset", directoryHint: .isDirectory)

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let dark = NSColor(calibratedRed: 0.035, green: 0.038, blue: 0.042, alpha: 1)
let ring = NSColor(calibratedWhite: 1, alpha: 0.14)
let green = NSColor(calibratedRed: 0.18, green: 0.86, blue: 0.42, alpha: 1)

func drawIcon(points: CGFloat, scale: CGFloat, fileName: String) throws {
    let pixels = Int(points * scale)
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)

    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(origin: .zero, size: size)
    let corner = size.width * 0.22
    let tile = NSBezierPath(roundedRect: rect.insetBy(dx: size.width * 0.04, dy: size.height * 0.04), xRadius: corner, yRadius: corner)
    dark.setFill()
    tile.fill()

    ring.setStroke()
    tile.lineWidth = max(1, size.width * 0.012)
    tile.stroke()

    green.setFill()
    green.setStroke()

    let micWidth = size.width * 0.20
    let micHeight = size.height * 0.34
    let micRect = NSRect(
        x: (size.width - micWidth) / 2,
        y: size.height * 0.43,
        width: micWidth,
        height: micHeight
    )
    NSBezierPath(roundedRect: micRect, xRadius: micWidth / 2, yRadius: micWidth / 2).fill()

    let strokeWidth = max(2, size.width * 0.055)
    let bowl = NSBezierPath()
    bowl.lineWidth = strokeWidth
    bowl.lineCapStyle = .round
    bowl.move(to: NSPoint(x: size.width * 0.34, y: size.height * 0.48))
    bowl.curve(
        to: NSPoint(x: size.width * 0.66, y: size.height * 0.48),
        controlPoint1: NSPoint(x: size.width * 0.34, y: size.height * 0.25),
        controlPoint2: NSPoint(x: size.width * 0.66, y: size.height * 0.25)
    )
    bowl.stroke()

    let stem = NSBezierPath()
    stem.lineWidth = strokeWidth
    stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: size.width * 0.50, y: size.height * 0.26))
    stem.line(to: NSPoint(x: size.width * 0.50, y: size.height * 0.20))
    stem.move(to: NSPoint(x: size.width * 0.39, y: size.height * 0.20))
    stem.line(to: NSPoint(x: size.width * 0.61, y: size.height * 0.20))
    stem.stroke()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "WispIcon", code: 1)
    }

    try png.write(to: iconsetURL.appending(path: fileName))
}

let specs: [(CGFloat, CGFloat, String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

for spec in specs {
    try drawIcon(points: spec.0, scale: spec.1, fileName: spec.2)
}
