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
            .tint(VexxTheme.accent)
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

enum VexxTheme {
    static let accent   = Color(red: 0.36, green: 0.74, blue: 1.00)
    static let accentHi = Color(red: 0.62, green: 0.87, blue: 1.00)
    static let bgTop    = Color(red: 0.05, green: 0.08, blue: 0.14)
    static let bgBottom = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let card     = Color.white.opacity(0.06)
    static let stroke   = Color.white.opacity(0.12)
}

enum VexxEvent: String { case on, off, error, gate }

enum VexxVoice {
    private static var player: AVAudioPlayer?
    static func play(_ event: VexxEvent) {
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
    static let ownerID   = "2BC18D89"
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
    @State private var appeared = false

    var body: some View {
        if license.isValid {
            VexxMain(engine: engine)
                .task {
                    appState.detectSupport()
                    engine.refresh(store.items)
                }
        } else {
            ZStack {
                LinearGradient(
                    colors: [VexxTheme.bgTop, VexxTheme.bgBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [VexxTheme.accent.opacity(0.22), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: 340
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    Text("VEEX")
                        .font(.system(size: 62, weight: .black))
                        .tracking(10)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [VexxTheme.accentHi, VexxTheme.accent],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: VexxTheme.accent.opacity(0.55), radius: 22)

                    Text("BY LEVI")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(5)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 8)

                    Spacer().frame(height: 46)

                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .font(.footnote)
                            .foregroundStyle(VexxTheme.accent.opacity(0.8))
                        TextField("VEEX-XXXX-XXX", text: $input)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                            .tint(VexxTheme.accent)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .background(VexxTheme.card, in: .rect(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(input.isEmpty ? VexxTheme.stroke : VexxTheme.accent.opacity(0.7), lineWidth: 1)
                    )

                    HStack(spacing: 7) {
                        Circle()
                            .fill(appState.isSupported ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                        Text(appState.isSupported ? "iOS \(AppInfo.osVersion) soportado" : "iOS \(AppInfo.osVersion) no soportado")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 14)

                    if let e = license.error {
                        Text(e)
                            .font(.caption)
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                            .padding(.top, 10)
                    }

                    Button {
                        license.activate(input)
                        if license.isValid { VexxVoice.play(.gate) }
                    } label: {
                        Text("Continuar")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VexxTheme.bgBottom)
                    .background(
                        LinearGradient(
                            colors: [VexxTheme.accentHi, VexxTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: .rect(cornerRadius: 16)
                    )
                    .disabled(!appState.isSupported || input.isEmpty)
                    .opacity(!appState.isSupported || input.isEmpty ? 0.45 : 1)
                    .padding(.top, 26)

                    Spacer()

                    HStack(spacing: 22) {
                        Link(destination: URL(string: "https://t.me/levibrouhy")!) {
                            Label("levibrouhy", systemImage: "paperplane.fill")
                        }
                        Link(destination: URL(string: "https://t.me/levibrouhs")!) {
                            Label("Canal", systemImage: "megaphone.fill")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VexxTheme.accent.opacity(0.85))
                    .padding(.bottom, 18)
                }
                .padding(.horizontal, 30)
                .opacity(appeared ? 1 : 0)
            }
            .task {
                appState.detectSupport()
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
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
            ZStack {
                LinearGradient(
                    colors: [VexxTheme.bgTop, VexxTheme.bgBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

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
                    .scrollContentBackground(.hidden)

                    Button { openFF() } label: {
                        Text("ABRIR FREE FIRE")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VexxTheme.bgBottom)
                    .background(
                        LinearGradient(
                            colors: [VexxTheme.accentHi, VexxTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: .rect(cornerRadius: 16)
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("VEEX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(VexxTheme.accent)
                }
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
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if item == nil {
                    Text("parche no encontrado")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .tint(VexxTheme.accent)
        .disabled(item == nil || engine.busyID != nil)
        .listRowBackground(VexxTheme.card)
    }
}

struct VexxSettings: View {
    @EnvironmentObject private var store: PatchProjectStore
    @ObservedObject var engine: VexxEngine
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRestore = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Restaurar todo") { confirmRestore = true }
                        .disabled(engine.busyID != nil)
                    if let e = engine.error {
                        Text(e).font(.caption2).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Desactiva todos los parches activos.")
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
