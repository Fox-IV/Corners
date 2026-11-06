import AppKit
let W: CGFloat = 1200, H: CGFloat = 760, scale: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W*scale), pixelsHigh: Int(H*scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 15, color: NSColor = .white, bold: Bool = false) {
    NSAttributedString(string: s, attributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .foregroundColor: color]).draw(at: NSPoint(x: x, y: y))
}
func at(_ x: CGFloat, _ y: CGFloat, _ f: () -> Void) {
    NSGraphicsContext.saveGraphicsState(); let t = NSAffineTransform(); t.translateX(by: x, yBy: y); t.concat(); f(); NSGraphicsContext.restoreGraphicsState()
}
func scaled(_ k: CGFloat, _ f: () -> Void) { let t = NSAffineTransform(); t.scale(by: k); t.concat(); f() }
let grey = NSColor(white: 0.8, alpha: 1)

text("Menu bar icon C in colour, to match app icon 2", 40, H - 50, size: 22, bold: true)
at(40, H - 300) { appIconScreen(230/1024) }
text("App icon 2 (for reference)", 62, H - 320, size: 14, color: grey)

let tones: [(String, MenuTone)] = [("C1 · Deep", .deep), ("C2 · Frosted", .frosted), ("C3 · Ember", .ember), ("C4 · Steel", .steel)]
for (i, (name, tone)) in tones.enumerated() {
    let x = 330 + CGFloat(i) * 215
    at(x, H - 250) { scaled(9) { menuColor(tone) } }
    text(name, x, H - 285, size: 16, color: grey)
}

text("Real size", 40, 330, size: 18, bold: true)
for (row, (bg, fg)) in [(NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1), NSColor.black), (NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1), NSColor.white)].enumerated() {
    let y = 280 - CGFloat(row) * 40
    bg.setFill(); NSRect(x: 40, y: y, width: 1120, height: 24).fill()
    let ink = fg.withAlphaComponent(0.85)
    for (i, (name, tone)) in tones.enumerated() {
        let x = 90 + CGFloat(i) * 250
        at(x, y + 5) { menuColor(tone) }
        text(name, x + 28, y + 3, size: 13, color: ink)
    }
    text("14:32", 1110, y + 3, size: 13, color: ink)
}
// against a wallpaper-ish tinted menu bar, since macOS menu bars are translucent
text("Over a tinted (translucent) menu bar", 40, 160, size: 18, bold: true)
NSGradient(colors: [NSColor(srgbRed: 0.35, green: 0.45, blue: 0.62, alpha: 1), NSColor(srgbRed: 0.12, green: 0.16, blue: 0.25, alpha: 1)])!
    .draw(in: NSRect(x: 40, y: 110, width: 1120, height: 24), angle: 0)
for (i, (name, tone)) in tones.enumerated() {
    let x = 90 + CGFloat(i) * 250
    at(x, 115) { menuColor(tone) }
    text(name, x + 28, 113, size: 13, color: .white)
}
text("Colour icons stay the same in light and dark mode; they don't flip to black or white like the system icons.", 40, 60, size: 14, color: grey)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon-preview-c.png"))
