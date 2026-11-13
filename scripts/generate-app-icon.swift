#!/usr/bin/env swift
// Generates the app icon set and the site's icon files from the SVG sources in Branding/.
//
// Usage: swift scripts/generate-app-icon.swift BRANDING_DIR APPICONSET_DIR SITE_PUBLIC_DIR
//
// Run through `make app-icon`. Sizes of 64 px and under use app-icon-small.svg (eyes only);
// larger ones use app-icon.svg. AppKit rasterizes the SVGs, so no extra tools are needed.

import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("generate-app-icon: \(message)\n".utf8))
    exit(1)
}

struct Slot {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png"
    }
}

/// Pixel sizes at or under this use the simplified icon.
let smallIconLimit = 64

func loadImage(_ url: URL) -> NSImage {
    guard let image = NSImage(contentsOf: url), image.isValid else {
        fail("cannot read \(url.path)")
    }
    return image
}

func png(of image: NSImage, pixels: Int) -> Data {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else {
        fail("cannot create a \(pixels) px bitmap")
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fail("cannot encode a \(pixels) px PNG")
    }
    return data
}

func write(_ data: Data, to url: URL) {
    do {
        try data.write(to: url, options: .atomic)
    } catch {
        fail("cannot write \(url.path): \(error.localizedDescription)")
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fail("usage: generate-app-icon.swift BRANDING_DIR APPICONSET_DIR SITE_PUBLIC_DIR")
}
let branding = URL(fileURLWithPath: arguments[1], isDirectory: true)
let iconSet = URL(fileURLWithPath: arguments[2], isDirectory: true)
let sitePublic = URL(fileURLWithPath: arguments[3], isDirectory: true)

let fullURL = branding.appendingPathComponent("app-icon.svg")
let smallURL = branding.appendingPathComponent("app-icon-small.svg")
let full = loadImage(fullURL)
let small = loadImage(smallURL)

let slots = [16, 32, 128, 256, 512].flatMap { [Slot(points: $0, scale: 1), Slot(points: $0, scale: 2)] }
for slot in slots {
    let image = slot.pixels <= smallIconLimit ? small : full
    write(png(of: image, pixels: slot.pixels), to: iconSet.appendingPathComponent(slot.filename))
}

let images = slots.map { slot in
    """
        { "filename" : "\(slot.filename)", "idiom" : "mac", "scale" : "\(slot.scale)x", \
    "size" : "\(slot.points)x\(slot.points)" }
    """
}
let contents = """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
write(Data(contents.utf8), to: iconSet.appendingPathComponent("Contents.json"))

// The site serves copies: the SVGs as they are, plus a PNG favicon for browsers without SVG
// favicon support.
do {
    write(try Data(contentsOf: smallURL), to: sitePublic.appendingPathComponent("favicon.svg"))
    write(try Data(contentsOf: fullURL), to: sitePublic.appendingPathComponent("app-icon.svg"))
} catch {
    fail("cannot copy the SVG sources: \(error.localizedDescription)")
}
write(png(of: small, pixels: 32), to: sitePublic.appendingPathComponent("favicon.png"))
