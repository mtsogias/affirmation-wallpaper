import Cocoa
import Accelerate

/// Sample affirmations for first launch. The live list is stored in
/// UserDefaults ("affirmations") and is never overwritten after that.
let defaultAffirmations: [String] = [
    "I am focused and present",
    "I finish what I start",
    "I am calm, confident, and clear",
    "I make time for what matters",
    "I grow a little every day",
    "How can I make it more fun?",
    "I am already the person I am becoming",
    "Everything I need is already here",
]

// ---------------------------------------------------------------------------
// AuroraRenderer: computes the aurora frame ONCE, shared by all screens
// ---------------------------------------------------------------------------

class AuroraRenderer {

    struct Wave {
        let fx: CGFloat
        let fy: CGFloat
        var ph: CGFloat
        let sp: CGFloat
        let ax: CGFloat
    }

    private var waves: [Wave] = []
    /// Base palette (RGB 0-1). The color LUT is built from these, optionally
    /// hue-rotated via setHueShift().
    private let baseColors: [(Float, Float, Float)] = [
        (15/255, 8/255, 25/255),
        (40/255, 12/255, 60/255),
        (80/255, 20/255, 70/255),
        (140/255, 30/255, 60/255),
        (190/255, 60/255, 40/255),
        (220/255, 110/255, 30/255),
        (180/255, 80/255, 50/255),
        (60/255, 15/255, 50/255),
    ]
    private var colorLUT: [(Float, Float, Float)] = []

    /// Latest rendered frame (low resolution, upscale when drawing).
    private(set) var image: CGImage?

    // Reusable buffers so we don't allocate per frame.
    private var pixelData = [UInt8](repeating: 0, count: 0)
    private var arg = [Float](repeating: 0, count: 0)
    private var sinOut = [Float](repeating: 0, count: 0)
    private var value = [Float](repeating: 0, count: 0)
    private var fwaves: [(fx: Float, fy: Float, ph: Float, ax: Float)] = []
    private var bufferSize = (lw: 0, lh: 0)

    init() {
        for _ in 0..<5 {
            waves.append(Wave(
                fx: CGFloat.random(in: 0.01...0.04),
                fy: CGFloat.random(in: 0.01...0.04),
                ph: CGFloat.random(in: 0...CGFloat(2 * Double.pi)),
                sp: CGFloat.random(in: 0.15...0.45),
                ax: CGFloat.random(in: 0.5...1.0)
            ))
        }

        setHueShift(CGFloat(UserDefaults.standard.double(forKey: "hueShift")))
        fwaves = waves.map { (Float($0.fx), Float($0.fy), Float($0.ph), Float($0.ax)) }
    }

    /// Rotate the whole palette through the color wheel (0 = original) and
    /// rebuild the 256-entry lookup table. Called from the settings slider.
    func setHueShift(_ degrees: CGFloat) {
        let shift = degrees / 360.0
        var rgb: [(Float, Float, Float)] = []
        for (r, g, b) in baseColors {
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            NSColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
                .getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            var nh = (h + shift).truncatingRemainder(dividingBy: 1)
            if nh < 0 { nh += 1 }
            let c = NSColor(hue: nh, saturation: s, brightness: v, alpha: 1)
                .usingColorSpace(.deviceRGB) ?? NSColor.black
            rgb.append((Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent)))
        }

        colorLUT.removeAll(keepingCapacity: true)
        let nColors = rgb.count
        for i in 0..<256 {
            let seg = Float(i) / 255.0 * Float(nColors - 1)
            let i0 = Int(seg)
            let f = seg - Float(i0)
            let ca = rgb[max(0, min(nColors - 1, i0))]
            let cb = rgb[max(0, min(nColors - 1, i0 + 1))]
            colorLUT.append((
                ca.0 + (cb.0 - ca.0) * f,
                ca.1 + (cb.1 - ca.1) * f,
                ca.2 + (cb.2 - ca.2) * f
            ))
        }
    }

    /// Advance wave phases and render the shared frame, sized for the largest screen.
    func tick(dt: TimeInterval, maxScreenSize: NSSize, speed: CGFloat) {
        for i in waves.indices {
            waves[i].ph += waves[i].sp * speed * dt
            fwaves[i].ph = Float(waves[i].ph)
        }
        let scale: Int = 16
        let lw = max(10, Int(maxScreenSize.width) / scale)
        let lh = max(10, Int(maxScreenSize.height) / scale)
        image = renderImage(width: lw, height: lh)
    }

    /// Render the aurora field into a CGImage at the given pixel size.
    /// Uses Accelerate (vvsinf) to vectorize the per-row sin computation.
    func renderImage(width lw: Int, height lh: Int) -> CGImage? {
        if lw != bufferSize.lw || lh != bufferSize.lh {
            pixelData = [UInt8](repeating: 0, count: lw * lh * 4)
            arg = [Float](repeating: 0, count: lw)
            sinOut = [Float](repeating: 0, count: lw)
            value = [Float](repeating: 0, count: lw)
            bufferSize = (lw, lh)
        }

        var count = Int32(lw)
        let invN = 1.0 / Float(waves.count)

        for y in 0..<lh {
            let yf = Float(y)
            // First wave initializes the accumulator.
            for x in 0..<lw {
                arg[x] = Float(x) * fwaves[0].fx + yf * fwaves[0].fy + fwaves[0].ph
            }
            vvsinf(&sinOut, arg, &count)
            for x in 0..<lw {
                value[x] = sinOut[x] * fwaves[0].ax
            }
            // Remaining waves add in.
            for w in 1..<fwaves.count {
                for x in 0..<lw {
                    arg[x] = Float(x) * fwaves[w].fx + yf * fwaves[w].fy + fwaves[w].ph
                }
                vvsinf(&sinOut, arg, &count)
                for x in 0..<lw {
                    value[x] += sinOut[x] * fwaves[w].ax
                }
            }
            // Map to color LUT and write the row.
            let brightness = Float(max(0.05, UserDefaults.standard.double(forKey: "brightness")))
            let rowBase = y * lw * 4
            for x in 0..<lw {
                let v = (value[x] * invN + 1) * 0.5
                let clamped = min(255, max(0, Int(v * 255)))
                let (r, g, b) = colorLUT[clamped]
                let idx = rowBase + x * 4
                pixelData[idx] = UInt8(min(1, r * brightness) * 255)
                pixelData[idx + 1] = UInt8(min(1, g * brightness) * 255)
                pixelData[idx + 2] = UInt8(min(1, b * brightness) * 255)
                pixelData[idx + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(pixelData) as CFData)!
        return CGImage(
            width: lw, height: lh,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: lw * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

// ---------------------------------------------------------------------------
// AuroraView: aurora via layer contents (GPU upscales), messages as layers
// ---------------------------------------------------------------------------

class AuroraView: NSView {

    private let renderer: AuroraRenderer
    private let screen: NSScreen
    private var messages: [Message] = []
    private var nextMsgTime: TimeInterval = 0
    private var nextMessageID = 0
    private var messageLayers: [Int: (bar: CALayer, text: CATextLayer)] = [:]
    private let maxMessages = 2

    // Vision board image state (max 1 image at a time).
    private var imageFiles: [URL] = []
    private var lastImageURL: URL?
    private var imageLayer: CALayer?
    private var imageAlpha: CGFloat = 0
    private var imagePhase = ""
    private var imagePhaseStart: TimeInterval = 0
    private var nextImageTime: TimeInterval = 0

    struct Message {
        let id: Int
        let text: String
        var x: CGFloat
        var y: CGFloat
        var size: CGSize
        var bbox: CGRect
        var alpha: CGFloat
        var phase: String
        var phaseStart: TimeInterval
        var done: Bool
    }

    init(frame frameRect: NSRect, renderer: AuroraRenderer, screen: NSScreen) {
        self.renderer = renderer
        self.screen = screen
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .linear
        nextMsgTime = Date().timeIntervalSince1970 + 2.0
        nextImageTime = Date().timeIntervalSince1970 + 5.0
        reloadImageFiles()
    }

    /// Scan the image folder (from settings) recursively for supported files.
    /// Subfolders listed in the "excludedFolders" preference are skipped.
    func reloadImageFiles() {
        let exts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]
        let path = UserDefaults.standard.string(forKey: "imageFolder") ?? ""
        let excluded = (UserDefaults.standard.stringArray(forKey: "excludedFolders") ?? [])
            .map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            imageFiles = []
            return
        }
        imageFiles = enumerator.compactMap { $0 as? URL }
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .filter { url in
                let p = url.path.hasSuffix("/") ? url.path : url.path + "/"
                return !excluded.contains { p.hasPrefix($0) }
            }
    }

    /// Visible placement area for this screen, in LOCAL view coordinates
    /// (menubar + dock already excluded via visibleFrame, shifted to origin).
    private var placementArea: CGRect {
        let v = screen.visibleFrame
        let o = screen.frame.origin
        return CGRect(x: v.minX - o.x, y: v.minY - o.y, width: v.width, height: v.height)
    }

    /// Bounds of on-screen windows (layer 0 = normal app windows) that would
    /// hide our affirmations/images, in GLOBAL screen coordinates.
    /// Our own aurora windows use desktop-level (layer != 0) so they're skipped
    /// automatically. The settings window is layer 0 → counted as occupied.
    /// No Screen-Recording permission needed: geometry only (owner name would
    /// be redacted without entitlement, but we don't use it).
    private func occupiedRects() -> [CGRect] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var rects: [CGRect] = []
        for w in info {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let alpha = (w[kCGWindowAlpha as String] as? Double) ?? (w[kCGWindowAlpha as String] as? Int).map(Double.init), alpha > 0.5 else { continue }
            guard let bounds = w[kCGWindowBounds as String] as? [String: Any] else { continue }
            guard let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double else { continue }
            // Ignore tiny windows (tool-tips, etc.).
            guard width >= 40, height >= 40 else { continue }
            // CGWindowBounds is Quartz (origin top-left of the main display).
            // Placement uses Cocoa (origin bottom-left). Convert before comparing.
            rects.append(quartzRectToCocoa(CGRect(x: x, y: y, width: width, height: height)))
        }
        return rects
    }

    /// Quartz window bounds → Cocoa screen coordinates.
    private func quartzRectToCocoa(_ quartz: CGRect) -> CGRect {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(
            x: quartz.origin.x,
            y: mainHeight - quartz.origin.y - quartz.size.height,
            width: quartz.size.width,
            height: quartz.size.height
        )
    }

    /// True if a local candidate rect intersects an occupied window on this
    /// screen. Candidate is converted to global screen coordinates first.
    private func candidateOverlapsWindow(_ candidate: CGRect, occupied: [CGRect]) -> Bool {
        let pad: CGFloat = 20
        let globalCandidate = candidate.offsetBy(dx: screen.frame.origin.x, dy: screen.frame.origin.y)
        let grown = globalCandidate.insetBy(dx: -pad, dy: -pad)
        return occupied.contains { $0.intersects(grown) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Update message lifecycle + hand the new frame to Core Animation.
    /// No drawRect — the GPU does the upscaling and compositing, so the
    /// per-frame CPU cost stays tiny.
    func update(now: TimeInterval) {
        for i in messages.indices {
            updateMessage(&messages[i], now)
        }
        messages.removeAll { $0.done }

        if now >= nextMsgTime && messages.count < maxMessages {
            let interval = UserDefaults.standard.double(forKey: "messageInterval")
            if interval > 0 {
                trySpawnMessage(now)
                nextMsgTime = now + interval * Double.random(in: 0.7...1.4)
            } else {
                // Disabled (0) — check again soon in case it gets enabled.
                nextMsgTime = now + 5
            }
        }

        updateImage(now)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = renderer.image
        syncMessageLayers()
        imageLayer?.opacity = Float(imageAlpha)
        CATransaction.commit()
    }

    /// Spawn + lifecycle for the vision board image (max 1 at a time).
    private func updateImage(_ now: TimeInterval) {
        if imageLayer == nil {
            imageAlpha = 0
            if now >= nextImageTime {
                let interval = UserDefaults.standard.double(forKey: "imageInterval")
                if interval > 0 {
                    trySpawnImage(now)
                    nextImageTime = now + interval * Double.random(in: 0.7...1.4)
                } else {
                    // Disabled (0) — check again soon in case it gets enabled.
                    nextImageTime = now + 5
                }
            }
            return
        }

        switch imagePhase {
        case "fadein":
            imageAlpha = min(1.0, CGFloat((now - imagePhaseStart) / 2.0))
            if imageAlpha >= 1.0 {
                imagePhase = "dwell"
                imagePhaseStart = now
            }
        case "dwell":
            if now - imagePhaseStart >= 12.0 {
                imagePhase = "fadeout"
                imagePhaseStart = now
            }
        case "fadeout":
            imageAlpha = max(0.0, 1.0 - CGFloat((now - imagePhaseStart) / 3.0))
            if imageAlpha <= 0.0 {
                imageLayer?.removeFromSuperlayer()
                imageLayer = nil
            }
        default:
            break
        }
    }

    private func trySpawnImage(_ now: TimeInterval) {
        // Never show the same image twice in a row.
        var candidates = imageFiles
        if candidates.count > 1, let last = lastImageURL {
            candidates = candidates.filter { $0 != last }
        }
        guard let url = candidates.randomElement(),
              let nsImage = NSImage(contentsOf: url) else { return }
        lastImageURL = url
        var rect = CGRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }

        // Scale to at most 25% of the screen, keeping aspect ratio.
        let maxW = bounds.width * 0.25
        let maxH = bounds.height * 0.25
        let scale = min(maxW / rect.width, maxH / rect.height)
        let w = rect.width * scale
        let h = rect.height * scale

        let area = placementArea
        let occupied = occupiedRects()

        // Random position that doesn't overlap active affirmation messages
        // or on-screen windows.
        var frame = CGRect.zero
        for _ in 0..<25 {
            let x = CGFloat.random(in: area.minX...max(area.minX, area.maxX - w - 20))
            let y = CGFloat.random(in: area.minY...max(area.minY, area.maxY - h - 20))
            let candidate = CGRect(x: x, y: y, width: w, height: h)
            let overlapsMsg = messages.contains { existing in
                let pad: CGFloat = 30
                return candidate.insetBy(dx: -pad, dy: -pad).intersects(existing.bbox.insetBy(dx: -pad, dy: -pad))
            }
            frame = candidate
            if overlapsMsg { continue }
            if candidateOverlapsWindow(candidate, occupied: occupied) { continue }
            break
        }

        let imgLayer = CALayer()
        imgLayer.frame = frame
        imgLayer.contents = cgImage
        imgLayer.contentsGravity = .resizeAspect
        imgLayer.cornerRadius = 8
        imgLayer.masksToBounds = true
        imgLayer.opacity = 0
        layer?.addSublayer(imgLayer)

        imageLayer = imgLayer
        imageAlpha = 0
        imagePhase = "fadein"
        imagePhaseStart = now
    }

    private func syncMessageLayers() {
        let alive = Set(messages.map { $0.id })
        for (id, pair) in messageLayers where !alive.contains(id) {
            pair.bar.removeFromSuperlayer()
            pair.text.removeFromSuperlayer()
            messageLayers.removeValue(forKey: id)
        }

        guard let root = layer else { return }
        let scale = window?.backingScaleFactor ?? 2

        for m in messages {
            if messageLayers[m.id] == nil {
                let bar = CALayer()
                bar.frame = m.bbox
                bar.cornerRadius = 10
                bar.backgroundColor = NSColor(srgbRed: 0.04, green: 0.02, blue: 0.08, alpha: 1).cgColor

                let text = CATextLayer()
                text.string = NSAttributedString(string: m.text, attributes: [
                    .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                    .foregroundColor: NSColor.white,
                ])
                text.frame = CGRect(x: m.x, y: m.y, width: m.size.width + 4, height: m.size.height + 4)
                text.contentsScale = scale
                text.isWrapped = false

                root.addSublayer(bar)
                root.addSublayer(text)
                messageLayers[m.id] = (bar, text)
            }
            let pair = messageLayers[m.id]!
            pair.bar.opacity = Float(m.alpha * 0.78)
            pair.text.opacity = Float(m.alpha)
        }
    }

    private func trySpawnMessage(_ now: TimeInterval) {
        // Read fresh every spawn so settings edits apply without a restart.
        let affirmations = UserDefaults.standard.stringArray(forKey: "affirmations") ?? []
        guard let text = affirmations.randomElement() else { return }
        let font = NSFont.systemFont(ofSize: 18, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let area = placementArea
        let occupied = occupiedRects()

        for _ in 0..<25 {
            let x = CGFloat.random(in: area.minX...max(area.minX, area.maxX - textSize.width - 40))
            let y = CGFloat.random(in: area.minY...max(area.minY, area.maxY - textSize.height - 40))
            let bbox = CGRect(x: x - 16, y: y - 8, width: textSize.width + 32, height: textSize.height + 16)

            let overlapsMsg = messages.contains { existing in
                let pad: CGFloat = 30
                return bbox.insetBy(dx: -pad, dy: -pad).intersects(existing.bbox.insetBy(dx: -pad, dy: -pad))
            }
            if overlapsMsg { continue }
            if candidateOverlapsWindow(bbox, occupied: occupied) { continue }

            nextMessageID += 1
            messages.append(Message(
                id: nextMessageID, text: text, x: x, y: y, size: textSize, bbox: bbox,
                alpha: 0, phase: "fadein", phaseStart: now, done: false
            ))
            return
        }
    }

    private func updateMessage(_ m: inout Message, _ t: TimeInterval) {
        switch m.phase {
        case "fadein":
            m.alpha = min(1.0, CGFloat((t - m.phaseStart) / 2.0))
            if m.alpha >= 1.0 {
                m.phase = "dwell"
                m.phaseStart = t
            }
        case "dwell":
            if t - m.phaseStart >= 12.0 {
                m.phase = "fadeout"
                m.phaseStart = t
            }
        case "fadeout":
            m.alpha = max(0.0, 1.0 - CGFloat((t - m.phaseStart) / 3.0))
            if m.alpha <= 0.0 {
                m.done = true
            }
        default:
            break
        }
    }
}

// ---------------------------------------------------------------------------
// AppDelegate: one desktop window per screen + wallpaper sync
// ---------------------------------------------------------------------------

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, SettingsHost {
    private let renderer = AuroraRenderer()
    private var windows: [NSWindow] = []
    private var views: [AuroraView] = []
    private var timer: Timer?
    private var lastFrame: TimeInterval = 0
    /// Original wallpaper per screen name, restored on quit.
    private var oldWallpapers: [String: URL] = [:]
    private var wallpaperRetries = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "auroraSpeed": 1.0,
            "frameRate": 30.0,
            "messageInterval": 9.0,
            "imageInterval": 20.0,
            "imageFolder": "",
            "brightness": 1.0,
            "hueShift": 0.0,
            "affirmations": defaultAffirmations,
            "excludedFolders": [String](),
        ])

        NSApp.setActivationPolicy(.regular)
        if let icon = NSImage(named: "AppIconRounded") {
            NSApp.applicationIconImage = icon
        }
        clearStaleWallpapers()
        setupMenu()
        createWindows()
        syncWallpaper()
        startTimer()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // The wallpaper API only applies to the currently active space per
        // screen — re-sync whenever the user switches spaces.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                NSApp.terminate(nil)
            }
            return event
        }

        // Ensure graceful quit (wallpaper restore) on `killall` / SIGTERM.
        signal(SIGTERM) { _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @objc private func screensChanged() {
        createWindows()
        syncWallpaper()
    }

    // -----------------------------------------------------------------------
    // Menu + settings window
    // -----------------------------------------------------------------------

    private var settingsWindow: NSWindow?
    private var settingsStore: SettingsStore?

    private func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "AffirmationWallpaper beenden", action: #selector(quitApp), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let store = SettingsStore(host: self)
        settingsStore = store
        let window = SettingsWindowFactory.makeWindow(store: store, renderer: renderer)
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func settingsDidChange(_ key: String) {
        if key == "frameRate" {
            timer?.invalidate()
            startTimer()
        }
        if key == "hueShift" {
            renderer.setHueShift(CGFloat(UserDefaults.standard.double(forKey: "hueShift")))
        }
        if key == "brightness" || key == "hueShift" {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(syncWallpaperDebounced), object: nil)
            perform(#selector(syncWallpaperDebounced), with: nil, afterDelay: 0.5)
        }
    }

    func settingsDidChangeImageSources() {
        for view in views {
            view.reloadImageFiles()
        }
    }

    @objc private func syncWallpaperDebounced() {
        syncWallpaper()
    }

    @objc private func spaceChanged() {
        syncWallpaper()
    }

    private func createWindows() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        views.removeAll()

        for screen in NSScreen.screens {
            let frame = screen.frame

            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = NSColor.black
            window.hasShadow = false

            let view = AuroraView(
                frame: NSRect(origin: .zero, size: frame.size),
                renderer: renderer,
                screen: screen
            )
            window.contentView = view
            window.orderFrontRegardless()

            windows.append(window)
            views.append(view)
        }
    }

    private func startTimer() {
        lastFrame = Date().timeIntervalSince1970
        // ~30 fps default (adjustable in settings): the aurora frame is cheap,
        // the GPU does the upscaling — smooth animation, low CPU.
        let fps = max(5, UserDefaults.standard.double(forKey: "frameRate"))
        timer = Timer.scheduledTimer(timeInterval: 1.0 / fps, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }

    @objc private func tick() {
        let now = Date().timeIntervalSince1970
        let dt = min(now - lastFrame, 0.1)
        lastFrame = now

        var maxSize = NSSize.zero
        for screen in NSScreen.screens {
            maxSize.width = max(maxSize.width, screen.frame.width)
            maxSize.height = max(maxSize.height, screen.frame.height)
        }

        let speed = CGFloat(max(0.05, UserDefaults.standard.double(forKey: "auroraSpeed")))
        renderer.tick(dt: dt, maxScreenSize: maxSize, speed: speed)
        for view in views {
            view.update(now: now)
        }
    }

    // -----------------------------------------------------------------------
    // Wallpaper sync: set a still aurora frame as the real desktop picture,
    // so Mission Control previews and the lock screen show the aurora too.
    // -----------------------------------------------------------------------

    private func syncWallpaper() {
        wallpaperRetries = 0
        applyWallpapers()
    }

    /// Deletes leftover aurora stills from previous sessions (crash leftovers).
    /// Filenames contain a random per-launch hash, so they'd never be
    /// overwritten and would slowly accumulate.
    private func clearStaleWallpapers() {
        for dir in [Self.wallpaperDirectory, Self.legacyWallpaperDirectory] {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in files where file.hasPrefix("wallpaper-") {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }

    private func applyWallpapers() {
        for screen in NSScreen.screens {
            let key = screen.localizedName
            let defaultsKey = "originalWallpaper-\(key)"
            if oldWallpapers[key] == nil {
                // Never capture one of our own aurora stills as "original"
                // (can happen after an unclean quit) — that would poison the restore.
                if let current = NSWorkspace.shared.desktopImageURL(for: screen),
                   !current.path.contains("/Meanwhile/wallpaper-"),
                   !current.path.contains("/AffirmationWallpaper/wallpaper-") {
                    oldWallpapers[key] = current
                    // Persist so the original survives a crash (memory-only
                    // storage would lose it and restore would fall back to
                    // the generic default wallpaper).
                    UserDefaults.standard.set(current.path, forKey: defaultsKey)
                } else if let saved = UserDefaults.standard.string(forKey: defaultsKey) {
                    oldWallpapers[key] = URL(fileURLWithPath: saved)
                }
            }

            // Quarter resolution is plenty for a smooth gradient field.
            let scale = screen.backingScaleFactor
            let w = max(10, Int(screen.frame.width * scale) / 4)
            let h = max(10, Int(screen.frame.height * scale) / 4)

            guard let image = renderer.renderImage(width: w, height: h),
                  let url = savePNG(image, name: "wallpaper-\(key.hashValue)") else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                NSLog("AffirmationWallpaper: wallpaper sync failed for %@: %@", key, error.localizedDescription)
            }
        }

        // WallpaperAgent sometimes silently drops a screen — verify and retry.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.verifyWallpapers()
        }
    }

    private func verifyWallpapers() {
        guard wallpaperRetries < 3 else { return }
        wallpaperRetries += 1

        var missing = false
        for screen in NSScreen.screens {
            let key = screen.localizedName
            let expected = "wallpaper-\(key.hashValue).png"
            if NSWorkspace.shared.desktopImageURL(for: screen)?.lastPathComponent != expected {
                NSLog("AffirmationWallpaper: wallpaper did not stick for %@, retry %d", key, wallpaperRetries)
                missing = true
            }
        }
        if missing {
            applyWallpapers()
        }
    }

    private func savePNG(_ image: CGImage, name: String) -> URL? {
        let dir = Self.wallpaperDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name + ".png")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try? data.write(to: url)
        return url
    }

    private static var wallpaperDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AffirmationWallpaper")
    }

    private static var legacyWallpaperDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Meanwhile")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        timer?.invalidate()
        timer = nil

        // Hide the aurora windows immediately so the desktop is visible again.
        for window in windows {
            window.orderOut(nil)
        }

        // Restore the original wallpaper on every screen. The system applies
        // wallpaper changes asynchronously and sometimes drops a request
        // (mostly on external displays), so we set it twice with a pause.
        // We spin the run loop ourselves so async XPC replies get processed —
        // blocking it (usleep) makes the system drop the requests.
        restoreWallpapers()
        spinRunLoop(0.5)
        restoreWallpapers()
        spinRunLoop(0.7)

        // Delete our aurora stills: spaces that were synced but could not be
        // restored then fall back to the system default instead of keeping a
        // stale aurora frame.
        try? FileManager.default.removeItem(at: Self.wallpaperDirectory)
        try? FileManager.default.removeItem(at: Self.legacyWallpaperDirectory)
        return .terminateNow
    }

    /// Lets the main run loop process events/XPC for the given duration.
    private func spinRunLoop(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }

    private func restoreWallpapers() {
        let fallback = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
        for screen in NSScreen.screens {
            let target = oldWallpapers[screen.localizedName] ?? fallback
            do {
                try NSWorkspace.shared.setDesktopImageURL(target, for: screen, options: [:])
            } catch {
                NSLog("AffirmationWallpaper: wallpaper restore failed for %@: %@", screen.localizedName, error.localizedDescription)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()