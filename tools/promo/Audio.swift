// Synthesised soundtrack for the promo, timed to the animation in main.swift,
// plus the step that muxes it into the final MP4. Everything is generated
// here: no samples or third-party audio.
import AVFoundation

let SR = 48_000

struct Bus {
    var l: [Float], r: [Float]
    init(_ n: Int) { l = .init(repeating: 0, count: n); r = .init(repeating: 0, count: n) }
    mutating func add(_ i: Int, _ v: Float, pan: Float = 0) {
        guard i >= 0, i < l.count else { return }
        l[i] += v * (1 - pan) * 0.5 * 1.41
        r[i] += v * (1 + pan) * 0.5 * 1.41
    }
}

struct Noise {
    var s: UInt32 = 0x9E3779B9
    mutating func next() -> Float {
        s ^= s << 13; s ^= s >> 17; s ^= s << 5
        return Float(s) / Float(UInt32.max) * 2 - 1
    }
}

/// Chamberlin state-variable filter.
struct SVF {
    var low: Float = 0, band: Float = 0
    mutating func run(_ x: Float, cutoff: Float, q: Float) -> (low: Float, band: Float, high: Float) {
        let f = 2 * sin(Float.pi * min(cutoff, 18_000) / Float(SR))
        low += f * band
        let high = x - low - q * band
        band += f * high
        return (low, band, high)
    }
}

func smooth(_ x: Double) -> Float { let x = max(0, min(1, x)); return Float(x * x * (3 - 2 * x)) }

// MARK: Voices

/// Soft sustained chord: detuned sines with a couple of harmonics, slow vibrato.
func pad(_ dry: inout Bus, _ wet: inout Bus, notes: [Double], from: Double, to: Double,
         level: (Double) -> Float) {
    for (k, f0) in notes.enumerated() {
        for (d, pan) in [(0.9985, Float(-0.5)), (1.0015, Float(0.5))] {
            var ph = Double(k) * 0.7
            for i in Int(from * Double(SR))..<Int(to * Double(SR)) {
                let t = Double(i) / Double(SR)
                let f = f0 * d * (1 + 0.0015 * sin(2 * .pi * 0.23 * t + Double(k)))
                ph += 2 * .pi * f / Double(SR)
                let v = Float(sin(ph) + 0.22 * sin(2 * ph) + 0.06 * sin(3 * ph)) * level(t) * 0.05
                dry.add(i, v, pan: pan * 0.6); wet.add(i, v * 0.8, pan: pan)
            }
        }
    }
}

/// Bell-like chime: inharmonic partials with fast attack and long decay.
func chime(_ dry: inout Bus, _ wet: inout Bus, at t0: Double, freq: Double, amp: Float, pan: Float, decay: Double = 1.6) {
    let partials: [(Double, Float, Double)] = [(1, 1, 1), (2.0, 0.35, 0.6), (2.76, 0.25, 0.45), (5.4, 0.08, 0.25)]
    let n = Int((decay * 3) * Double(SR))
    let start = Int(t0 * Double(SR))
    for i in 0..<n {
        let t = Double(i) / Double(SR)
        let atk = Float(min(1, t / 0.004))
        var v: Float = 0
        for (m, a, dk) in partials {
            v += a * Float(sin(2 * .pi * freq * m * t) * exp(-t / (decay * dk)))
        }
        v *= atk * amp
        dry.add(start + i, v * 0.7, pan: pan); wet.add(start + i, v, pan: -pan * 0.5)
    }
}

/// Short glassy tick: a click of filtered noise plus a very short high ping.
func tick(_ dry: inout Bus, _ wet: inout Bus, at t0: Double, amp: Float, pan: Float) {
    var noise = Noise(), svf = SVF()
    let start = Int(t0 * Double(SR))
    for i in 0..<Int(0.12 * Double(SR)) {
        let t = Double(i) / Double(SR)
        let n = svf.run(noise.next(), cutoff: 6_000, q: 0.6).high * Float(exp(-t / 0.004))
        let ping = Float(sin(2 * .pi * 3_520 * t) * exp(-t / 0.025)) * 0.5
        let v = (n + ping) * amp
        dry.add(start + i, v, pan: pan); wet.add(start + i, v * 0.6, pan: pan)
    }
}

/// Rising shimmer: band-passed noise sweeping up plus a cluster of high sines.
func riser(_ dry: inout Bus, _ wet: inout Bus, from: Double, to: Double, amp: Float, pan: Float) {
    var noise = Noise(s: 1234), svf = SVF()
    let tones = [2_349.3, 2_637.0, 3_520.0, 4_698.6]
    for i in Int(from * Double(SR))..<Int(to * Double(SR)) {
        let t = Double(i) / Double(SR)
        let p = (t - from) / (to - from)
        let env = smooth(p) * smooth(p) * amp
        let cutoff = Float(700 * pow(9.0, p))
        var v = svf.run(noise.next(), cutoff: cutoff, q: 0.25).band * 0.6
        for (k, f) in tones.enumerated() {
            v += Float(sin(2 * .pi * f * t + Double(k))) * 0.08 * Float(0.5 + 0.5 * sin(2 * .pi * (5 + Double(k)) * t))
        }
        dry.add(i, v * env * 0.5, pan: pan); wet.add(i, v * env, pan: -pan)
    }
}

/// Camera whoosh: noise through a sweeping low-pass, panning across.
func whoosh(_ dry: inout Bus, _ wet: inout Bus, from: Double, to: Double, amp: Float) {
    var noise = Noise(s: 777), svf = SVF()
    for i in Int(from * Double(SR))..<Int(to * Double(SR)) {
        let t = Double(i) / Double(SR)
        let p = (t - from) / (to - from)
        let shape = Float(sin(.pi * pow(p, 0.8)))
        let env = shape * shape * amp
        let cutoff = 250 + 3_200 * shape
        let v = svf.run(noise.next(), cutoff: cutoff, q: 0.5).low * env
        let pan = Float(p * 1.4 - 0.7)
        dry.add(i, v, pan: pan); wet.add(i, v * 0.5, pan: -pan)
    }
}

/// Deep sub hit with a falling pitch, for when a shot lands.
func sub(_ dry: inout Bus, _ wet: inout Bus, at t0: Double, amp: Float) {
    let start = Int(t0 * Double(SR))
    var ph = 0.0
    for i in 0..<Int(2.2 * Double(SR)) {
        let t = Double(i) / Double(SR)
        let f = 42 + 55 * exp(-t / 0.07)
        ph += 2 * .pi * f / Double(SR)
        let env = Float(min(1, t / 0.006) * exp(-t / 0.55))
        let v = Float(sin(ph)) * env * amp
        dry.add(start + i, v); wet.add(start + i, v * 0.15)
    }
}

// MARK: Reverb (Schroeder: parallel damped combs into series all-passes)

func reverb(_ x: [Float], combs: [Int], allpasses: [Int], feedback: Float = 0.86, damp: Float = 0.3) -> [Float] {
    var out = [Float](repeating: 0, count: x.count)
    for d in combs {
        var buf = [Float](repeating: 0, count: d), idx = 0, lp: Float = 0
        for i in 0..<x.count {
            let y = buf[idx]
            lp = y * (1 - damp) + lp * damp
            buf[idx] = x[i] + lp * feedback
            idx = (idx + 1) % d
            out[i] += y / Float(combs.count)
        }
    }
    for d in allpasses {
        var buf = [Float](repeating: 0, count: d), idx = 0
        for i in 0..<out.count {
            let b = buf[idx], v = out[i]
            let y = -v * 0.7 + b
            buf[idx] = v + b * 0.7
            idx = (idx + 1) % d
            out[i] = y
        }
    }
    return out
}

// MARK: Score

func renderSoundtrack(duration: Double) -> Bus {
    let n = Int(duration * Double(SR))
    var dry = Bus(n), wet = Bus(n)

    // D major add9 pad; lifts an octave at the final reveal
    let base = [146.83, 220.0, 293.66, 329.63, 369.99]
    pad(&dry, &wet, notes: base, from: 0, to: duration) { t in
        let swell = 0.55 * smooth(t / 1.6) + 0.25 * smooth((t - 3.8) / 1.0) + 0.2 * smooth((t - 6.4) / 1.0)
        return Float(swell) * (1 - smooth((t - 8.6) / 0.8))
    }
    pad(&dry, &wet, notes: [587.33, 739.99, 880.0], from: 6.0, to: duration) { t in
        0.55 * smooth((t - 6.6) / 1.2) * (1 - smooth((t - 8.6) / 0.8))
    }

    // laptop corner rounds (0.5–1.9 s)
    tick(&dry, &wet, at: 0.5, amp: 0.18, pan: -0.3)
    riser(&dry, &wet, from: 0.5, to: 1.9, amp: 0.22, pan: -0.3)
    chime(&dry, &wet, at: 1.88, freq: 1_174.66, amp: 0.16, pan: -0.25)
    chime(&dry, &wet, at: 1.93, freq: 1_760.0, amp: 0.07, pan: 0.2)

    // pull back to the laptop (2.6–4.6 s), lands with a sub
    whoosh(&dry, &wet, from: 2.5, to: 4.6, amp: 0.5)
    sub(&dry, &wet, at: 4.5, amp: 0.55)
    tick(&dry, &wet, at: 4.5, amp: 0.15, pan: 0)

    // pull back to reveal the monitor (5.4–7.0 s)
    whoosh(&dry, &wet, from: 5.3, to: 7.0, amp: 0.45)
    sub(&dry, &wet, at: 6.9, amp: 0.4)

    // monitor corners round (6.6–7.6 s): brighter arpeggiated chime
    riser(&dry, &wet, from: 6.6, to: 7.6, amp: 0.2, pan: 0.35)
    tick(&dry, &wet, at: 6.6, amp: 0.25, pan: 0.4)
    for (k, f) in [1_174.66, 1_479.98, 1_760.0, 2_349.32].enumerated() {
        chime(&dry, &wet, at: 7.58 + Double(k) * 0.06, freq: f, amp: 0.13 - Float(k) * 0.02,
              pan: 0.4 - Float(k) * 0.2, decay: 1.9)
    }

    // mix: dry + stereo reverb, gentle saturation, normalise to -1 dBFS, fade out
    let wl = reverb(wet.l, combs: [1557, 1617, 1491, 1422, 1277, 1356], allpasses: [225, 556, 441])
    let wr = reverb(wet.r, combs: [1580, 1640, 1514, 1445, 1300, 1379], allpasses: [248, 579, 464])
    var out = Bus(n)
    for i in 0..<n {
        let t = Double(i) / Double(SR)
        let g = (1 - smooth((t - 8.7) / 0.7)) * min(1, Float(t / 0.02))
        out.l[i] = tanh((dry.l[i] + wl[i] * 0.9) * 1.1) * g
        out.r[i] = tanh((dry.r[i] + wr[i] * 0.9) * 1.1) * g
    }
    let peak = max(out.l.map(abs).max() ?? 1, out.r.map(abs).max() ?? 1)
    let gain = 0.89 / max(peak, 0.0001)
    for i in 0..<n { out.l[i] *= gain; out.r[i] *= gain }
    return out
}

// MARK: Write + mux

func writeAudio(_ bus: Bus, to url: URL) throws {
    try? FileManager.default.removeItem(at: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: Double(SR), channels: 2)!
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: SR, AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 256_000,
    ])
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bus.l.count))!
    buf.frameLength = AVAudioFrameCount(bus.l.count)
    bus.l.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: bus.l.count) }
    bus.r.withUnsafeBufferPointer { buf.floatChannelData![1].update(from: $0.baseAddress!, count: bus.r.count) }
    try file.write(from: buf)
}

func mux(video: URL, audio: URL, to out: URL) throws {
    try? FileManager.default.removeItem(at: out)
    let comp = AVMutableComposition()
    let v = AVURLAsset(url: video), a = AVURLAsset(url: audio)
    let range = CMTimeRange(start: .zero, duration: v.duration)
    try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(range, of: v.tracks(withMediaType: .video)[0], at: .zero)
    try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: .zero, duration: min(a.duration, v.duration)),
                         of: a.tracks(withMediaType: .audio)[0], at: .zero)
    let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
    export.outputURL = out
    export.outputFileType = .mp4
    let done = DispatchSemaphore(value: 0)
    export.exportAsynchronously { done.signal() }
    done.wait()
    if export.status != .completed { throw export.error ?? NSError(domain: "mux", code: 1) }
}
