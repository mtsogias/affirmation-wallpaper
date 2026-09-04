import SwiftUI
import AppKit
import ServiceManagement

@MainActor
protocol SettingsHost: AnyObject {
    func settingsDidChange(_ key: String)
    func settingsDidChangeImageSources()
}

struct AffRow: Identifiable, Equatable {
    let id: UUID
    var text: String
    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    weak var host: SettingsHost?
    weak var undoManager: UndoManager?

    @Published var language: AppLanguage
    @Published var brightness: Double
    @Published var hueShift: Double
    @Published var auroraSpeed: Double
    @Published var frameRate: Double
    @Published var messageInterval: Double
    @Published var imageInterval: Double
    @Published var imageFolder: String
    @Published var excludedFolders: [String]
    @Published var rows: [AffRow]
    @Published var draft: String = ""

    private var gestureStart: [String: Double] = [:]

    init(host: SettingsHost) {
        self.host = host
        language = .resolved
        let d = UserDefaults.standard
        brightness = d.object(forKey: "brightness") as? Double ?? 1.0
        hueShift = d.object(forKey: "hueShift") as? Double ?? 0
        auroraSpeed = d.object(forKey: "auroraSpeed") as? Double ?? 1.0
        frameRate = d.object(forKey: "frameRate") as? Double ?? 30
        messageInterval = d.object(forKey: "messageInterval") as? Double ?? 9
        imageInterval = d.object(forKey: "imageInterval") as? Double ?? 20
        imageFolder = d.string(forKey: "imageFolder") ?? ""
        excludedFolders = d.stringArray(forKey: "excludedFolders") ?? []
        let texts = d.stringArray(forKey: "affirmations") ?? defaultAffirmations
        rows = texts.map { AffRow(text: $0) }
    }

    func t(_ key: String) -> String { Loc.t(key, language) }

    func setLanguage(_ lang: AppLanguage) {
        guard lang != language else { return }
        language = lang
        UserDefaults.standard.set(lang.rawValue, forKey: "language")
        host?.settingsDidChange("language")
    }

    func beginGesture(_ key: String) {
        gestureStart[key] = sliderValue(key)
    }

    func endGesture(_ key: String) {
        guard let old = gestureStart.removeValue(forKey: key) else { return }
        let new = sliderValue(key)
        guard abs(old - new) > 0.0008 else { return }
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restoreSlider(key, old) }
        }
        undoManager?.setActionName(t("undoSlider"))
    }

    func setLive(_ key: String, _ value: Double) {
        assignSlider(key, value)
        UserDefaults.standard.set(value, forKey: key)
        host?.settingsDidChange(key)
    }

    private func restoreSlider(_ key: String, _ value: Double) {
        let current = sliderValue(key)
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restoreSlider(key, current) }
        }
        undoManager?.setActionName(t("undoSlider"))
        setLive(key, value)
    }

    private func sliderValue(_ key: String) -> Double {
        switch key {
        case "brightness": return brightness
        case "hueShift": return hueShift
        case "auroraSpeed": return auroraSpeed
        case "frameRate": return frameRate
        case "messageInterval": return messageInterval
        case "imageInterval": return imageInterval
        default: return 0
        }
    }

    private func assignSlider(_ key: String, _ value: Double) {
        switch key {
        case "brightness": brightness = value
        case "hueShift": hueShift = value
        case "auroraSpeed": auroraSpeed = value
        case "frameRate": frameRate = value
        case "messageInterval": messageInterval = value
        case "imageInterval": imageInterval = value
        default: break
        }
    }

    func persistAffirmations() {
        UserDefaults.standard.set(rows.map(\.text), forKey: "affirmations")
    }

    func addDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let row = AffRow(text: text)
        rows.append(row)
        draft = ""
        persistAffirmations()
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.remove(row.id, registerUndo: true) }
        }
        undoManager?.setActionName(t("undoAffirmation"))
    }

    func remove(_ id: UUID, registerUndo: Bool = true) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let row = rows[index]
        rows.remove(at: index)
        persistAffirmations()
        guard registerUndo else { return }
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let i = min(index, store.rows.count)
                store.rows.insert(row, at: i)
                store.persistAffirmations()
            }
        }
        undoManager?.setActionName(t("undoAffirmation"))
    }

    func pickImageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = t("pickFolderMessage")
        panel.prompt = t("choose")
        if !imageFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: imageFolder)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let old = imageFolder
        let new = url.path
        guard old != new else { return }
        applyFolder(new)
        undoManager?.setActionName(t("undoFolder"))
    }

    private func applyFolder(_ path: String) {
        let current = imageFolder
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.applyFolder(current) }
        }
        imageFolder = path
        UserDefaults.standard.set(path, forKey: "imageFolder")
        host?.settingsDidChangeImageSources()
    }

    func addExcludedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = t("excludeFolderMessage")
        panel.prompt = t("ignore")
        let base = imageFolder.isEmpty ? NSHomeDirectory() : imageFolder
        panel.directoryURL = URL(fileURLWithPath: base)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard !excludedFolders.contains(path) else { return }
        let old = excludedFolders
        excludedFolders.append(path)
        UserDefaults.standard.set(excludedFolders, forKey: "excludedFolders")
        host?.settingsDidChangeImageSources()
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.applyExcluded(old) }
        }
        undoManager?.setActionName(t("undoExclude"))
    }

    func removeExcluded(_ path: String) {
        let old = excludedFolders
        excludedFolders.removeAll { $0 == path }
        UserDefaults.standard.set(excludedFolders, forKey: "excludedFolders")
        host?.settingsDidChangeImageSources()
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.applyExcluded(old) }
        }
        undoManager?.setActionName(t("undoExclude"))
    }

    private func applyExcluded(_ folders: [String]) {
        let current = excludedFolders
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.applyExcluded(current) }
        }
        excludedFolders = folders
        UserDefaults.standard.set(folders, forKey: "excludedFolders")
        host?.settingsDidChangeImageSources()
    }

    var folderName: String {
        URL(fileURLWithPath: imageFolder).lastPathComponent
    }

    var opensAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("AffirmationWallpaper: login item failed: %@", error.localizedDescription)
        }
        objectWillChange.send()
    }
}

@MainActor
enum SettingsWindowFactory {
    static func makeWindow(store: SettingsStore, renderer: AuroraRenderer) -> NSWindow {
        let root = SettingsRootView(store: store, renderer: renderer)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = store.t("settings")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 660))
        window.contentMinSize = NSSize(width: 500, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        store.undoManager = window.undoManager
        return window
    }
}

private enum Tab: String, CaseIterable, Identifiable {
    case appearance, affirmations, images, general
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .affirmations: return "quote.opening"
        case .images: return "photo"
        case .general: return "gearshape"
        }
    }
    var titleKey: String {
        switch self {
        case .general: return "tabGeneral"
        case .appearance: return "tabAppearance"
        case .affirmations: return "tabAffirmations"
        case .images: return "tabImages"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var store: SettingsStore
    let renderer: AuroraRenderer
    @State private var tab: Tab = .appearance
    @Environment(\.undoManager) private var envUndo

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().opacity(0.5)

            Group {
                switch tab {
                case .general: GeneralTab(store: store)
                case .appearance: AppearanceTab(store: store, renderer: renderer)
                case .affirmations: AffirmationsTab(store: store)
                case .images: ImagesTab(store: store)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 500, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if let envUndo { store.undoManager = envUndo } }
        .onChange(of: envUndo) { _, new in if let new { store.undoManager = new } }
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases) { item in
                let selected = tab == item
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(selected ? 0.10 : 0.001))
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(selected ? 0.12 : 0), lineWidth: 1)
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(store.t(item.titleKey))
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .allowsHitTesting(false)
                    ClickSurface {
                        withAnimation(.easeInOut(duration: 0.15)) { tab = item }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
        }
        .padding(3)
        .frame(height: 38)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct GeneralTab: View {
    @ObservedObject var store: SettingsStore

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.t("openAtLogin"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            SettingsCard {
                Toggle(isOn: Binding(
                    get: { store.opensAtLogin },
                    set: { store.setOpensAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("openAtLogin"))
                            .font(.system(size: 13, weight: .medium))
                        Text(store.t("openAtLoginHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .toggleStyle(.switch)
            }

            Text(store.t("language"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            SettingsCard(padding: 8) {
                VStack(spacing: 2) {
                    ForEach(AppLanguage.allCases) { lang in
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(store.language == lang ? 0.06 : 0.001))
                            HStack {
                                Text(lang.nativeName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if store.language == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .allowsHitTesting(false)
                            ClickSurface { store.setLanguage(lang) }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                    }
                }
            }

            Text(store.t("languageHint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HStack {
                Text("AffirmationWallpaper")
                    .font(.system(size: 12, weight: .medium))
                Text(version)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppearanceTab: View {
    @ObservedObject var store: SettingsStore
    let renderer: AuroraRenderer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AuroraPreview(renderer: renderer, hue: store.hueShift, brightness: store.brightness)
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            SettingsCard {
                VStack(spacing: 16) {
                    SettingSlider(
                        title: store.t("brightness"),
                        key: "brightness",
                        store: store,
                        value: $store.brightness,
                        range: 0.2...2.0,
                        display: String(format: "%.1f", store.brightness)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        SettingSlider(
                            title: store.t("hue"),
                            key: "hueShift",
                            store: store,
                            value: $store.hueShift,
                            range: 0...360,
                            display: "\(Int(store.hueShift))°"
                        )

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                LinearGradient(
                                    colors: (0..<12).map {
                                        Color(hue: Double($0) / 12.0, saturation: 0.55, brightness: 0.72)
                                    },
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .clipShape(Capsule())
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                                    .offset(x: max(0, min(geo.size.width - 8, geo.size.width * store.hueShift / 360.0 - 4)))
                            }
                        }
                        .frame(height: 8)
                    }

                    SettingSlider(
                        title: store.t("auroraSpeed"),
                        key: "auroraSpeed",
                        store: store,
                        value: $store.auroraSpeed,
                        range: 0.2...2.0,
                        display: String(format: "%.1f", store.auroraSpeed)
                    )

                    SettingSlider(
                        title: store.t("frameRate"),
                        key: "frameRate",
                        store: store,
                        value: $store.frameRate,
                        range: 10...30,
                        display: "\(Int(store.frameRate)) \(store.t("fps"))"
                    )
                }
            }
        }
    }
}

private struct AffirmationsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingSlider(
                title: store.t("messageInterval"),
                key: "messageInterval",
                store: store,
                value: $store.messageInterval,
                range: 0...60,
                display: store.messageInterval == 0 ? store.t("off") : "\(Int(store.messageInterval)) s"
            )

            Text(store.t("yourSentences"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            SettingsCard(padding: 8) {
                if store.rows.isEmpty {
                    Text(store.t("emptyAffirmations"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach($store.rows) { $row in
                                HStack(spacing: 8) {
                                    TextField(store.t("newAffirmation"), text: $row.text)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13))
                                        .onChange(of: row.text) { _, _ in
                                            store.persistAffirmations()
                                        }
                                    Button {
                                        store.remove(row.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 22, height: 22)
                                            .background(Circle().fill(Color.primary.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 300)
                }
            }

            HStack(spacing: 8) {
                TextField(store.t("newAffirmation"), text: $store.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .onSubmit { store.addDraft() }

                Button(store.t("add")) { store.addDraft() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }
}

private struct ImagesTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingSlider(
                title: store.t("imageInterval"),
                key: "imageInterval",
                store: store,
                value: $store.imageInterval,
                range: 0...60,
                display: store.imageInterval == 0 ? store.t("off") : "\(Int(store.imageInterval)) s"
            )

            Text(store.t("visionBoard"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            SettingsCard {
                HStack(spacing: 12) {
                    Image(systemName: store.imageFolder.isEmpty ? "folder" : "folder.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.imageFolder.isEmpty ? store.t("noFolder") : store.folderName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(store.imageFolder.isEmpty ? store.t("noFolderHint") : store.imageFolder)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(store.imageFolder.isEmpty ? 3 : 1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button(store.imageFolder.isEmpty ? store.t("chooseFolder") : store.t("chooseOtherFolder")) {
                        store.pickImageFolder()
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }

            HStack {
                Text(store.t("ignoredSubfolders"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(store.t("ignoreSubfolder")) { store.addExcludedFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .disabled(store.imageFolder.isEmpty)
            }

            SettingsCard(padding: 8) {
                if store.excludedFolders.isEmpty {
                    Text(store.t("noExclusions"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.excludedFolders, id: \.self) { path in
                            HStack {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text(path)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 180, alignment: .trailing)
                                Button {
                                    store.removeExcluded(path)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.primary.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }
}

/// Transparent AppKit view that eats clicks in its whole bounds.
/// SwiftUI Button/onTapGesture on macOS often only hit-tests the glyphs.
private struct ClickSurface: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ClickView, context: Context) {
        view.action = action
    }

    final class ClickView: NSView {
        var action: () -> Void = {}

        override var isOpaque: Bool { false }
        override var mouseDownCanMoveWindow: Bool { false }
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            action()
        }
    }
}

private struct SettingsCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct SettingSlider: View {
    let title: String
    let key: String
    @ObservedObject var store: SettingsStore
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(display)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range) { editing in
                if editing { store.beginGesture(key) }
                else { store.endGesture(key) }
            }
            .onChange(of: value) { _, v in store.setLive(key, v) }
        }
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Copies the live aurora frame on a timer so hue/brightness show up immediately.
private struct AuroraPreview: NSViewRepresentable {
    let renderer: AuroraRenderer
    var hue: Double
    var brightness: Double

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resize
        view.layer?.magnificationFilter = .linear
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.renderer = renderer
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.renderer = renderer
        view.refresh()
    }

    final class PreviewView: NSView {
        weak var renderer: AuroraRenderer?
        private var timer: Timer?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            timer?.invalidate()
            timer = nil
            guard window != nil else { return }
            let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            refresh()
        }

        func refresh() {
            layer?.contents = renderer?.image
        }
    }
}
