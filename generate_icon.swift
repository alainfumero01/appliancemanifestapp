#!/usr/bin/swift
// LoadScan icon generator
// Run: swift generate_icon.swift
// Writes all required PNG sizes into the Xcode asset catalog.
import AppKit
import CoreGraphics
import Foundation

let outputDir = "./ApplianceManifest/Assets.xcassets/AppIcon.appiconset"

// (filename, pixel size)
let sizes: [(String, Int)] = [
    ("Icon-20@2x",    40),
    ("Icon-20@3x",    60),
    ("Icon-29@2x",    58),
    ("Icon-29@3x",    87),
    ("Icon-40@2x",    80),
    ("Icon-40@3x",   120),
    ("Icon-60@2x",   120),
    ("Icon-60@3x",   180),
    ("Icon-76",       76),
    ("Icon-76@2x",   152),
    ("Icon-83.5@2x", 167),
    ("Icon-1024",   1024),
]

func renderIcon(pixels: Int) -> Data? {
    let s = pixels
    let sf = CGFloat(s)

    // Use a bitmap rep at exact pixel dimensions — avoids retina 2x scaling
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: s, pixelsHigh: s,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    bitmap.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    // ── Background gradient ─────────────────────────────────────────
    // Soft graphite: #5C6470 (top) → #191D24 (bottom)
    let cs = CGColorSpaceCreateDeviceRGB()
    let top    = CGColor(red: 0.361, green: 0.392, blue: 0.439, alpha: 1) // #5C6470
    let bottom = CGColor(red: 0.098, green: 0.114, blue: 0.141, alpha: 1) // #191D24
    let gradient = CGGradient(colorsSpace: cs,
                               colors: [top, bottom] as CFArray,
                               locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: sf / 2, y: sf),
                           end:   CGPoint(x: sf / 2, y: 0),
                           options: [])

    // ── Corner brackets ─────────────────────────────────────────────
    let pad:   CGFloat = sf * 0.180
    let arm:   CGFloat = sf * 0.145
    let thick: CGFloat = sf * 0.040

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(thick)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.beginPath()
    // Top-left (visual top = high Y in CG)
    ctx.move(to:    CGPoint(x: pad + arm, y: sf - pad))
    ctx.addLine(to: CGPoint(x: pad,       y: sf - pad))
    ctx.addLine(to: CGPoint(x: pad,       y: sf - pad - arm))
    // Top-right
    ctx.move(to:    CGPoint(x: sf - pad - arm, y: sf - pad))
    ctx.addLine(to: CGPoint(x: sf - pad,       y: sf - pad))
    ctx.addLine(to: CGPoint(x: sf - pad,       y: sf - pad - arm))
    // Bottom-left (visual bottom = low Y in CG)
    ctx.move(to:    CGPoint(x: pad + arm, y: pad))
    ctx.addLine(to: CGPoint(x: pad,       y: pad))
    ctx.addLine(to: CGPoint(x: pad,       y: pad + arm))
    // Bottom-right
    ctx.move(to:    CGPoint(x: sf - pad - arm, y: pad))
    ctx.addLine(to: CGPoint(x: sf - pad,       y: pad))
    ctx.addLine(to: CGPoint(x: sf - pad,       y: pad + arm))
    ctx.strokePath()

    // ── Barcode bars ─────────────────────────────────────────────────
    let bw: CGFloat = sf * 0.570
    let bh: CGFloat = sf * 0.400
    let bx: CGFloat = (sf - bw) / 2
    let by: CGFloat = (sf - bh) / 2

    let bars: [(CGFloat, CGFloat)] = [
        (0.155, 1.00), (0.060, 0.78), (0.115, 1.00),
        (0.060, 0.78), (0.155, 1.00), (0.060, 0.78),
        (0.115, 1.00), (0.060, 0.78), (0.155, 1.00),
    ]
    let totalW = bars.reduce(0.0) { $0 + $1.0 }
    let gap    = (1.0 - totalW) / CGFloat(bars.count - 1)

    var cx = bx
    for (wf, hf) in bars {
        let barW = bw * wf
        let barH = bh * hf
        let barY = by + (bh - barH) / 2
        let radius = barW * 0.25
        let rect   = CGRect(x: cx, y: barY, width: barW, height: barH)
        let alpha: CGFloat = wf < 0.1 ? 0.82 : 0.95
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        cx += barW + bw * gap
    }

    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])
}

// ── Run ─────────────────────────────────────────────────────────────
var generated = 0
for (name, size) in sizes {
    let path = "\(outputDir)/\(name).png"
    if let pngData = renderIcon(pixels: size) {
        do {
            try pngData.write(to: URL(fileURLWithPath: path))
            print("✓  \(name).png  (\(size)×\(size))")
            generated += 1
        } catch {
            print("✗  \(name).png — write error: \(error.localizedDescription)")
        }
    } else {
        print("✗  \(name).png — render failed")
    }
}
print("\nDone. \(generated)/\(sizes.count) icons generated.")
