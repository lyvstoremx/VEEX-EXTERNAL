import SwiftUI
import UIKit
import CryptoKit
import AVFoundation

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false

    init() {
        _tabNavigation = State(initialValue: AppTabNavigationState())
    }

    var body: some View {
        VexxRoot()
            .tint(AppTheme.accent)
            .imageScale(.small)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
            .patchStorePresentation(patchStore)
            .repositoryStorePresentation(repositoryStore, patchStore: patchStore)
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .new: return "tab.new"
        case .sources: return "tab.sources"
        case .installed: return "tab.installed"
        case .files: return "tab.files"
        case .search: return "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .new: return "clock.fill"
        case .sources: return "shippingbox.fill"
        case .installed: return "tray.full.fill"
        case .files: return "folder.fill"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - VEEX

enum VexxEvent: String { case on, off, error, gate }

enum VexxVoice {
    private static var player: AVAudioPlayer?
    static func play(_ event: VexxEvent) {
        if UserDefaults.standard.bool(forKey: "vexx.mute") { return }
        guard let url = Bundle.main.url(forResource: event.rawValue, withExtension: "m4a") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

enum VexxTab: String, CaseIterable, Identifiable {
    case aimbots = "Aimbots", holograms = "Hologramas", guest = "Borrar Invitado"
    var id: String { rawValue }
}

struct VexxRow: Identifiable {
    let id: String
    let title: String
    let match: String
    let tab: VexxTab
}

enum VexxCatalog {
    static let rows: [VexxRow] = [
        .init(id: "antena",  title: "Aim Drag Antena",       match: "antena",    tab: .aimbots),
        .init(id: "drag",    title: "Aim Drag",              match: "drag",      tab: .aimbots),
        .init(id: "pecho",   title: "Aim Pecho",             match: "pecho",     tab: .aimbots),
        .init(id: "balas",   title: "Balas Mágicas",         match: "balas",     tab: .aimbots),
        .init(id: "holoarm", title: "Hologramas Armas",      match: "holog",     tab: .holograms),
        .init(id: "holoper", title: "Hologramas Personajes", match: "personaje", tab: .holograms),
        .init(id: "guest",   title: "Reset Guest",           match: "guest",     tab: .guest),
    ]
}

@MainActor
final class VexxEngine: ObservableObject {
    @Published private(set) var active: Set<UUID> = []
    @Published var busyID: UUID?
    @Published var error: String?

    func refresh(_ items: [PatchLibraryItem]) {
        active = Set(items.filter { DevicePatchService.latestReceipt(projectID: $0.id) != nil }.map(\.id))
    }

    func toggle(_ item: PatchLibraryItem) {
        guard busyID == nil else { return }
        busyID = item.id
        error = nil
        let isOn = active.contains(item.id)
        Task.detached(priority: .userInitiated) {
            do {
                if isOn {
                    try Self.restoreOne(item)
                    await MainActor.run {
                        _ = self.active.remove(item.id)
                        self.busyID = nil
                        VexxVoice.play(.off)
                    }
                } else {
                    try Self.applyOne(item)
                    await MainActor.run {
                        self.active.insert(item.id)
                        self.busyID = nil
                        VexxVoice.play(.on)
                    }
                }
            } catch {
                await MainActor.run {
                    self.busyID = nil
                    self.error = "\(error)"
                    VexxVoice.play(.error)
                }
            }
        }
    }

    func restoreAll(_ items: [PatchLibraryItem]) {
        guard busyID == nil else { return }
        let targets = items.filter { active.contains($0.id) }
        guard !targets.isEmpty else { return }
        busyID = targets.first?.id
        Task.detached(priority: .userInitiated) {
            for item in targets {
                do {
                    try Self.restoreOne(item)
                    await MainActor.run { _ = self.active.remove(item.id) }
                } catch {
                    await MainActor.run { self.error = "\(error)" }
                }
            }
            await MainActor.run { self.busyID = nil }
        }
    }

    private nonisolated static func applyOne(_ item: PatchLibraryItem) throws {
        guard let base = item.project else { return }
        let project = item.summary.schemaVersion >= 2 && item.canInspectContents
            ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
            : base
        _ = try DevicePatchService.apply(project: project)
    }

    private nonisolated static func restoreOne(_ item: PatchLibraryItem) throws {
        guard let receipt = DevicePatchService.latestReceipt(projectID: item.id) else { return }
        let inspection = try DevicePatchService.inspectRestore(receipt: receipt)
        try DevicePatchService.restore(
            receipt: receipt,
            allowChangedTargets: !inspection.changedTargets.isEmpty
        )
    }
}

@MainActor
final class VexxLicense: ObservableObject {
    @Published var isValid = false
    @Published var error: String?

    static let masterKey = "VEEX-LEVI-2004"
    static let ownerID   = "REEMPLAZA"
    static let secret    = "VEEX-3105-LEVI"
    private let alpha = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private let epoch = Date(timeIntervalSince1970: 1_767_225_600)

    private func norm(_ s: String) -> String {
        s.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
    }

    static var deviceID: String {
        let u = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        return String(u.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }

    init() {
        let exp = UserDefaults.standard.double(forKey: "vexx.exp")
        isValid = exp == .infinity || (exp > 0 && Date(timeIntervalSince1970: exp) > Date())
    }

    func activate(_ raw: String) {
        let c = norm(raw)
        if c == norm(Self.masterKey) {
            if Self.ownerID == "REEMPLAZA" || Self.ownerID == Self.deviceID {
                grant(nil)
            } else { error = "Esta key es de otro dispositivo" }
            return
        }
        guard c.count == 11, c.hasPrefix("VEEX") else { error = "Formato inválido"; return }
        let body = String(c.dropFirst(4))
        let expPart = String(body.prefix(4))
        let sig = String(body.suffix(3))
        guard let exp = decodeExpiry(expPart) else { error = "Key inválida"; return }
        guard sig == sign(expiry: expPart) else { error = "Key incorrecta"; return }
        guard exp > Date() else { error = "Key vencida"; return }
        grant(exp)
    }

    private func grant(_ exp: Date?) {
        isValid = true; error = nil
        UserDefaults.standard.set(exp?.timeIntervalSince1970 ?? .infinity, forKey: "vexx.exp")
    }

    private func sign(expiry: String) -> String {
        let key = SymmetricKey(data: Data(Self.secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data((Self.deviceID + expiry).utf8), using: key)
        var n = mac.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        var out = ""
        for _ in 0..<3 { out.append(alpha[Int(n % 32)]); n /= 32 }
        return out
    }

    private func decodeExpiry(_ s: String) -> Date? {
        var n = 0
        for ch in s {
            guard let i = alpha.firstIndex(of: ch) else { return nil }
            n = n * 32 + i
        }
        return Calendar.current.date(byAdding: .day, value: n, to: epoch)
    }
}

struct VexxRoot: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: PatchProjectStore
    @StateObject private var license = VexxLicense()
    @StateObject private var engine = VexxEngine()
    @State private var input = ""

    var body: some View {
        if license.isValid {
            VexxMain(engine: engine)
                .task {
                    appState.detectSupport()
                    engine.refresh(store.items)
                }
        } else {
            VStack(spacing: 18) {
                Spacer()
                Text("VEEX").font(.system(size: 46, weight: .black)).foregroundStyle(AppTheme.accent)
                Text("EXTERNAL · by Levi").font(.caption).foregroundStyle(.secondary)

                TextField("VEEX-XXXX-XXX", text: $input)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))

                HStack(spacing: 8) {
                    Circle().fill(appState.isSupported ? .green : .red).frame(width: 9, height: 9)
                    Text(appState.isSupported ? "Soportado" : "No soportado")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(appState.isSupported ? .green : .red)
                    Text("iOS \(AppInfo.osVersion)").font(.footnote).foregroundStyle(.secondary)
                }

                if let e = license.error { Text(e).font(.caption).foregroundStyle(.red) }

                Button("Continuar") {
                    license.activate(input)
                    if license.isValid { VexxVoice.play(.gate) }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .controlSize(.large)
                .disabled(!appState.isSupported || input.isEmpty)

                Text("ID: \(VexxLicense.deviceID)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(26)
            .task { appState.detectSupport() }
        }
    }
}

struct VexxMain: View {
    @EnvironmentObject private var store: PatchProjectStore
    @ObservedObject var engine: VexxEngine
    @State private var tab: VexxTab = .aimbots
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(VexxTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                List {
                    ForEach(VexxCatalog.rows.filter { $0.tab == tab }) { row in
                        VexxSwitchRow(row: row, engine: engine, items: store.items)
                    }
                }
                .listStyle(.plain)

                Button { openFF() } label: {
                    Text("ABRIR FREE FIRE")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .padding()
            }
            .navigationTitle("VEEX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
            }
            .sheet(isPresented: $showSettings) { VexxSettings(engine: engine) }
            .task { engine.refresh(store.items) }
        }
    }

    private func openFF() {
        for s in ["freefire://", "freefiremax://"] {
            if let u = URL(string: s), UIApplication.shared.canOpenURL(u) {
                UIApplication.shared.open(u); return
            }
        }
    }
}

struct VexxSwitchRow: View {
    let row: VexxRow
    @ObservedObject var engine: VexxEngine
    let items: [PatchLibraryItem]

    private var item: PatchLibraryItem? {
        items.first { $0.project?.name.localizedCaseInsensitiveContains(row.match) == true }
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { item.map { engine.active.contains($0.id) } ?? false },
            set: { _ in if let item { engine.toggle(item) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.subheadline.weight(.semibold))
                if item == nil {
                    Text("parche no encontrado").font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .tint(AppTheme.accent)
        .disabled(item == nil || engine.busyID != nil)
    }
}

struct VexxSettings: View {
    @EnvironmentObject private var store: PatchProjectStore
    @ObservedObject var engine: VexxEngine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("vexx.mute") private var mute = false
    @State private var confirmRestore = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Voces", isOn: Binding(get: { !mute }, set: { mute = !$0 }))
                Section {
                    Button("Restaurar todo") { confirmRestore = true }
                        .disabled(engine.busyID != nil)
                    if let e = engine.error {
                        Text(e).font(.caption2).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Desactiva todos los parches activos.")
                }
                Section {
                    Text("ID: \(VexxLicense.deviceID)").font(.caption.monospaced())
                }
            }
            .navigationTitle("Ajustes")
            .toolbar { Button("Listo") { dismiss() } }
            .confirmationDialog(
                "¿Restaurar todos los parches?",
                isPresented: $confirmRestore,
                titleVisibility: .visible
            ) {
                Button("Restaurar", role: .destructive) { engine.restoreAll(store.items) }
            }
        }
    }
}
