import AppKit

private let scriptURL = URL(fileURLWithPath: #filePath)
private let repositoryRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let green = NSColor(
    calibratedRed: 15.0 / 255.0,
    green: 61.0 / 255.0,
    blue: 44.0 / 255.0,
    alpha: 1
)
private let leafGreen = NSColor(
    calibratedRed: 39.0 / 255.0,
    green: 163.0 / 255.0,
    blue: 106.0 / 255.0,
    alpha: 1
)
private let amber = NSColor(
    calibratedRed: 239.0 / 255.0,
    green: 166.0 / 255.0,
    blue: 60.0 / 255.0,
    alpha: 1
)

private func drawIcon(size: Int, destination: URL) throws {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let side = CGFloat(size)

    context.setFillColor(green.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))

    let leafX = side * 0.20
    let leafY = side * 0.21
    let leafSide = side * 0.38
    let radius = side * 0.30
    let leafPath = CGMutablePath()
    leafPath.move(to: CGPoint(x: leafX, y: leafY + leafSide))
    leafPath.addLine(to: CGPoint(x: leafX + leafSide - radius, y: leafY + leafSide))
    leafPath.addArc(
        center: CGPoint(x: leafX + leafSide - radius, y: leafY + leafSide - radius),
        radius: radius,
        startAngle: .pi / 2,
        endAngle: 0,
        clockwise: true
    )
    leafPath.addLine(to: CGPoint(x: leafX + leafSide, y: leafY))
    leafPath.addLine(to: CGPoint(x: leafX + radius, y: leafY))
    leafPath.addArc(
        center: CGPoint(x: leafX + radius, y: leafY + radius),
        radius: radius,
        startAngle: -.pi / 2,
        endAngle: -.pi,
        clockwise: true
    )
    leafPath.closeSubpath()
    context.addPath(leafPath)
    context.setFillColor(leafGreen.cgColor)
    context.fillPath()

    let dotSide = side * 0.31
    context.setFillColor(amber.cgColor)
    context.fillEllipse(
        in: CGRect(
            x: side * (1 - 0.19) - dotSide,
            y: side * (1 - 0.20) - dotSide,
            width: dotSide,
            height: dotSide
        )
    )

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: destination, options: .atomic)
}

private let iosIconDirectory = repositoryRoot
    .appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
private let iosIcons: [String: Int] = [
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
]

for (filename, size) in iosIcons {
    try drawIcon(size: size, destination: iosIconDirectory.appendingPathComponent(filename))
}

private let androidIcons: [(String, Int)] = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]
for (density, size) in androidIcons {
    let destination = repositoryRoot
        .appendingPathComponent("android/app/src/main/res")
        .appendingPathComponent(density)
        .appendingPathComponent("ic_launcher.png")
    try drawIcon(size: size, destination: destination)
}
