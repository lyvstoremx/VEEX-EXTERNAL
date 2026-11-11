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
    static let on       = Color(red: 0.30, green: 0.85, blue: 0.50)
    static let off      = Color(red: 0.95, green: 0.35, blue: 0.40)
    static let spring   = Animation.spring(response: 0.32, dampingFraction: 0.68)
}

enum VexxEvent: String { case on, off, error, gate }

enum VexxVoice {
    private static var player: AVAudioPlayer?
    static func play(_ event: VexxEvent) {
        let exts = ["mp3", "m4a", "m4b", "caf", "wav"]
        guard let url = exts
            .compactMap({ Bundle.main.url(forResource: event.rawValue, withExtension: $0) })
            .first else { return }
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
    let file: String
    let tab: VexxTab
}

enum VexxCatalog {
    static let password = "Levi-externas-veex-6393*#%"

    static let rows: [VexxRow] = [
        .init(id: "antena",  title: "Aim Drag Antena",       file: "aim_drag_antena.3105",  tab: .aimbots),
        .init(id: "drag",    title: "Aim Drag",              file: "aim_drag.3105",         tab: .aimbots),
        .init(id: "pecho",   title: "Aim Pecho",             file: "iam_pecho.3105",        tab: .aimbots),
        .init(id: "balas",   title: "Balas Mágicas",         file: "balas_magicas.3105",    tab: .aimbots),
        .init(id: "holoarm", title: "Hologramas Armas",      file: "holo_armas.3105",       tab: .holograms),
        .init(id: "holoper", title: "Hologramas Personajes", file: "holo_personaje.3105",   tab: .holograms),
        .init(id: "guest",   title: "Reset Guest",           file: "Reset Guest.3105",      tab: .guest),
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
    @Published private(set) var expiry: Date?
    @Published private(set) var storedKey: String = ""

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
        let t = UserDefaults.standard.double(forKey: "vexx.exp")
        storedKey = UserDefaults.standard.string(forKey: "vexx.key") ?? ""
        if t == .infinity {
            isValid = true
            expiry = nil
        } else if t > 0 {
            let d = Date(timeIntervalSince1970: t)
            expiry = d
            isValid = d > Date()
        }
    }

    var remainingText: String {
        guard let expiry else { return "Permanente" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        if days <= 0 { return "Vence hoy" }
        return days == 1 ? "1 día restante" : "\(days) días restantes"
    }

    func activate(_ raw: String) {
        let c = norm(raw)
        if c == norm(Self.masterKey) {
            if Self.ownerID == "REEMPLAZA" || Self.ownerID == Self.deviceID {
                grant(nil, key: raw.uppercased())
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
        grant(exp, key: raw.uppercased())
    }

    func signOut() {
        isValid = false
        expiry = nil
        storedKey = ""
        UserDefaults.standard.removeObject(forKey: "vexx.exp")
        UserDefaults.standard.removeObject(forKey: "vexx.key")
    }

    private func grant(_ exp: Date?, key: String) {
        isValid = true
        error = nil
        expiry = exp
        storedKey = key
        UserDefaults.standard.set(exp?.timeIntervalSince1970 ?? .infinity, forKey: "vexx.exp")
        UserDefaults.standard.set(key, forKey: "vexx.key")
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
        Group {
            if license.isValid {
                VexxMain(engine: engine, license: license)
                    .transition(.opacity)
                    .task {
                        appState.detectSupport()
                        engine.refresh(store.items)
                    }
            } else {
                gate
            }
        }
        .animation(.easeInOut(duration: 0.3), value: license.isValid)
    }

    private var gate: some View {
        ZStack {
            LinearGradient(colors: [VexxTheme.bgTop, VexxTheme.bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            RadialGradient(
                colors: [VexxTheme.accent.opacity(0.26), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 360
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("VEEX")
                    .font(.system(size: 64, weight: .black))
                    .tracking(11)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [VexxTheme.accentHi, VexxTheme.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: VexxTheme.accent.opacity(0.6), radius: 26)
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)

                Text("BY LEVI")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.top, 9)
                    .opacity(appeared ? 1 : 0)

                Spacer().frame(height: 48)

                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.footnote)
                        .foregroundStyle(VexxTheme.accent.opacity(0.85))
                    TextField("VEEX-XXXX-XXX", text: $input)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white)
                        .tint(VexxTheme.accent)
                }
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(VexxTheme.card, in: .rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            input.isEmpty ? VexxTheme.stroke : VexxTheme.accent.opacity(0.75),
                            lineWidth: 1
                        )
                )
                .shadow(color: input.isEmpty ? .clear : VexxTheme.accent.opacity(0.35), radius: 14)
                .animation(VexxTheme.spring, value: input.isEmpty)

                HStack(spacing: 7) {
                    Circle()
                        .fill(appState.isSupported ? VexxTheme.on : VexxTheme.off)
                        .frame(width: 7, height: 7)
                    Text(appState.isSupported
                         ? "iOS \(AppInfo.osVersion) soportado"
                         : "iOS \(AppInfo.osVersion) no soportado")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 15)

                if let e = license.error {
                    Text(e)
                        .font(.caption)
                        .foregroundStyle(VexxTheme.off)
                        .padding(.top, 11)
                        .transition(.opacity)
                }

                Button {
                    license.activate(input)
                    if license.isValid { VexxVoice.play(.gate) }
                } label: {
                    Text("Continuar")
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
                    in: .rect(cornerRadius: 18)
                )
                .shadow(color: VexxTheme.accent.opacity(0.45), radius: 18)
                .disabled(!appState.isSupported || input.isEmpty)
                .opacity(!appState.isSupported || input.isEmpty ? 0.45 : 1)
                .scaleEffect(input.isEmpty ? 0.99 : 1)
                .animation(VexxTheme.spring, value: input.isEmpty)
                .padding(.top, 28)

                Spacer()

                HStack(spacing: 22) {
                    Link(destination: URL(string: "https://t.me/levibrouh")!) {
                        Label("levibrouh", systemImage: "paperplane.fill")
                    }
                    Link(destination: URL(string: "https://t.me/levibrouhs")!) {
                        Label("Canal", systemImage: "megaphone.fill")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(VexxTheme.accent.opacity(0.85))
                .padding(.bottom, 18)
                .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 30)
        }
        .task {
            appState.detectSupport()
            withAnimation(.easeOut(duration: 0.55)) { appeared = true }
        }
    }
}

struct VexxMain: View {
    @EnvironmentObject private var store: PatchProjectStore
    @ObservedObject var engine: VexxEngine
    @ObservedObject var license: VexxLicense
    @State private var tab: VexxTab = .aimbots
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [VexxTheme.bgTop, VexxTheme.bgBottom], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        ForEach(VexxTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .animation(VexxTheme.spring, value: tab)

                    List {
                        ForEach(VexxCatalog.rows.filter { $0.tab == tab }) { row in
                            VexxSwitchRow(row: row, engine: engine, items: store.items)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .animation(VexxTheme.spring, value: tab)

                    Button { openFF() } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "flame.fill")
                            Text("ABRIR FREE FIRE")
                        }
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VexxTheme.bgBottom)
                    .background(
                        LinearGradient(
                            colors: [VexxTheme.accentHi, VexxTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: .rect(cornerRadius: 18)
                    )
                    .shadow(color: VexxTheme.accent.opacity(0.45), radius: 18)
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
            .sheet(isPresented: $showSettings) {
                VexxSettings(license: license)
            }
            .task {
                engine.refresh(store.items)
                await seedBundledPatches()
            }
        }
    }

    private func seedBundledPatches() async {
        guard !UserDefaults.standard.bool(forKey: "vexx.seeded") else { return }
        UserDefaults.standard.set(true, forKey: "vexx.seeded")
        let urls = Bundle.main.urls(forResourcesWithExtension: "3105", subdirectory: nil) ?? []
        for url in urls {
            while store.isBusy { try? await Task.sleep(nanoseconds: 200_000_000) }
            if let data = try? Data(contentsOf: url) {
                _ = store.importPackage(data: data, password: VexxCatalog.password)
            }
        }
        while store.isBusy { try? await Task.sleep(nanoseconds: 200_000_000) }
        engine.refresh(store.items)
    }

    private func openFF() {
        let schemes = ["freefire://", "freefiremax://"]
        func attempt(_ index: Int) {
            guard index < schemes.count, let url = URL(string: schemes[index]) else { return }
            UIApplication.shared.open(url, options: [:]) { ok in
                if !ok { attempt(index + 1) }
            }
        }
        attempt(0)
    }
}

struct VexxSwitchRow: View {
    let row: VexxRow
    @ObservedObject var engine: VexxEngine
    let items: [PatchLibraryItem]

    private var item: PatchLibraryItem? {
        items.first {
            $0.packageURL.lastPathComponent.lowercased() == row.file.lowercased()
        }
    }

    private var isOn: Bool {
        item.map { engine.active.contains($0.id) } ?? false
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { _ in if let item { engine.toggle(item) } }
        )) {
            HStack(spacing: 11) {
                Circle()
                    .fill(isOn ? VexxTheme.on : VexxTheme.off)
                    .frame(width: 8, height: 8)
                    .shadow(color: (isOn ? VexxTheme.on : VexxTheme.off).opacity(0.8), radius: 6)
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
        }
        .tint(isOn ? VexxTheme.on : VexxTheme.off)
        .disabled(item == nil || engine.busyID != nil)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14)
                .fill(isOn ? VexxTheme.on.opacity(0.12) : VexxTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isOn ? VexxTheme.on.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
        .animation(VexxTheme.spring, value: isOn)
    }
}

struct VexxSettings: View {
    @ObservedObject var license: VexxLicense
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Tiempo", systemImage: "clock.fill")
                        Spacer()
                        Text(license.remainingText)
                            .foregroundStyle(license.expiry == nil ? VexxTheme.on : Color.secondary)
                    }
                    HStack {
                        Label("Dispositivos", systemImage: "iphone")
                        Spacer()
                        Text("1 · este iPhone").foregroundStyle(.secondary)
                    }
                    Button {
                        UIPasteboard.general.string = license.storedKey
                        copied = true
                    } label: {
                        Label(copied ? "Key guardada" : "Guardar key", systemImage: "doc.on.doc.fill")
                    }
                    Button(role: .destructive) {
                        license.signOut()
                        dismiss()
                    } label: {
                        Label("Borrar key", systemImage: "trash.fill")
                    }
                } header: {
                    Text("Tu key")
                }

                Section {
                    Link("t.me/levibrouh", destination: URL(string: "https://t.me/levibrouh")!)
                    Link("t.me/levibrouhs", destination: URL(string: "https://t.me/levibrouhs")!)
                } header: {
                    Text("Telegram")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Listo") { dismiss() } }
        }
    }
}
