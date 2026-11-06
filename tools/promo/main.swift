// Renders the promo video: a close-up of a laptop's square bottom corner that
// rounds off, a pull-back to the whole laptop, then a reveal of an external
// display whose corners round too. The soundtrack is synthesised in Audio.swift.
//
//   swiftc -O Sources/Artwork.swift tools/promo/*.swift -o build/obj/promo
//   build/obj/promo build/corners-promo.mp4 [--stills dir]
import AppKit
import AVFoundation

let W = 1920, H = 1080, FPS = 30
let duration = 9.4
let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "build/corners-promo.mp4"
let stillsDir: String? = args.firstIndex(of: "--stills").map { args[$0 + 1] }

enum Corners { case topLeft, topRight, bottomLeft, bottomRight
    static let ordered: [(Corners, String)] = [(.topLeft, ""), (.topRight, ""), (.bottomLeft, ""), (.bottomRight, "")] }

// MARK: Scene (world units, y up)

let laptopScreen = NSRect(x: -756, y: -491, width: 1512, height: 982)
let monitorScreen = NSRect(x: 1520, y: -380, width: 1900, height: 1069)
let hardwareRadius: CGFloat = 18

func ease(_ x: Double) -> CGFloat {
    let x = max(0, min(1, x))
    return CGFloat(x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2)
}
func progress(_ t: Double, _ a: Double, _ b: Double) -> CGFloat { ease((t - a) / (b - a)) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat { a + (b - a) * p }
func fade(_ t: Double, _ a: Double, _ b: Double, _ edge: Double = 0.3) -> CGFloat {
    min(progress(t, a, a + edge), 1 - progress(t, b - edge, b))
}

/// Streaks lit along the bottom edge (where the corners are), dipping dark mid-screen.
func drawWallpaper(_ r: NSRect, seed: UInt64) {
    var rng = RNG(s: seed)
    let phase = rng.range(0, 6)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: r).addClip()
    Palette.black.setFill(); r.fill()
    var x = r.minX
    while x < r.maxX {
        let w = r.width * rng.range(0.003, 0.014)
        let b = band((x - r.minX) / r.width, phase, &rng)
        let lit = mix(mix(Palette.navy, Palette.steel, b * 1.6), Palette.ice, (b - 0.4) * 1.8)
        let dark = mix(Palette.black, Palette.navy, b * 0.6)
        let f = rng.range(0.4, 0.7)
        NSGradient(colors: [lit, mix(dark, lit, 0.25), dark, mix(dark, lit, 0.5)],
                   atLocations: [0, f * 0.45, f, 1], colorSpace: .sRGB)!
            .draw(in: NSRect(x: x, y: r.minY, width: w + 0.6, height: r.height), angle: 90)
        x += w
    }
    for _ in 0..<5 {
        let ax = r.minX + r.width * rng.range(0.05, 0.95)
        let c = Palette.accents[Int(rng.next() * 2.99)]
        NSGradient(colors: [c.withAlphaComponent(0), c, c.withAlphaComponent(0)])!
            .draw(in: NSRect(x: ax, y: r.minY + r.height * rng.range(0.05, 0.25),
                             width: r.width * 0.0022, height: r.height * 0.4), angle: 90)
    }
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.72, blue: 0.42, alpha: 0.95), .clear])!
        .draw(in: NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.018), angle: 90)
    NSGraphicsContext.restoreGraphicsState()
}

/// Black corner mask (and its curve, for the highlight) in the given corner of `r`.
func corner(_ r: NSRect, _ c: Corners, _ radius: CGFloat) -> (fill: NSBezierPath, curve: NSBezierPath) {
    let e = radius * 1.528665, n: CGFloat = 3.26
    let right = c == .bottomRight || c == .topRight, top = c == .topLeft || c == .topRight
    func map(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: right ? r.maxX - x : r.minX + x, y: top ? r.maxY - y : r.minY + y)
    }
    let pts = (0...48).map { i -> NSPoint in
        let a = CGFloat(i) / 48 * .pi / 2
        return map(e - e * pow(cos(a), 2 / n), e - e * pow(sin(a), 2 / n))
    }
    let fill = NSBezierPath(), curve = NSBezierPath()
    fill.move(to: map(-3, -3)); fill.line(to: map(-3, e)); pts.forEach { fill.line(to: $0) }; fill.line(to: map(e, -3)); fill.close()
    curve.move(to: pts[0]); pts.dropFirst().forEach { curve.line(to: $0) }
    return (fill, curve)
}

let bezel = NSColor(srgbRed: 0.035, green: 0.035, blue: 0.04, alpha: 1)

func drawScreenCorners(_ r: NSRect, _ corners: [(Corners, CGFloat)], glint: CGFloat, scale: CGFloat) {
    for (c, radius) in corners where radius > 0.01 {
        let p = corner(r, c, radius)
        bezel.setFill(); p.fill.fill()
        if glint > 0 {
            Palette.ice.withAlphaComponent(glint).setStroke()
            p.curve.lineWidth = 4 / scale
            p.curve.stroke()
        }
    }
}

func drawLaptop(bottomRadius: CGFloat, glint: CGFloat, scale: CGFloat) {
    let s = laptopScreen
    // lid with aluminium edge
    let lid = NSBezierPath(roundedRect: s.insetBy(dx: -26, dy: -26).offsetBy(dx: 0, dy: -4)
        .union(NSRect(x: s.minX - 26, y: s.minY - 42, width: s.width + 52, height: 20)), xRadius: 44, yRadius: 44)
    bezel.setFill(); lid.fill()
    NSColor(srgbRed: 0.32, green: 0.34, blue: 0.38, alpha: 1).setStroke()
    lid.lineWidth = 4; lid.stroke()
    drawWallpaper(s, seed: 42)
    // hardware-rounded top corners, notch
    drawScreenCorners(s, [(.topLeft, hardwareRadius), (.topRight, hardwareRadius)], glint: 0, scale: scale)
    bezel.setFill()
    NSBezierPath(roundedRect: NSRect(x: -100, y: s.maxY - 34, width: 200, height: 60), xRadius: 12, yRadius: 12).fill()
    // Corners' bottom masks
    drawScreenCorners(s, [(.bottomLeft, bottomRadius), (.bottomRight, bottomRadius)], glint: glint, scale: scale)
    // base
    let base = NSBezierPath(roundedRect: NSRect(x: -880, y: -584, width: 1760, height: 34), xRadius: 17, yRadius: 17)
    NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.37, blue: 0.41, alpha: 1),
                        NSColor(srgbRed: 0.72, green: 0.74, blue: 0.78, alpha: 1)])!.draw(in: base, angle: 90)
    NSColor(srgbRed: 0.25, green: 0.26, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: -120, y: -556, width: 240, height: 8), xRadius: 4, yRadius: 4).fill()
}

func drawMonitor(radius: CGFloat, glint: CGFloat, scale: CGFloat) {
    let s = monitorScreen
    // stand
    let silver = NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.43, blue: 0.47, alpha: 1),
                                     NSColor(srgbRed: 0.70, green: 0.72, blue: 0.76, alpha: 1)])!
    silver.draw(in: NSBezierPath(rect: NSRect(x: s.midX - 110, y: -570, width: 220, height: 200)), angle: 0)
    silver.draw(in: NSBezierPath(roundedRect: NSRect(x: s.midX - 330, y: -584, width: 660, height: 22), xRadius: 11, yRadius: 11), angle: 90)
    let body = NSBezierPath(roundedRect: s.insetBy(dx: -24, dy: -24), xRadius: 20, yRadius: 20)
    bezel.setFill(); body.fill()
    NSColor(srgbRed: 0.30, green: 0.32, blue: 0.36, alpha: 1).setStroke()
    body.lineWidth = 4; body.stroke()
    drawWallpaper(s, seed: 1337)
    drawScreenCorners(s, Corners.ordered.map { ($0.0, radius) }, glint: glint, scale: scale)
}

// MARK: Camera

struct Cam { var x: CGFloat; var y: CGFloat; var scale: CGFloat }
let close = Cam(x: laptopScreen.minX + 71, y: laptopScreen.minY + 40, scale: 4.5)
let laptopShot = Cam(x: 0, y: -40, scale: 0.68)
let wideShot = Cam(x: 1282, y: 40, scale: 0.40)

func camera(_ t: Double) -> Cam {
    func blend(_ a: Cam, _ b: Cam, _ p: CGFloat) -> Cam {
        // zoom geometrically, and move so the pan speed tracks the zoom
        let s = exp(lerp(log(a.scale), log(b.scale), p))
        let k = a.scale == b.scale ? p : (1 / s - 1 / a.scale) / (1 / b.scale - 1 / a.scale)
        return Cam(x: lerp(a.x, b.x, k), y: lerp(a.y, b.y, k), scale: s)
    }
    if t < 2.6 { return close }
    if t < 5.4 { return blend(close, laptopShot, progress(t, 2.6, 4.6)) }
    return blend(laptopShot, wideShot, progress(t, 5.4, 7.0))
}

// MARK: Frame

func drawFrame(_ t: Double) {
    let full = NSRect(x: 0, y: 0, width: W, height: H)
    NSGradient(colors: [NSColor(srgbRed: 0.09, green: 0.11, blue: 0.15, alpha: 1),
                        NSColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1)])!
        .draw(in: NSBezierPath(rect: full), relativeCenterPosition: NSPoint(x: 0, y: 0.1))

    let cam = camera(t)
    let laptopRound = progress(t, 0.5, 1.9)
    let laptopGlint = sin(.pi * laptopRound) * 0.9
    let monitorRound = progress(t, 6.6, 7.6)
    let monitorGlint = sin(.pi * monitorRound)

    NSGraphicsContext.saveGraphicsState()
    let tr = NSAffineTransform()
    tr.translateX(by: CGFloat(W) / 2, yBy: CGFloat(H) / 2)
    tr.scale(by: cam.scale)
    tr.translateX(by: -cam.x, yBy: -cam.y)
    tr.concat()
    drawLaptop(bottomRadius: hardwareRadius * laptopRound, glint: laptopGlint, scale: cam.scale)
    drawMonitor(radius: hardwareRadius * 1.7 * monitorRound, glint: monitorGlint, scale: cam.scale)
    NSGraphicsContext.restoreGraphicsState()

    // hold on the wide shot, then fade out
    let out = progress(t, 8.7, 9.4)
    if out > 0 { NSColor(white: 0, alpha: out).setFill(); full.fill() }
}

// MARK: Encode

let url = URL(fileURLWithPath: outPath + ".silent.mp4")
try? FileManager.default.removeItem(at: url)
let writer = try! AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let stillTimes: [Double] = [4.6, 5.0, 5.4, 5.8, 6.2, 6.6, 7.0, 7.6, 8.5]
let frames = Int(duration * Double(FPS))
for f in 0..<frames {
    let t = Double(f) / Double(FPS)
    while !input.isReadyForMoreMediaData { usleep(2000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    let buf = pb!
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    drawFrame(t)
    if let dir = stillsDir, stillTimes.contains(where: { abs($0 - t) < 0.5 / Double(FPS) }), let img = ctx.makeImage() {
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "\(dir)/still-\(String(format: "%04.1f", t)).png"))
    }
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime: CMTime(value: Int64(f), timescale: CMTimeScale(FPS)))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("Video failed: \(String(describing: writer.error))") }

let audioURL = URL(fileURLWithPath: outPath + ".audio.m4a")
try! writeAudio(renderSoundtrack(duration: duration), to: audioURL)
try! mux(video: url, audio: audioURL, to: URL(fileURLWithPath: outPath))
try? FileManager.default.removeItem(at: url)
try? FileManager.default.removeItem(at: audioURL)
print("Wrote \(outPath) (\(frames) frames + soundtrack)")
