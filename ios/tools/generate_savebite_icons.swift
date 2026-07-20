import CoreGraphics
import Foundation
import ImageIO

// From the repository root:
// swiftc ios/tools/generate_savebite_icons.swift -o /tmp/savebite-icons &&
// /tmp/savebite-icons

private let scriptURL = URL(fileURLWithPath: #filePath)
private let repositoryRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let markURL = repositoryRoot
    .appendingPathComponent("assets/images/savebite_mark.png")

private func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

guard let mark = loadImage(markURL) else {
    fatalError("The master app-mark asset is missing from assets/images.")
}

/// Renders an opaque RGB PNG. App Store icons may not contain an alpha channel.
private func render(
    image: CGImage,
    width: Int,
    height: Int,
    destination: URL,
    inset: CGFloat = 0
) throws {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(canvas)
    context.interpolationQuality = .high
    context.draw(
        image,
        in: canvas.insetBy(dx: inset, dy: inset)
    )

    guard let rendered = context.makeImage(),
          let output = CGImageDestinationCreateWithURL(
              destination as CFURL,
              "public.png" as CFString,
              1,
              nil
          ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(output, rendered, nil)
    guard CGImageDestinationFinalize(output) else {
        throw CocoaError(.fileWriteUnknown)
    }
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
    try render(
        image: mark,
        width: size,
        height: size,
        destination: iosIconDirectory.appendingPathComponent(filename)
    )
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
    try render(image: mark, width: size, height: size, destination: destination)
}

// Android adaptive icons need additional safe-zone padding because launchers
// may mask the foreground into circles, squircles, or other shapes.
try render(
    image: mark,
    width: 432,
    height: 432,
    destination: repositoryRoot.appendingPathComponent(
        "android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground_image.png"
    ),
    inset: 40
)

// Native launch screens intentionally render only a black background. The
// descriptive brand artwork lives in Flutter's SplashScreen, so users never
// see the same splash content twice during startup.
