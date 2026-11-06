// Corners — rounds the corners of every Mac display to match the
// hardware-rounded corners of notched MacBook Pro / Air screens.
//
// How it works: one transparent, click-through window per display sits above
// everything (menu bar, Dock, full-screen apps) and paints black "corner
// masks". On a notched MacBook the hardware already rounds the top corners,
// so only the bottom two are painted; everywhere else all four are.

import AppKit
import IOKit
import ServiceManagement

// MARK: - Model

struct Corners: OptionSet, Codable, Hashable {
    let rawValue: Int
    static let topLeft = Corners(rawValue: 1)
    static let topRight = Corners(rawValue: 2)
    static let bottomLeft = Corners(rawValue: 4)
    static let bottomRight = Corners(rawValue: 8)
    static let top: Corners = [.topLeft, .topRight]
    static let bottom: Corners = [.bottomLeft, .bottomRight]
    static let all: Corners = [.top, .bottom]

    static let ordered: [(Corners, String)] = [
        (.topLeft, "Top Left"), (.topRight, "Top Right"),
        (.bottomLeft, "Bottom Left"), (.bottomRight, "Bottom Right"),
    ]
}

struct DisplaySettings: Codable, Equatable {
    var enabled: Bool
    var corners: Corners
    var radius: Double
}

enum Machine {
    /// e.g. "Mac15,6"
    static let modelIdentifier: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }()

    /// e.g. "MacBook Pro (14-inch, Nov 2023)" (Apple silicon), else the identifier.
    static let productName: String = {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        defer { IOObjectRelease(entry) }
        if entry != 0,
           let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
               .takeRetainedValue() as? Data {
            let name = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
            if !name.isEmpty { return name }
        }
        return modelIdentifier
    }()

    /// Known notched (hardware-rounded top corners) laptops. Used only as a
    /// fallback — the primary signal is the screen's safe-area inset.
    static let knownNotchedModels: Set<String> = [
        "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4", // 2021 M1 Pro/Max
        "Mac14,2", "Mac14,15",                                                 // Air M2 13/15
        "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10",                           // MBP M2 Pro/Max
        "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11", // MBP M3
        "Mac15,12", "Mac15,13",                                                // Air M3
        "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8",                 // MBP M4
        "Mac16,12", "Mac16,13",                                                // Air M4
    ]
}

struct Display {
    let id: CGDirectDisplayID
    let screen: NSScreen
    let uuid: String
    let name: String
    let isBuiltin: Bool
    let hasNotch: Bool

    init(screen: NSScreen) {
        self.screen = screen
        id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        if let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let s = CFUUIDCreateString(nil, u) as String? {
            uuid = s
        } else {
            uuid = "display-\(id)"
        }
        name = screen.localizedName
        isBuiltin = CGDisplayIsBuiltin(id) != 0
        hasNotch = isBuiltin && (screen.safeAreaInsets.top > 0
            || Machine.knownNotchedModels.contains(Machine.modelIdentifier))
    }

    /// Corners the panel itself already rounds.
    var hardwareCorners: Corners { hasNotch ? .top : [] }

    var autoSettings: DisplaySettings {
        DisplaySettings(enabled: true,
                        corners: Corners.all.subtracting(hardwareCorners),
                        radius: Store.defaultRadius)
    }

    var summary: String {
        if hasNotch { return "Hardware rounds the top corners → adding the bottom two" }
        if isBuiltin { return "No rounded corners in hardware → adding all four" }
        return "External display → adding all four"
    }
}

// MARK: - Persistence

enum Store {
    static let d = UserDefaults.standard
    /// Close to the physical top-corner radius of notched MacBook panels (in points
    /// at default scaling). Fine-tune with the slider + calibration guides.
    static let defaultRadius = 10.0

    static var enabled: Bool {
        get { d.object(forKey: "enabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "enabled") }
    }
    static var continuous: Bool {
        get { d.object(forKey: "continuous") as? Bool ?? true }
        set { d.set(newValue, forKey: "continuous") }
    }

    static func settings(for display: Display) -> DisplaySettings {
        if let data = d.data(forKey: "display." + display.uuid),
           let s = try? JSONDecoder().decode(DisplaySettings.self, from: data) {
            return s
        }
        return display.autoSettings
    }
    static func save(_ s: DisplaySettings, for display: Display) {
        if let data = try? JSONEncoder().encode(s) { d.set(data, forKey: "display." + display.uuid) }
    }
    static func reset(_ display: Display) { d.removeObject(forKey: "display." + display.uuid) }
}

// MARK: - Drawing

final class CornerView: NSView {
    var corners: Corners = [] { didSet { needsDisplay = true } }
    var guideCorners: Corners = [] { didSet { needsDisplay = true } }
    var radius: CGFloat = 10 { didSet { needsDisplay = true } }
    var continuous = true { didSet { needsDisplay = true } }
    var calibrating = false { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    /// Extent along each edge and superellipse exponent. The "continuous"
    /// curve mimics Apple's squircle corners: it starts ~1.53× the radius from
    /// the corner and passes through the same 45° point as a circular arc.
    private var shape: (extent: CGFloat, exponent: CGFloat) {
        continuous ? (radius * 1.528665, 3.26) : (radius, 2)
    }

    /// Points along the corner curve, from the vertical edge to the horizontal
    /// edge, mapped into the requested corner of the view.
    private func curvePoints(_ corner: Corners) -> [CGPoint] {
        let (e, n) = shape
        let w = bounds.width, h = bounds.height
        let flipX = corner == .bottomRight || corner == .topRight
        let flipY = corner == .topLeft || corner == .topRight
        let steps = 48
        return (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps) * .pi / 2
            let x = e - e * pow(cos(t), 2 / n)
            let y = e - e * pow(sin(t), 2 / n)
            return CGPoint(x: flipX ? w - x : x, y: flipY ? h - y : y)
        }
    }

    private func cornerOrigin(_ corner: Corners) -> CGPoint {
        CGPoint(x: (corner == .bottomRight || corner == .topRight) ? bounds.width : 0,
                y: (corner == .topLeft || corner == .topRight) ? bounds.height : 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
        guard radius > 0 else { return }

        (calibrating ? NSColor.systemRed : NSColor.black).setFill()
        for (c, _) in Corners.ordered where corners.contains(c) {
            let p = NSBezierPath()
            p.move(to: cornerOrigin(c))
            curvePoints(c).forEach { p.line(to: $0) }
            p.close()
            p.fill()
        }

        // Calibration guide on hardware-rounded corners: the line stays hidden
        // behind the bezel while our radius ≤ the panel's radius.
        if calibrating {
            NSColor.systemRed.setStroke()
            for (c, _) in Corners.ordered where guideCorners.contains(c) {
                let p = NSBezierPath()
                let pts = curvePoints(c)
                p.move(to: pts[0])
                pts.dropFirst().forEach { p.line(to: $0) }
                p.lineWidth = 1
                p.stroke()
            }
        }
    }
}

final class OverlayWindow: NSWindow {
    let cornerView = CornerView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        sharingType = .none // keep screenshots/recordings clean, like real hardware corners
        contentView = cornerView
        setFrame(screen.frame, display: false)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Menu helpers

final class ClosureTarget: NSObject {
    let handler: (NSMenuItem) -> Void
    init(_ handler: @escaping (NSMenuItem) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSMenuItem) { handler(sender) }
}

final class SliderItemView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let onChange: (Double) -> Void

    init(value: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        slider = NSSlider(value: value, minValue: 0, maxValue: 40, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 46))
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.frame = NSRect(x: 20, y: 4, width: 224, height: 22)
        label.frame = NSRect(x: 21, y: 26, width: 224, height: 16)
        label.font = .menuFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        addSubview(slider)
        addSubview(label)
        updateLabel()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateLabel() { label.stringValue = String(format: "Radius: %.1f pt", slider.doubleValue) }

    @objc private func changed() {
        slider.doubleValue = (slider.doubleValue * 2).rounded() / 2 // 0.5 pt steps
        updateLabel()
        onChange(slider.doubleValue)
    }
}

// MARK: - App

final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var displays: [Display] = []
    private var windows: [String: OverlayWindow] = [:]
    private var targets: [ClosureTarget] = []
    private var calibrating = false
    private var rebuildWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Full-colour "Ember" icon (Artwork.swift), matching the app icon.
        let icon = NSImage(size: menuSize, flipped: false) { _ in menuColor(.ember); return true }
        icon.isTemplate = false
        icon.accessibilityDescription = "Corners"
        statusItem.button?.image = icon
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(scheduleRebuild),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(bringToFront),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(scheduleRebuild),
            name: NSWorkspace.didWakeNotification, object: nil)

        rebuild()
    }

    // MARK: Overlays

    @objc private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuild() }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func rebuild() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
        displays = NSScreen.screens.map(Display.init)
        for d in displays {
            windows[d.uuid] = OverlayWindow(screen: d.screen)
            apply(d)
        }
    }

    private func apply(_ d: Display) {
        guard let w = windows[d.uuid] else { return }
        let s = Store.settings(for: d)
        let on = Store.enabled && s.enabled
        let v = w.cornerView
        v.radius = CGFloat(s.radius)
        v.continuous = Store.continuous
        v.calibrating = calibrating
        v.corners = on ? s.corners : []
        v.guideCorners = on ? d.hardwareCorners : []
        if on && (!s.corners.isEmpty || (calibrating && !d.hardwareCorners.isEmpty)) {
            w.setFrame(d.screen.frame, display: true)
            w.orderFrontRegardless()
        } else {
            w.orderOut(nil)
        }
    }

    private func applyAll() { displays.forEach(apply) }

    @objc private func bringToFront() {
        windows.values.filter(\.isVisible).forEach { $0.orderFrontRegardless() }
    }

    private func update(_ d: Display, _ change: (inout DisplaySettings) -> Void) {
        var s = Store.settings(for: d)
        change(&s)
        Store.save(s, for: d)
        apply(d)
    }

    // MARK: Menu

    private func item(_ title: String, key: String = "", state: Bool? = nil,
                      _ handler: @escaping (NSMenuItem) -> Void) -> NSMenuItem {
        let t = ClosureTarget(handler)
        targets.append(t)
        let mi = NSMenuItem(title: title, action: #selector(ClosureTarget.fire(_:)), keyEquivalent: key)
        mi.target = t
        if let state { mi.state = state ? .on : .off }
        return mi
    }

    private func info(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        targets.removeAll()

        let header = info(Machine.productName)
        header.attributedTitle = NSAttributedString(string: Machine.productName,
                                                    attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(header)
        menu.addItem(info(Machine.modelIdentifier))
        menu.addItem(.separator())

        menu.addItem(item("Round Corners", key: "r", state: Store.enabled) { [weak self] _ in
            Store.enabled.toggle(); self?.applyAll()
        })
        menu.addItem(.separator())

        for d in displays {
            let s = Store.settings(for: d)
            let sub = NSMenu()
            sub.addItem(info(d.summary))
            sub.addItem(.separator())
            sub.addItem(item("Round This Display", state: s.enabled) { [weak self] _ in
                self?.update(d) { $0.enabled.toggle() }
            })
            sub.addItem(.separator())
            for (c, label) in Corners.ordered {
                let hw = d.hardwareCorners.contains(c)
                sub.addItem(item(label + (hw ? "  (rounded by hardware)" : ""),
                                 state: s.corners.contains(c)) { [weak self] _ in
                    self?.update(d) { $0.corners.formSymmetricDifference(c) }
                })
            }
            sub.addItem(.separator())
            let slider = NSMenuItem()
            slider.view = SliderItemView(value: s.radius) { [weak self] v in
                self?.update(d) { $0.radius = v }
            }
            sub.addItem(slider)
            sub.addItem(.separator())
            sub.addItem(item("Reset to Auto-Detected") { [weak self] _ in
                Store.reset(d); self?.apply(d)
            })

            let label = d.isBuiltin ? "\(d.name) — Built-in" : d.name
            let mi = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            mi.image = NSImage(systemSymbolName: d.isBuiltin ? "laptopcomputer" : "display",
                               accessibilityDescription: nil)
            mi.state = (Store.enabled && s.enabled && !s.corners.isEmpty) ? .on : .off
            mi.submenu = sub
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let style = NSMenu()
        style.addItem(item("Continuous (Apple-style squircle)", state: Store.continuous) { [weak self] _ in
            Store.continuous = true; self?.applyAll()
        })
        style.addItem(item("Circular", state: !Store.continuous) { [weak self] _ in
            Store.continuous = false; self?.applyAll()
        })
        let styleItem = NSMenuItem(title: "Corner Style", action: nil, keyEquivalent: "")
        styleItem.submenu = style
        menu.addItem(styleItem)

        menu.addItem(item("Calibrate Radius (show guides)", state: calibrating) { [weak self] _ in
            guard let self else { return }
            self.calibrating.toggle()
            self.applyAll()
            if self.calibrating { self.showCalibrationHelp() }
        })

        let loginOn = SMAppService.mainApp.status == .enabled
        menu.addItem(item("Launch at Login", state: loginOn) { _ in
            do {
                if loginOn { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            } catch {
                let a = NSAlert(error: error)
                a.informativeText = "Try moving Corners.app to /Applications first.\n\n\(error.localizedDescription)"
                NSApp.activate(ignoringOtherApps: true)
                a.runModal()
            }
        })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Corners", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func showCalibrationHelp() {
        let a = NSAlert()
        a.messageText = "Calibrating corners"
        a.informativeText = """
        The corners Corners paints are shown in red.

        On a notched MacBook a thin red line is also drawn along the top (hardware) corners. \
        Open the built-in display's menu and drag the radius up until that line just starts \
        to peek out from the corner, then nudge it back down one step — the bottom corners \
        now match the hardware.

        Turn off "Calibrate Radius" when you're done.
        """
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
