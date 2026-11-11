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
    static let accent   = Color(white: 0.94)
    static let accentHi = Color.white
    static let bgTop    = Color(white: 0.10)
    static let bgBottom = Color(white: 0.01)
    static let card     = Color.white.opacity(0.07)
    static let stroke   = Color.white.opacity(0.14)
    static let on       = Color(red: 0.30, green: 0.85, blue: 0.50)
    static let off      = Color(red: 0.95, green: 0.35, blue: 0.40)
    static let spring   = Animation.spring(response: 0.32, dampingFraction: 0.68)
    static let supportedList = "iOS 17.0–17.7 · 18.0–18.7.1 · 26.0–26.6.1 · 27 betas 1–4"
}

struct VexxPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

enum VexxError: Error { case notBundled, importFailed }

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
        .init(id: "pecho",   title: "Aim Pecho",             file: "aim_pecho.3105",        tab: .aimbots),
        .init(id: "balas",   title: "Balas Mágicas",         file: "balas_magicas.3105",    tab: .aimbots),
        .init(id: "holoarm", title: "Hologramas Armas",      file: "holo_armas.3105",       tab: .holograms),
        .init(id: "holoper", title: "Hologramas Personajes", file: "holo_personaje.3105",   tab: .holograms),
        .init(id: "guest",   title: "Reset Guest",           file: "Reset Guest.3105",      tab: .guest),
    ]
}

enum VexxMatch {
    static func score(_ row: VexxRow, _ item: PatchLibraryItem) -> Int {
        let key = row.file.replacingOccurrences(of: ".3105", with: "").lowercased()
        let full = row.file.lowercased()
        let f = item.packageURL.deletingPathExtension().lastPathComponent.lowercased()
        let n = (item.project?.name ?? "").lowercased()

        var best = 0
        for t in [f, n] where !t.isEmpty {
            if t == key || t == full {
                best = max(best, 100)
            } else if t.hasPrefix(key) {
                best = max(best, 60 - abs(t.count - key.count))
            } else if key.hasPrefix(t) {
                best = max(best, 50 - abs(key.count - t.count))
            } else if t.contains(key) || key.contains(t) {
                best = max(best, 30)
            }
        }
        return best
    }

    static func assignment(
        rows: [VexxRow],
        items: [PatchLibraryItem]
    ) -> [String: PatchLibraryItem] {
        var candidates: [(rowID: String, item: PatchLibraryItem, score: Int)] = []
        for row in rows {
            let scored = items.map { (item: $0, score: score(row, $0)) }.filter { $0.score > 0 }
            guard let top = scored.max(by: { $0.score < $1.score }) else { continue }
            candidates.append((row.id, top.item, top.score))
        }

        var result: [String: PatchLibraryItem] = [:]
        var used = Set<UUID>()
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard !used.contains(candidate.item.id) else { continue }
            used.insert(candidate.item.id)
            result[candidate.rowID] = candidate.item
        }
        return result
    }
}

@MainActor
final class VexxEngine: ObservableObject {
    @Published private(set) var active: Set<UUID> = []
    @Published var busyID: UUID?
    @Published var error: String?

    func refresh(_ items: [PatchLibraryItem]) {
        active = Set(items.filter { DevicePatchService.latestReceipt(projectID: $0.id) != nil }.map(\.id))
    }

    func toggleRow(_ row: VexxRow, store: PatchProjectStore) {
        guard busyID == nil else { return }
        busyID = UUID()
        error = nil

        Task.detached(priority: .userInitiated) {
            do {
                var map = await MainActor.run {
                    VexxMatch.assignment(rows: VexxCatalog.rows, items: store.items)
                }

                if let existing = map[row.id],
                   await MainActor.run(body: { self.active.contains(existing.id) }) {
                    try Self.restoreOne(existing)
                    await MainActor.run {
                        _ = self.active.remove(existing.id)
                        self.busyID = nil
                        VexxVoice.play(.off)
                    }
                    return
                }

                if row.tab == .aimbots {
                    let others = await MainActor.run {
                        VexxCatalog.rows
                            .filter { $0.tab == .aimbots && $0.id != row.id }
                            .compactMap { map[$0.id] }
                            .filter { self.active.contains($0.id) }
                    }
                    for other in others {
                        try? Self.restoreOne(other)
                        await MainActor.run { _ = self.active.remove(other.id) }
                    }
                }

                var target = map[row.id]

                if target == nil {
                    try await Self.importBundled(row: row, store: store)
                    map = await MainActor.run {
                        VexxMatch.assignment(rows: VexxCatalog.rows, items: store.items)
                    }
                    target = map[row.id]
                }

                guard let item = target else { throw VexxError.notBundled }

                try Self.applyOne(item)
                await MainActor.run {
                    self.active.insert(item.id)
                    self.busyID = nil
                    VexxVoice.play(.on)
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

    private nonisolated static func importBundled(
        row: VexxRow,
        store: PatchProjectStore
    ) async throws {
        let base = row.file.replacingOccurrences(of: ".3105", with: "")
        guard let url = Bundle.main.url(forResource: row.file, withExtension: nil)
            ?? Bundle.main.url(forResource: base, withExtension: "3105"),
              let data = try? Data(contentsOf: url) else {
            throw VexxError.notBundled
        }

        await MainActor.run {
            _ = store.importPackage(data: data, password: VexxCatalog.password)
        }

        for _ in 0..<24 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            let done = await MainActor.run {
                !store.isBusy && VexxMatch.assignment(
                    rows: VexxCatalog.rows,
                    items: store.items
                )[row.id] != nil
            }
            if done { return }
        }
        throw VexxError.importFailed
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
    @State private var glow = false

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
                colors: [Color.white.opacity(glow ? 0.16 : 0.06), .clear],
                center: .top,
                startRadius: 10,
                endRadius: glow ? 420 : 300
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("VEEX")
                    .font(.system(size: 66, weight: .black))
                    .tracking(12)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [VexxTheme.accentHi, Color(white: 0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .white.opacity(glow ? 0.5 : 0.15), radius: glow ? 32 : 12)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)

                Text("BY LEVI")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(7)
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.top, 10)
                    .opacity(appeared ? 1 : 0)

                Spacer().frame(height: 46)

                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("VEEX-XXXX-XXX", text: $input)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white)
                        .tint(.white)
                }
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(VexxTheme.card, in: .rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(input.isEmpty ? VexxTheme.stroke : .white.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: input.isEmpty ? .clear : .white.opacity(0.25), radius: 16)
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
                    if input.isEmpty { license.error = "Escribe tu key"; return }
                    guard appState.isSupported else {
                        license.error = "Este iOS no está soportado"
                        return
                    }
                    license.activate(input)
                    if license.isValid { VexxVoice.play(.gate) }
                } label: {
                    Text("Continuar")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(VexxTheme.bgBottom)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                        .background(
                            LinearGradient(
                                colors: [VexxTheme.accentHi, VexxTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: .rect(cornerRadius: 18)
                        )
                        .shadow(color: .white.opacity(glow ? 0.4 : 0.2), radius: glow ? 22 : 12)
                }
                .buttonStyle(VexxPressStyle())
                .padding(.top, 26)

                Spacer()

                Text("SOPORTADO")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.22))
                Text(VexxTheme.supportedList)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.32))
                    .multilineTextAlignment(.center)
                    .padding(.top, 3)

                HStack(spacing: 22) {
                    Link(destination: URL(string: "https://t.me/levibrouh")!) {
                        Label("levibrouh", systemImage: "paperplane.fill")
                    }
                    Link(destination: URL(string: "https://t.me/levibrouhs")!) {
                        Label("Canal", systemImage: "megaphone.fill")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 16)
                .padding(.bottom, 16)
                .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 30)
        }
        .task {
            appState.detectSupport()
            withAnimation(.easeOut(duration: 0.55)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
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
                        let map = VexxMatch.assignment(rows: VexxCatalog.rows, items: store.items)
                        ForEach(VexxCatalog.rows.filter { $0.tab == tab }) { row in
                            VexxSwitchRow(row: row, engine: engine, item: map[row.id])
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
                        .foregroundStyle(VexxTheme.bgBottom)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                        .background(
                            LinearGradient(
                                colors: [VexxTheme.accentHi, VexxTheme.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: .rect(cornerRadius: 18)
                        )
                        .shadow(color: .white.opacity(0.25), radius: 14)
                    }
                    .buttonStyle(VexxPressStyle())
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("VEEX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .sheet(isPresented: $showSettings) {
                VexxSettings(license: license)
            }
            .task { engine.refresh(store.items) }
        }
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
    @EnvironmentObject private var store: PatchProjectStore
    let row: VexxRow
    @ObservedObject var engine: VexxEngine
    let item: PatchLibraryItem?

    @State private var pending = false

    private var isOn: Bool {
        item.map { engine.active.contains($0.id) } ?? false
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isOn || pending },
            set: { _ in
                pending = true
                engine.toggleRow(row, store: store)
            }
        )) {
            HStack(spacing: 11) {
                Circle()
                    .fill(pending ? Color.orange : (isOn ? VexxTheme.on : VexxTheme.off))
                    .frame(width: 8, height: 8)
                    .shadow(
                        color: (pending ? Color.orange : (isOn ? VexxTheme.on : VexxTheme.off)).opacity(0.8),
                        radius: 6
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(pending ? "aplicando…" : (isOn ? "activado" : "desactivado"))
                        .font(.caption2)
                        .foregroundStyle(pending ? .orange : (isOn ? VexxTheme.on : .white.opacity(0.35)))
                }
                if pending {
                    Spacer()
                    ProgressView().controlSize(.small)
                }
            }
        }
        .tint(isOn ? VexxTheme.on : VexxTheme.off)
        .disabled(engine.busyID != nil)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14)
                .fill(isOn ? VexxTheme.on.opacity(0.12) : VexxTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isOn ? VexxTheme.on.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
        .animation(VexxTheme.spring, value: isOn)
        .onChange(of: engine.busyID) { value in
            if value == nil { pending = false }
        }
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
