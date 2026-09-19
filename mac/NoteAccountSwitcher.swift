import SwiftUI
import AppKit

struct NoteAccount: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorIndex: Int
}

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published var accounts: [NoteAccount] = []
    @Published var errorMessage: String?
    @Published var snapshots: [String: AnalyticsSnapshot] = [:]
    @Published var refreshErrors: [UUID: String] = [:]
    @Published var updating: Set<UUID> = []
    @Published var refreshingAll = false

    private let fileManager = FileManager.default
    private let appFolder: URL
    private let accountsFile: URL
    private var chromeProcesses: [Process] = []

    private init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        appFolder = support.appendingPathComponent("NoteAccountSwitcher", isDirectory: true)
        accountsFile = appFolder.appendingPathComponent("accounts.json")
        try? fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        load()
        if let data = try? Data(contentsOf: appFolder.appendingPathComponent("analytics.json")),
           let saved = try? JSONDecoder().decode([String: AnalyticsSnapshot].self, from: data) {
            snapshots = saved
        }
    }

    func add(name: String, colorIndex: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accounts.append(NoteAccount(id: UUID(), name: trimmed, colorIndex: colorIndex))
        save()
    }

    func rename(_ account: NoteAccount, to name: String) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accounts[index].name = trimmed
        save()
    }

    func remove(_ account: NoteAccount, deleteLoginData: Bool) {
        guard !updating.contains(account.id) else { return }
        accounts.removeAll { $0.id == account.id }
        snapshots = snapshots.filter { !$0.key.hasPrefix(account.id.uuidString + "|") }
        refreshErrors[account.id] = nil
        do {
            try JSONEncoder().encode(snapshots).write(to: appFolder.appendingPathComponent("analytics.json"), options: .atomic)
        } catch {
            errorMessage = "アクセス情報の保存に失敗しました: \(error.localizedDescription)"
        }
        if deleteLoginData {
            try? fileManager.removeItem(at: profileFolder(for: account))
        }
        save()
    }

    func open(_ account: NoteAccount, url: String = "https://note.com/") {
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        guard fileManager.fileExists(atPath: chrome.path) else {
            errorMessage = "Google Chromeが見つかりません。/Applications にインストールしてください。"
            return
        }

        let profile = profileFolder(for: account)
        do {
            try fileManager.createDirectory(at: profile, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = chrome
            process.arguments = [
                "--user-data-dir=\(profile.path)",
                "--no-first-run",
                "--disable-background-mode",
                "--remote-debugging-port=0",
                "--remote-debugging-address=127.0.0.1",
                "--new-window",
                url
            ]
            try process.run()
            chromeProcesses.removeAll { !$0.isRunning }
            chromeProcesses.append(process)
        } catch {
            errorMessage = "Chromeを起動できませんでした: \(error.localizedDescription)"
        }
    }

    func snapshot(for account: NoteAccount, period: AnalyticsPeriod) -> AnalyticsSnapshot? {
        snapshots[account.id.uuidString + "|" + period.rawValue]
    }

    func refresh(_ account: NoteAccount, period: AnalyticsPeriod) async {
        guard !updating.contains(account.id) else { return }
        updating.insert(account.id)
        refreshErrors[account.id] = nil
        defer { updating.remove(account.id) }
        do {
            let profile = profileFolder(for: account)
            var endpoint = try? await ChromeConnection.endpoint(profile: profile)
            if endpoint == nil {
                open(account, url: "https://note.com/dashboard")
                for _ in 0..<24 {
                    try await Task.sleep(for: .milliseconds(500))
                    endpoint = try? await ChromeConnection.endpoint(profile: profile)
                    if endpoint != nil { break }
                }
            }
            guard let endpoint else { throw AnalyticsError.unavailable }
            let result = try await ChromeConnection.fetch(endpoint: endpoint, period: period)
            guard accounts.contains(where: { $0.id == account.id }) else { return }
            var next = snapshots
            next[account.id.uuidString + "|" + period.rawValue] = result
            try JSONEncoder().encode(next).write(to: appFolder.appendingPathComponent("analytics.json"), options: .atomic)
            snapshots = next
        } catch {
            refreshErrors[account.id] = error.localizedDescription
        }
    }

    func refreshAll(period: AnalyticsPeriod) async {
        guard !refreshingAll else { return }
        refreshingAll = true
        defer { refreshingAll = false }
        for account in accounts { await refresh(account, period: period) }
    }

    func stopLaunchedChrome() {
        for process in chromeProcesses where process.isRunning {
            process.terminate()
        }
        chromeProcesses.removeAll()
    }

    func revealProfile(_ account: NoteAccount) {
        let profile = profileFolder(for: account)
        try? fileManager.createDirectory(at: profile, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([profile])
    }

    private func profileFolder(for account: NoteAccount) -> URL {
        appFolder.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(account.id.uuidString, isDirectory: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: accountsFile),
              let decoded = try? JSONDecoder().decode([NoteAccount].self, from: data) else { return }
        accounts = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: accountsFile, options: .atomic)
        } catch {
            errorMessage = "設定を保存できませんでした: \(error.localizedDescription)"
        }
    }
}


struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorIndex = 0
    let colors: [Color]
    let onAdd: (String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("アカウントを追加").font(.title2.bold())
            TextField("例：仕事用note", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("識別カラー").font(.subheadline.bold())
            HStack(spacing: 12) {
                ForEach(colors.indices, id: \.self) { index in
                    Circle()
                        .fill(colors[index])
                        .frame(width: 28, height: 28)
                        .overlay {
                            if colorIndex == index {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { colorIndex = index }
                }
            }
            Text("追加後にサイドバーのアカウント名を押し、専用Chromeでnoteへログインしてください。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("追加") {
                    onAdd(name, colorIndex)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AccountStore.shared.stopLaunchedChrome()
    }
}

@main
struct NoteAccountSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .windowResizability(.contentMinSize)
    }
}
