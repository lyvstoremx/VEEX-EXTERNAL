//
//  ContentView.swift
//  VEEX EXTERNAL
//

import SwiftUI
import UIKit
import AVFoundation
import CryptoKit

// MARK: - Error
enum VexxError: LocalizedError, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let m): return m }
    }
    var errorDescription: String? { description }
}

// MARK: - Audio
@MainActor
final class VexxAudio {
    static let shared = VexxAudio()
    private var player: AVAudioPlayer?
    func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

// MARK: - Catálogo
enum VexxGroup { case aim, holo, reset }

struct VexxPatch: Identifiable {
    let id: String
    let title: String
    let pkg: String
    let group: VexxGroup
}

enum VexxCatalog {
    static let password = "Levi-externas-veex-6393*#%"
    static let all: [VexxPatch] = [
        .init(id: "aim_drag", title: "Aim Drag Antena", pkg: "aim_drag_antena", group: .aim),
        .init(id: "aim_pecho", title: "Aim Pecho", pkg: "aim_pecho", group: .aim),
        .init(id: "balas", title: "Balas Mágicas", pkg: "balas_magicas", group: .aim),
        .init(id: "holo_arma", title: "Hologramas Armas", pkg: "holo_arma", group: .holo),
        .init(id: "holo_pers", title: "Hologramas Personajes", pkg: "holo_personaje", group: .holo),
        .init(id: "reset", title: "Borrar Invitado", pkg: "Reset Guest", group: .reset)
    ]

    static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Licencia
@MainActor
final class VexxLicense: ObservableObject {
    static let masters: Set<String> = ["VEEX-LEVI-2004", "VEEX-LEVI-FF26"]
    private static let secret = "veex-externas-levi-2026"
    private static let alpha = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let kKey = "veex.key"
    private static let kDev = "veex.devices"

    @Published var valid = false
    @Published var master = false
    @Published var expiry: Date?
    @Published var message: String?

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.kKey) {
            _ = activate(saved, silent: true)
        }
    }

    var idfv: String { UIDevice.current.identifierForVendor?.uuidString ?? "sin-id" }

    private func tag() -> [UInt8] {
        let h = SHA256.hash(data: Data((idfv + Self.secret).utf8))
        return Array(h).prefix(4).map { $0 }
    }

    private static func b32(_ bytes: [UInt8]) -> String {
        var out = ""
        var buffer = 0
        var bits = 0
        for b in bytes {
            buffer = (buffer << 8) | Int(b)
            bits += 8
            while bits >= 5 {
                out.append(alpha[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 { out.append(alpha[(buffer << (5 - bits)) & 31]) }
        return out
    }

    private static func unb32(_ s: String) -> [UInt8]? {
        var out: [UInt8] = []
        var buffer = 0
        var bits = 0
        for ch in s.uppercased() {
            guard let i = alpha.firstIndex(of: ch) else { return nil }
            buffer = (buffer << 5) | i
            bits += 5
            if bits >= 8 {
                out.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return out
    }

    @discardableResult
    func activate(_ raw: String, silent: Bool = false) -> Bool {
        let key = raw.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        message = nil

        if Self.masters.contains(key) {
            master = true
            valid = true
            expiry = nil
            UserDefaults.standard.set(key, forKey: Self.kKey)
            return true
        }

        let parts = key.split(separator: "-")
        guard parts.count == 3,
              parts[0] == "VEEX",
              let payload = Self.unb32(String(parts[1])), payload.count == 7,
              let sig = Self.unb32(String(parts[2])), sig.count >= 5 else {
            if !silent { message = "key inválida" }
            return false
        }

        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(payload),
            using: SymmetricKey(data: Data(Self.secret.utf8))
        )
        guard Array(mac).prefix(5).elementsEqual(sig.prefix(5)) else {
            if !silent { message = "key inválida" }
            return false
        }

        let days = Int(payload[0]) << 8 | Int(payload[1])
        let date = Calendar.current.date(
            byAdding: .day,
            value: days,
            to: Date(timeIntervalSince1970: 1_577_836_800)
        ) ?? Date()
        guard date > Date() else {
            if !silent { message = "key vencida" }
            return false
        }

        if payload[2] & 1 == 1, !Array(payload[3...6]).elementsEqual(tag()) {
            if !silent { message = "key de otro dispositivo" }
            return false
        }

        var devs = UserDefaults.standard.dictionary(forKey: Self.kDev) as? [String: [String]] ?? [:]
        var list = devs[key] ?? []
        if !list.contains(idfv) {
            if payload[2] & 2 == 0, list.count >= 1 {
                if !silent { message = "key en uso en otro dispositivo" }
                return false
            }
            list.append(idfv)
            devs[key] = list
            UserDefaults.standard.set(devs, forKey: Self.kDev)
        }

        master = false
        valid = true
        expiry = date
        UserDefaults.standard.set(key, forKey: Self.kKey)
        return true
    }

    func forget() {
        valid = false
        master = false
        expiry = nil
        UserDefaults.standard.removeObject(forKey: Self.kKey)
    }

    var remaining: String {
        if master { return "Permanente" }
        guard let expiry else { return "—" }
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0)
        return days == 0 ? "Vence hoy" : "\(days) días"
    }

    var devices: Int {
        let devs = UserDefaults.standard.dictionary(forKey: Self.kDev) as? [String: [String]] ?? [:]
        let key = UserDefaults.standard.string(forKey: Self.kKey) ?? ""
        return (devs[key] ?? []).count
    }
}

enum VexxSupport {
    static var isSupported: Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major >= 16 && major <= 27
    }
}

// MARK: - Raíz
struct ContentView: View {
    @StateObject private var license = VexxLicense()
    @State private var input = ""

    var body: some View {
        Group {
            if license.valid {
                VexxMain(license: license)
            } else {
                VexxGate(input: $input, license: license)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Gate
struct VexxGate: View {
    @Binding var input: String
    @ObservedObject var license: VexxLicense
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Text("VEEX")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(.white)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)

                HStack(spacing: 7) {
                    Circle()
                        .fill(VexxSupport.isSupported ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(VexxSupport.isSupported ? "Soportado" : "No soportado")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VexxSupport.isSupported ? .green : .red)
                }
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 12) {
                    TextField("VEEX-XXXX-XXXX", text: $input)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

                    if let m = license.message {
                        Text(m)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    }

                    Button {
                        if license.activate(input) { VexxAudio.shared.play("on") }
                    } label: {
                        Text("Continuar")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(appeared ? 1 : 0.95)
                }
                .padding(.horizontal, 26)

                Spacer()

                VStack(spacing: 8) {
                    Text("Levi")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                    HStack(spacing: 16) {
                        Link("Canal", destination: URL(string: "https://t.me/levibrouhs")!)
                        Link("Telegram", destination: URL(string: "https://t.me/levibrouh")!)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.bottom, 26)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { appeared = true }
        }
    }
}

// MARK: - Principal
struct VexxMain: View {
    @EnvironmentObject private var store: PatchProjectStore
    @ObservedObject var license: VexxLicense

    @State private var tab = 0
    @State private var on: Set<String> = []
    @State private var busy: String?
    @State private var error: String?
    @State private var showSettings = false

    private var rows: [VexxPatch] {
        switch tab {
        case 0: return VexxCatalog.all.filter { $0.group == .aim }
        case 1: return VexxCatalog.all.filter { $0.group == .holo }
        default: return VexxCatalog.all.filter { $0.group == .reset }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.12))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                tabs
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(rows) { p in rowView(p) }
                    }
                    .padding(16)
                }
                footer
            }
        }
        .task { sync() }
        .sheet(isPresented: $showSettings) { VexxSettings(license: license) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VEEX EXTERNAL")
                    .font(.system(size: 17, weight: .black))
                    .tracking(1)
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    Circle()
                        .fill(VexxSupport.isSupported ? .green : .red)
                        .frame(width: 6, height: 6)
                    Text(VexxSupport.isSupported ? "Soportado" : "No soportado")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VexxSupport.isSupported ? .green : .red)
                }
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Array(["Aimbots", "Hologramas", "Borrar Invitado"].enumerated()), id: \.offset) { i, t in
                Button {
                    withAnimation(.snappy) { tab = i }
                } label: {
                    Text(t)
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(tab == i ? Color.white : Color.white.opacity(0.07), in: Capsule())
                        .foregroundStyle(tab == i ? .black : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func rowView(_ p: VexxPatch) -> some View {
        let active = on.contains(p.id)
        let working = busy == p.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(active ? "Activado" : "Desactivado")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(active ? .green : .white.opacity(0.4))
            }
            Spacer()
            if working {
                ProgressView().tint(.white).scaleEffect(0.8)
            } else {
                Capsule()
                    .fill(active ? Color.green : Color.red)
                    .frame(width: 46, height: 26)
                    .overlay(alignment: active ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .padding(3)
                    }
                    .animation(.snappy, value: active)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { toggle(p) }
        .scaleEffect(working ? 0.98 : 1)
        .animation(.snappy, value: working)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { openFF() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 12))
                    Text("Abrir Free Fire").font(.system(size: 13, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            Button { sync() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: Lógica
    private func cacheKey(_ p: VexxPatch) -> String { "veex.id." + p.id }

    private func cache(_ id: UUID, _ p: VexxPatch) {
        UserDefaults.standard.set(id.uuidString, forKey: cacheKey(p))
    }

    private func availablePackages() -> [URL] {
        let fm = FileManager.default
        let root = Bundle.main.bundleURL
        var found: [URL] = []
        for dir in [root, root.appendingPathComponent("Frameworks")] {
            if let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                found += list.filter { $0.pathExtension.lowercased() == "3105" }
            }
        }
        if let extra = Bundle.main.urls(forResourcesWithExtension: "3105", subdirectory: nil) {
            found += extra
        }
        return found
    }

    private func packageURL(_ p: VexxPatch) -> URL? {
        if let direct = Bundle.main.url(forResource: p.pkg, withExtension: "3105") { return direct }
        let key = VexxCatalog.norm(p.pkg)
        return availablePackages().first {
            VexxCatalog.norm($0.deletingPathExtension().lastPathComponent) == key
        }
    }

    private func findItem(_ p: VexxPatch) -> PatchLibraryItem? {
        if let raw = UserDefaults.standard.string(forKey: cacheKey(p)),
           let id = UUID(uuidString: raw),
           let hit = store.items.first(where: { $0.id == id }) {
            return hit
        }
        let wanted = Set([VexxCatalog.norm(p.pkg), VexxCatalog.norm(p.title)])
        if let hit = store.items.first(where: {
            let n = VexxCatalog.norm($0.project?.name ?? "")
            return !n.isEmpty && wanted.contains(n)
        }) {
            cache(hit.id, p)
            return hit
        }
        return nil
    }

    private func sync() {
        var s = Set<String>()
        for p in VexxCatalog.all {
            if let item = findItem(p), DevicePatchService.latestReceipt(projectID: item.id) != nil {
                s.insert(p.id)
            }
        }
        on = s
    }

    private func waitIdle() async {
        for _ in 0..<80 {
            if !store.isBusy { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func toggle(_ p: VexxPatch) {
        guard busy == nil else { return }
        busy = p.id
        error = nil
        let turningOn = !on.contains(p.id)
        Task {
            do {
                if turningOn {
                    try await turnOn(p)
                } else {
                    try await turnOff(p)
                }
                VexxAudio.shared.play(turningOn ? "on" : "off")
            } catch {
                self.error = "\(p.title): \(String(describing: error))"
            }
            sync()
            busy = nil
        }
    }

    private func turnOn(_ p: VexxPatch) async throws {
        if p.group == .aim {
            for other in VexxCatalog.all where other.group == .aim && other.id != p.id {
                try? await turnOff(other)
            }
            sync()
        }
        let item = try await importPackage(p)
        try await applyItem(item)
    }

    private func turnOff(_ p: VexxPatch) async throws {
        guard let item = findItem(p) else {
            on.remove(p.id)
            return
        }
        if let receipt = DevicePatchService.latestReceipt(projectID: item.id) {
            await waitIdle()
            try await Task.detached(priority: .userInitiated) {
                _ = try DevicePatchService.inspectRestore(receipt: receipt)
                try DevicePatchService.restore(receipt: receipt, allowChangedTargets: true)
            }.value
            store.reload()
        }
        if p.group == .aim {
            await waitIdle()
            try? PatchProjectLibrary.delete(item)
            store.reload()
            UserDefaults.standard.removeObject(forKey: cacheKey(p))
        }
    }

    private func importPackage(_ p: VexxPatch) async throws -> PatchLibraryItem {
        if let existing = findItem(p) { return existing }
        guard let url = packageURL(p) else {
            let names = availablePackages().map { $0.lastPathComponent }.sorted()
            throw VexxError.message(
                "falta \(p.pkg).3105 · ipa: \(names.isEmpty ? "vacío" : names.joined(separator: ", "))"
            )
        }
        let data = try Data(contentsOf: url)

        for attempt in 1...4 {
            await waitIdle()
            let before = Set(store.items.map(\.id))
            guard store.importPackage(data: data, password: VexxCatalog.password) else {
                try? await Task.sleep(nanoseconds: 400_000_000)
                continue
            }
            await waitIdle()
            if let fresh = store.items.first(where: { !before.contains($0.id) }) {
                cache(fresh.id, p)
                return fresh
            }
            if let existing = findItem(p) { return existing }
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
        }
        throw VexxError.message("import falló")
    }

    private func applyItem(_ item: PatchLibraryItem) async throws {
        let project: PatchProject
        if item.summary.schemaVersion >= 2, item.canInspectContents {
            project = try PatchProjectLibrary.synchronizeWorkspace(item: item)
        } else if let base = item.project {
            project = base
        } else {
            throw VexxError.message("parche bloqueado")
        }
        await waitIdle()
        try await Task.detached(priority: .userInitiated) {
            _ = try DevicePatchService.apply(project: project)
        }.value
        store.reload()
    }

    private func openFF() {
        let schemes = ["freefire://", "freefiremax://"]
        func attempt(_ i: Int) {
            guard i < schemes.count, let url = URL(string: schemes[i]) else { return }
            UIApplication.shared.open(url, options: [:]) { ok in
                if !ok { attempt(i + 1) }
            }
        }
        attempt(0)
    }
}

// MARK: - Ajustes
struct VexxSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var license: VexxLicense

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                List {
                    Section {
                        LabeledContent("Estado") {
                            Text(license.master ? "Permanente" : license.remaining)
                                .foregroundStyle(license.master ? .green : .white)
                        }
                        LabeledContent("Dispositivos") {
                            Text(license.master ? "Ilimitados" : "\(license.devices)")
                        }
                        LabeledContent("iOS") {
                            Text(ProcessInfo.processInfo.operatingSystemVersionString)
                        }
                    } header: {
                        Text("Licencia")
                    }

                    Section {
                        Link("Telegram", destination: URL(string: "https://t.me/levibrouh")!)
                        Link("Canal", destination: URL(string: "https://t.me/levibrouhs")!)
                    } header: {
                        Text("Levi")
                    }

                    Section {
                        Button("Borrar key", role: .destructive) {
                            license.forget()
                            dismiss()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }
}
