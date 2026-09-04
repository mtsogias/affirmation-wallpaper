import SwiftUI
import AppKit

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
    @Published var lastDeleted: (index: Int, row: AffRow)?

    init(host: SettingsHost) {
        self.host = host
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

    func set(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: key)
        host?.settingsDidChange(key)
    }

    func persistAffirmations() {
        UserDefaults.standard.set(rows.map(\.text), forKey: "affirmations")
    }

    func addDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        rows.append(AffRow(text: text))
        draft = ""
        lastDeleted = nil
        persistAffirmations()
    }

    func remove(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        lastDeleted = (index, rows[index])
        rows.remove(at: index)
        persistAffirmations()
    }

    func undoDelete() {
        guard let deleted = lastDeleted else { return }
        let index = min(deleted.index, rows.count)
        rows.insert(deleted.row, at: index)
        lastDeleted = nil
        persistAffirmations()
    }

    func pickImageFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !imageFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: imageFolder)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        imageFolder = url.path
        UserDefaults.standard.set(url.path, forKey: "imageFolder")
        host?.settingsDidChangeImageSources()
    }

    func addExcludedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ausschließen"
        let base = imageFolder.isEmpty ? NSHomeDirectory() : imageFolder
        panel.directoryURL = URL(fileURLWithPath: base)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard !excludedFolders.contains(path) else { return }
        excludedFolders.append(path)
        UserDefaults.standard.set(excludedFolders, forKey: "excludedFolders")
        host?.settingsDidChangeImageSources()
    }

    func removeExcluded(_ path: String) {
        excludedFolders.removeAll { $0 == path }
        UserDefaults.standard.set(excludedFolders, forKey: "excludedFolders")
        host?.settingsDidChangeImageSources()
    }

    var folderName: String {
        let name = URL(fileURLWithPath: imageFolder).lastPathComponent
        return name.isEmpty ? "Kein Ordner" : name
    }
}

@MainActor
enum SettingsWindowFactory {
    static func makeWindow(store: SettingsStore, renderer: AuroraRenderer) -> NSWindow {
        let root = SettingsRootView(store: store, renderer: renderer)
        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 540, height: 640)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Einstellungen"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private enum Tab: String, CaseIterable, Identifiable {
    case appearance = "Darstellung"
    case affirmations = "Affirmationen"
    case images = "Bilder"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .affirmations: return "quote.opening"
        case .images: return "photo"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var store: SettingsStore
    let renderer: AuroraRenderer
    @State private var tab: Tab = .appearance

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Divider().opacity(0.5)

            Group {
                switch tab {
                case .appearance: AppearanceTab(store: store, renderer: renderer)
                case .affirmations: AffirmationsTab(store: store)
                case .images: ImagesTab(store: store)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 540, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = item }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: tab == item ? .semibold : .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule(style: .continuous)
                            .fill(tab == item ? Color.primary.opacity(0.08) : Color.clear)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                tab == item ? Color.primary.opacity(0.10) : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct AppearanceTab: View {
    @ObservedObject var store: SettingsStore
    let renderer: AuroraRenderer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { _ in
                AuroraPreview(renderer: renderer)
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }

            SettingsCard {
                VStack(spacing: 16) {
                    SettingSlider(
                        title: "Helligkeit",
                        value: $store.brightness,
                        range: 0.2...2.0,
                        display: String(format: "%.1f", store.brightness)
                    ) { store.set("brightness", $0) }

                    VStack(alignment: .leading, spacing: 8) {
                        SettingSlider(
                            title: "Farbton",
                            value: $store.hueShift,
                            range: 0...360,
                            display: "\(Int(store.hueShift))°"
                        ) { store.set("hueShift", $0) }

                        LinearGradient(
                            colors: (0..<12).map {
                                Color(hue: Double($0) / 12.0, saturation: 0.55, brightness: 0.72)
                            },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 6)
                        .clipShape(Capsule())
                    }

                    SettingSlider(
                        title: "Aurora-Geschwindigkeit",
                        value: $store.auroraSpeed,
                        range: 0.2...2.0,
                        display: String(format: "%.1f", store.auroraSpeed)
                    ) { store.set("auroraSpeed", $0) }

                    SettingSlider(
                        title: "Bildrate",
                        value: $store.frameRate,
                        range: 10...30,
                        display: "\(Int(store.frameRate)) FPS"
                    ) { store.set("frameRate", $0) }
                }
            }
        }
    }
}

private struct AffirmationsTab: View {
    @ObservedObject var store: SettingsStore
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingSlider(
                title: "Abstand zwischen Affirmationen",
                value: $store.messageInterval,
                range: 0...60,
                display: store.messageInterval == 0 ? "aus" : "\(Int(store.messageInterval)) s"
            ) { store.set("messageInterval", $0) }

            HStack {
                Text("Deine Sätze")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.lastDeleted != nil {
                    Button("Wiederherstellen") { store.undoDelete() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(padding: 8) {
                if store.rows.isEmpty {
                    Text("Noch keine Affirmationen. Schreib unten eine und drück Return.")
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
                                    TextField("Affirmation", text: $row.text)
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
                    .frame(maxHeight: 320)
                }
            }

            HStack(spacing: 8) {
                TextField("Neue Affirmation …", text: $store.draft)
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
                    .focused($draftFocused)
                    .onSubmit { store.addDraft() }

                Button("Hinzufügen") { store.addDraft() }
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
                title: "Abstand zwischen Bildern",
                value: $store.imageInterval,
                range: 0...60,
                display: store.imageInterval == 0 ? "aus" : "\(Int(store.imageInterval)) s"
            ) { store.set("imageInterval", $0) }

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
                        Text(store.imageFolder.isEmpty ? "Kein Bilderordner" : store.folderName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(store.imageFolder.isEmpty
                             ? "Wähle einen Ordner mit Bildern fürs Vision Board."
                             : store.imageFolder)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button("Ändern") { store.pickImageFolder() }
                        .buttonStyle(QuietButtonStyle())
                }
            }

            HStack {
                Text("Unterordner auslassen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Ordner …") { store.addExcludedFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .disabled(store.imageFolder.isEmpty)
            }

            SettingsCard(padding: 8) {
                if store.excludedFolders.isEmpty {
                    Text("Keine. Nützlich, wenn in einem Unterordner z. B. ein Archiv liegt.")
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
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String
    var onChange: (Double) -> Void

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
            Slider(value: $value, in: range)
                .onChange(of: value) { _, v in onChange(v) }
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

private struct AuroraPreview: NSViewRepresentable {
    let renderer: AuroraRenderer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resize
        view.layer?.magnificationFilter = .linear
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.contents = renderer.image
    }
}
