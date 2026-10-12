#!/usr/bin/env swift
// Renders the app icon from code so the artwork has no binary source.
//
//   swift Scripts/make-icon.swift Resources/AppIcon.icns docs/icon.png
//
// Design: a dark rounded tile with a fanned stack of three profile cards; the front card
// carries an avatar disc and two text lines. Reads as "several accounts" at every size.

import AppKit

func render(pixels: Int, draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawIcon(_ s: CGFloat) {
    // macOS icons leave a margin around the tile so the shadow has room.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 1),
        NSColor(red: 0.09, green: 0.10, blue: 0.15, alpha: 1),
    ])!.draw(in: tilePath, angle: -90)

    // Subtle top highlight so the tile doesn't look flat.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Three cards fanned from the back-left to the front-right.
    let cardWidth = tile.width * 0.52
    let cardHeight = tile.height * 0.60
    let step = tile.width * 0.075
    let frontOrigin = NSPoint(x: tile.midX - cardWidth / 2 + step, y: tile.midY - cardHeight / 2 - step * 0.6)
    let radius = cardWidth * 0.14

    for index in [2, 1, 0] {
        let offset = CGFloat(index)
        let rect = NSRect(
            x: frontOrigin.x - step * offset, y: frontOrigin.y + step * 0.75 * offset,
            width: cardWidth, height: cardHeight)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let cardShadow = NSShadow()
        cardShadow.shadowColor = NSColor.black.withAlphaComponent(index == 0 ? 0.35 : 0.2)
        cardShadow.shadowBlurRadius = s * 0.015
        cardShadow.shadowOffset = NSSize(width: 0, height: -s * 0.006)
        cardShadow.set()
        (index == 0 ? NSColor.white : NSColor.white.withAlphaComponent(index == 1 ? 0.55 : 0.3)).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        guard index == 0 else { continue }

        // Avatar disc in the front card's top-left, then two lines of "text".
        let pad = cardWidth * 0.13
        let avatar = cardWidth * 0.30
        let avatarRect = NSRect(x: rect.minX + pad, y: rect.maxY - pad - avatar, width: avatar, height: avatar)
        NSGradient(colors: [
            NSColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1),
            NSColor(red: 0.20, green: 0.80, blue: 0.75, alpha: 1),
        ])!.draw(in: NSBezierPath(ovalIn: avatarRect), angle: -45)

        NSColor(white: 0.78, alpha: 1).setFill()
        let lineHeight = cardHeight * 0.07
        let lineRadius = lineHeight / 2
        let firstLine = NSRect(
            x: rect.minX + pad, y: avatarRect.minY - pad * 0.9 - lineHeight,
            width: cardWidth - pad * 2, height: lineHeight)
        NSBezierPath(roundedRect: firstLine, xRadius: lineRadius, yRadius: lineRadius).fill()
        let secondLine = NSRect(
            x: firstLine.minX, y: firstLine.minY - lineHeight * 1.9,
            width: firstLine.width * 0.62, height: lineHeight)
        NSBezierPath(roundedRect: secondLine, xRadius: lineRadius, yRadius: lineRadius).fill()
    }
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

let args = CommandLine.arguments.dropFirst()
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.icns> <preview.png>\n".utf8))
    exit(1)
}
let icnsURL = URL(fileURLWithPath: args.first!)
let previewURL = URL(fileURLWithPath: args.last!)

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(render(pixels: base, draw: drawIcon)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(render(pixels: base * 2, draw: drawIcon)).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { exit(Int32(iconutil.terminationStatus)) }

try png(render(pixels: 512, draw: drawIcon)).write(to: previewURL)
print("wrote \(icnsURL.path) and \(previewURL.path)")
