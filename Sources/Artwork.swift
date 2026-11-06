// Shared drawing code for the app icon and menu bar icon, in the style of
// the light-streak wallpaper: tall rounded slabs filled with vertical
// blue-white streaks fading to black, with rare warm accent lines.
import AppKit

struct RNG {
    var s: UInt64
    mutating func next() -> CGFloat {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((s >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
}

enum Palette {
    static let black = NSColor(srgbRed: 0.01, green: 0.015, blue: 0.03, alpha: 1)
    static let navy = NSColor(srgbRed: 0.12, green: 0.20, blue: 0.33, alpha: 1)
    static let steel = NSColor(srgbRed: 0.42, green: 0.55, blue: 0.72, alpha: 1)
    static let ice = NSColor(srgbRed: 0.88, green: 0.92, blue: 0.97, alpha: 1)
    static let accents = [
        NSColor(srgbRed: 1.0, green: 0.62, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.95, green: 0.25, blue: 0.20, alpha: 1),
        NSColor(srgbRed: 0.40, green: 0.65, blue: 1.0, alpha: 1),
    ]
}

func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!, t = max(0, min(1, t))
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}

/// Streak brightness 0…1 for a position across a slab: slow bands plus jitter.
func band(_ u: CGFloat, _ phase: CGFloat, _ rng: inout RNG) -> CGFloat {
    let slow = 0.5 + 0.5 * sin(u * 9 + phase) * cos(u * 3.7 + phase * 0.6)
    return max(0, min(1, slow * 0.8 + rng.range(-0.25, 0.35)))
}

/// Colour streaks clipped to `path`. `brightTop`: streaks glow at the top and
/// sink to black at the bottom (else the reverse, like the wallpaper's lower slabs).
func drawColorSlab(_ path: NSBezierPath, seed: UInt64, brightTop: Bool = true, accents: Bool = true) {
    let r = path.bounds
    var rng = RNG(s: seed)
    let phase = rng.range(0, 6)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    Palette.black.setFill(); r.fill()
    var x = r.minX
    while x < r.maxX {
        let w = r.width * rng.range(0.004, 0.022)
        let b = band((x - r.minX) / r.width, phase, &rng)
        let lit = mix(mix(Palette.navy, Palette.steel, b * 1.6), Palette.ice, (b - 0.4) * 1.8)
        let dark = mix(Palette.black, Palette.navy, b * 0.5)
        let stops: [NSColor] = brightTop ? [dark, dark, lit, lit] : [lit, lit, dark, dark]
        let fade = rng.range(0.25, 0.55)
        NSGradient(colors: stops, atLocations: [0, fade * 0.5, fade + 0.25, 1], colorSpace: .sRGB)!
            .draw(in: NSRect(x: x, y: r.minY, width: w + 0.5, height: r.height), angle: 90)
        x += w
    }
    if accents {
        for _ in 0..<3 where rng.next() < 0.8 {
            let ax = r.minX + r.width * rng.range(0.08, 0.92)
            let c = Palette.accents[Int(rng.next() * 2.99)]
            let y0 = brightTop ? r.minY + r.height * rng.range(0.05, 0.2) : r.minY + r.height * 0.4
            NSGradient(colors: [c.withAlphaComponent(0), c, c.withAlphaComponent(0)])!
                .draw(in: NSRect(x: ax, y: y0, width: max(1, r.width * 0.006), height: r.height * 0.45), angle: 90)
        }
    }
    // soft frosted rim + warm glow along the bottom edge
    NSColor(white: 1, alpha: 0.35).setStroke()
    path.lineWidth = max(1, r.width * 0.012)
    path.stroke()
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.75, blue: 0.45, alpha: 0.9), .clear])!
        .draw(in: NSRect(x: r.minX, y: r.minY, width: r.width, height: max(1.5, r.height * 0.02)), angle: 90)
    NSGraphicsContext.restoreGraphicsState()
}

func continuousRect(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

// MARK: App icon variants (drawn into a 1024×1024 canvas scaled by s)

func appIconSlabs(_ s: CGFloat) {
    let tile = continuousRect(NSRect(x: 100*s, y: 100*s, width: 824*s, height: 824*s), 185*s)
    Palette.black.setFill(); tile.fill()
    NSGraphicsContext.saveGraphicsState(); tile.addClip()
    // three slabs echoing the wallpaper: left one stepped, middle split, right full
    let gap = 22*s, top = 864*s, bottom = 160*s, w = (704*s - 2*gap) / 3, x0 = 160*s, r = 34*s
    drawColorSlab(continuousRect(NSRect(x: x0, y: bottom + 250*s, width: w, height: top - bottom - 250*s), r), seed: 3)
    drawColorSlab(continuousRect(NSRect(x: x0 + w + gap, y: bottom + 330*s, width: w, height: top - bottom - 330*s), r), seed: 11)
    drawColorSlab(continuousRect(NSRect(x: x0 + w + gap, y: bottom, width: w, height: 310*s), r), seed: 19, brightTop: false)
    drawColorSlab(continuousRect(NSRect(x: x0 + 2*(w + gap), y: bottom, width: w, height: top - bottom), r), seed: 27)
    NSGraphicsContext.restoreGraphicsState()
}

func appIconScreen(_ s: CGFloat) {
    let tile = continuousRect(NSRect(x: 100*s, y: 100*s, width: 824*s, height: 824*s), 185*s)
    Palette.black.setFill(); tile.fill()
    // one big "display" with all four corners rounded, full of streaks
    drawColorSlab(continuousRect(NSRect(x: 168*s, y: 262*s, width: 688*s, height: 500*s), 70*s), seed: 42)
    NSColor(white: 0.55, alpha: 1).setFill()
    continuousRect(NSRect(x: 140*s, y: 222*s, width: 744*s, height: 20*s), 10*s).fill()
}

func appIconFullBleed(_ s: CGFloat) {
    let tile = continuousRect(NSRect(x: 100*s, y: 100*s, width: 824*s, height: 824*s), 185*s)
    drawColorSlab(tile, seed: 77)
    // a black channel with the wallpaper's step, cut through the streaks
    NSGraphicsContext.saveGraphicsState(); tile.addClip()
    Palette.black.setFill()
    continuousRect(NSRect(x: 470*s, y: 440*s, width: 34*s, height: 560*s), 17*s).fill()
    continuousRect(NSRect(x: 300*s, y: 40*s, width: 204*s, height: 430*s), 34*s).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: Menu bar variants (template: drawn in a single colour, alpha varies)

let menuSize = NSSize(width: 19, height: 14)

/// Thin vertical stripes with varying opacity, fading downwards.
func templateStreaks(in r: NSRect, color: NSColor, seed: UInt64, step: CGFloat = 0.5) {
    var rng = RNG(s: seed)
    var x = r.minX
    while x < r.maxX - 0.01 {
        let a = rng.range(0.15, 1)
        NSGradient(colors: [color.withAlphaComponent(a * 0.15), color.withAlphaComponent(a)])!
            .draw(in: NSRect(x: x, y: r.minY, width: step, height: r.height), angle: 90)
        x += step
    }
}

/// A: outlined display, all four corners rounded, streaks inside.
func menuOutline(_ color: NSColor) {
    let r = NSRect(origin: .zero, size: menuSize).insetBy(dx: 0.75, dy: 0.75)
    let p = continuousRect(r, 3.5)
    NSGraphicsContext.saveGraphicsState(); p.addClip()
    templateStreaks(in: r.insetBy(dx: 1.75, dy: 1.75), color: color, seed: 5)
    NSGraphicsContext.restoreGraphicsState()
    color.setStroke(); p.lineWidth = 1.3; p.stroke()
}

/// B: three rounded slabs, the middle one stepped like the wallpaper.
func menuSlabs(_ color: NSColor) {
    let w: CGFloat = 5.4, g: CGFloat = 1.4, h = menuSize.height
    let slabs = [NSRect(x: 0, y: 3.5, width: w, height: h - 3.5),
                 NSRect(x: w + g, y: 7.5, width: w, height: h - 7.5),
                 NSRect(x: w + g, y: 0, width: w, height: 6.5),
                 NSRect(x: 2 * (w + g), y: 0, width: w, height: h)]
    for (i, r) in slabs.enumerated() {
        let p = continuousRect(r, 1.8)
        NSGraphicsContext.saveGraphicsState(); p.addClip()
        templateStreaks(in: r, color: color, seed: UInt64(10 + i))
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// C: solid rounded display made of streaks, no outline.
func menuSolid(_ color: NSColor) {
    let r = NSRect(origin: .zero, size: menuSize).insetBy(dx: 0.5, dy: 0.5)
    let p = continuousRect(r, 3.5)
    NSGraphicsContext.saveGraphicsState(); p.addClip()
    templateStreaks(in: r, color: color, seed: 9)
    NSGraphicsContext.restoreGraphicsState()
    color.withAlphaComponent(0.6).setStroke(); p.lineWidth = 0.6; p.stroke()
}

// MARK: Colour menu bar icon (icon C in icon 2's palette)

enum MenuTone { case deep, frosted, ember, steel }

/// Icon C in full colour: streaks in 0.5 pt steps (one Retina pixel) so they stay crisp at 19×14 pt.
func menuColor(_ tone: MenuTone, seed: UInt64 = 9) {
    let r = NSRect(origin: .zero, size: menuSize).insetBy(dx: 0.5, dy: 0.5)
    let p = continuousRect(r, 3.5)
    var rng = RNG(s: seed)
    let phase = rng.range(0, 6)
    NSGraphicsContext.saveGraphicsState(); p.addClip()
    Palette.black.setFill(); r.fill()
    var x = r.minX
    while x < r.maxX - 0.01 {
        let b = band((x - r.minX) / r.width, phase, &rng)
        var lit = mix(mix(Palette.navy, Palette.steel, b * 1.6), Palette.ice, (b - 0.4) * 1.8)
        var dark = mix(Palette.black, Palette.navy, b * 0.5)
        switch tone {
        case .deep: break
        case .frosted:
            lit = mix(lit, Palette.ice, 0.35); dark = mix(dark, Palette.steel, 0.45)
        case .ember: break
        case .steel:
            lit = mix(Palette.steel, Palette.ice, b); dark = mix(Palette.navy, Palette.steel, b * 0.4)
        }
        NSGradient(colors: [dark, lit], atLocations: [0.05, 0.85], colorSpace: .sRGB)!
            .draw(in: NSRect(x: x, y: r.minY, width: 0.5, height: r.height), angle: 90)
        x += 0.5
    }
    if tone == .ember || tone == .deep {
        // one warm accent streak like the wallpaper's orange/red lines
        NSGradient(colors: [Palette.accents[1], Palette.accents[0], Palette.accents[0].withAlphaComponent(0)],
                   atLocations: [0, 0.4, 1], colorSpace: .sRGB)!
            .draw(in: NSRect(x: r.minX + r.width * 0.68, y: r.minY, width: 0.5, height: r.height * 0.75), angle: 90)
    }
    if tone == .ember {
        NSGradient(colors: [NSColor(srgbRed: 1, green: 0.72, blue: 0.4, alpha: 1), .clear])!
            .draw(in: NSRect(x: r.minX, y: r.minY, width: r.width, height: 1.5), angle: 90)
    }
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 1, alpha: tone == .steel ? 0.5 : 0.4).setStroke()
    p.lineWidth = 0.5; p.stroke()
}
