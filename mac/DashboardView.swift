import SwiftUI

private let accountColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
private func accountColor(_ index: Int) -> Color { accountColors[((index % accountColors.count) + accountColors.count) % accountColors.count] }
private func countText(_ value: Int?) -> String { value.map { $0.formatted(.number) } ?? "—" }
private func timestamp(_ value: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    return date?.formatted(date: .abbreviated, time: .shortened) ?? value
}

struct DashboardView: View {
    @StateObject private var store = AccountStore.shared
    @State private var period: AnalyticsPeriod = .all
    @State private var showingAdd = false
    @State private var detailAccount: NoteAccount?
    @State private var accountToRemove: NoteAccount?
    @State private var selectedAccount: UUID?

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Label("note accounts", systemImage: "square.stack.3d.up.fill")
                    .font(.headline).padding(.horizontal, 16).padding(.top, 22)
                Text("アカウント切り替え").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                List(store.accounts) { account in
                    HStack(spacing: 8) {
                        Circle().fill(accountColor(account.colorIndex)).frame(width: 9, height: 9)
                        Button {
                            selectedAccount = account.id
                            store.open(account)
                        } label: {
                            HStack { Text(account.name).lineLimit(1); Spacer(); Image(systemName: "arrow.up.right") }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help("専用Chromeでnoteを開く")
                        Menu {
                            Button("アクセス状況を表示") { detailAccount = account }
                            Button("noteのダッシュボードを開く") { store.open(account, url: "https://note.com/dashboard") }
                            Button("保存場所を表示") { store.revealProfile(account) }
                            Divider()
                            Button("削除…", role: .destructive) { accountToRemove = account }
                                .disabled(store.updating.contains(account.id))
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).frame(width: 18)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(selectedAccount == account.id ? accountColor(account.colorIndex).opacity(0.12) : Color.clear)
                }.listStyle(.sidebar)
                Button { showingAdd = true } label: { Label("アカウントを追加", systemImage: "plus") }
                    .buttonStyle(.borderless).padding(16)
                Text("ウィンドウを閉じると専用Chromeも終了します。")
                    .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 16)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("アクセスダッシュボード").font(.largeTitle.bold())
                        Text("\(store.accounts.count)アカウント · 行をクリックすると記事別のアクセス状況を表示")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("集計期間", selection: $period) {
                        ForEach(AnalyticsPeriod.allCases) { Text($0.label).tag($0) }
                    }.frame(width: 145).disabled(!store.updating.isEmpty)
                    Button {
                        Task { await store.refreshAll(period: period) }
                    } label: {
                        Label(store.refreshingAll ? "更新中…" : "すべて更新", systemImage: "arrow.clockwise")
                    }.buttonStyle(.borderedProminent).disabled(store.accounts.isEmpty || !store.updating.isEmpty)
                }
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("「更新」で専用Chromeに接続します。初回はnoteへのログインが必要です。数値はnoteの集計時点の値です。")
                }.font(.caption).foregroundStyle(.secondary)
                if store.accounts.isEmpty {
                    ContentUnavailableView("アカウントを追加してください", systemImage: "person.crop.circle.badge.plus",
                        description: Text("サイドバーの「アカウントを追加」から登録できます。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack {
                            Text("アカウント").frame(maxWidth: .infinity, alignment: .leading)
                            metricHeaders
                            Text("更新").frame(width: 55)
                        }.font(.caption.bold()).foregroundStyle(.secondary).padding(16)
                        Divider()
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(store.accounts) { account in
                                    accountRow(account)
                                    Divider()
                                }
                            }
                        }
                    }.background(.background).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
                Text("— は未取得またはデータなしです。取得失敗時は前回取得値を保持します。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1100, minHeight: 620)
        .sheet(isPresented: $showingAdd) { AddAccountView(colors: accountColors) { store.add(name: $0, colorIndex: $1) } }
        .sheet(item: $detailAccount) { ArticleDetailView(account: $0, period: period) }
        .alert("エラー", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("「\(accountToRemove?.name ?? "")」を削除しますか？", isPresented: Binding(
            get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } }), titleVisibility: .visible) {
            if let account = accountToRemove {
                Button("一覧からのみ削除") { store.remove(account, deleteLoginData: false); accountToRemove = nil }
                Button("ログイン情報も完全に削除", role: .destructive) { store.remove(account, deleteLoginData: true); accountToRemove = nil }
            }
            Button("キャンセル", role: .cancel) { accountToRemove = nil }
        }
    }

    private var metricHeaders: some View {
        Group {
            Text("インプレッション").frame(width: 115, alignment: .trailing)
            Text("PV").frame(width: 85, alignment: .trailing)
            Text("スキ").frame(width: 75, alignment: .trailing)
            Text("コメント").frame(width: 75, alignment: .trailing)
        }
    }

    private func accountRow(_ account: NoteAccount) -> some View {
        let snapshot = store.snapshot(for: account, period: period)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { detailAccount = account } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Circle().fill(accountColor(account.colorIndex)).frame(width: 8, height: 8); Text(account.name).font(.headline) }
                            Text(snapshot.map { "取得: " + timestamp($0.fetchedAt) } ?? "未取得")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(countText(snapshot?.totals.impressions)).frame(width: 115, alignment: .trailing)
                        Text(countText(snapshot?.totals.pv)).frame(width: 85, alignment: .trailing)
                        Text(countText(snapshot?.totals.likes)).frame(width: 75, alignment: .trailing)
                        Text(countText(snapshot?.totals.comments)).frame(width: 75, alignment: .trailing)
                    }.monospacedDigit().contentShape(Rectangle())
                }.buttonStyle(.plain)
                Group {
                    if store.updating.contains(account.id) { ProgressView().controlSize(.small) }
                    else { Button { Task { await store.refresh(account, period: period) } } label: { Image(systemName: "arrow.clockwise") }.help("このアカウントを更新") }
                }.frame(width: 55)
            }
            if let error = store.refreshErrors[account.id] {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }.padding(16)
    }
}

struct ArticleDetailView: View {
    let account: NoteAccount
    let period: AnalyticsPeriod
    @ObservedObject private var store = AccountStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var sort = "pv"
    @State private var ascending = false
    private var snapshot: AnalyticsSnapshot? { store.snapshot(for: account, period: period) }
    private var articles: [ArticleStats] {
        let filtered = (snapshot?.articles ?? []).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
        return filtered.sorted { a, b in
            if sort == "date" { return ascending ? (a.publishedAt ?? "") < (b.publishedAt ?? "") : (a.publishedAt ?? "") > (b.publishedAt ?? "") }
            func value(_ article: ArticleStats) -> Int {
                switch sort { case "impressions": article.metrics.impressions ?? -1; case "likes": article.metrics.likes; case "comments": article.metrics.comments; default: article.metrics.pv }
            }
            if value(a) == value(b) { return a.id < b.id }
            return ascending ? value(a) < value(b) : value(a) > value(b)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.name).font(.title.bold())
                    Text("記事別アクセス状況 · \(period.label)").foregroundStyle(.secondary)
                }
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField("記事タイトルを検索", text: $search).textFieldStyle(.roundedBorder)
                Picker("並び順", selection: $sort) {
                    Text("PV").tag("pv"); Text("インプレッション").tag("impressions")
                    Text("スキ").tag("likes"); Text("コメント").tag("comments"); Text("公開日").tag("date")
                }.frame(width: 210)
                Button(ascending ? "昇順 ↑" : "降順 ↓") { ascending.toggle() }
                Button("更新") { Task { await store.refresh(account, period: period) } }.disabled(store.updating.contains(account.id))
            }
            if let error = store.refreshErrors[account.id] { Text(error).font(.caption).foregroundStyle(.orange) }
            if store.updating.contains(account.id) { ProgressView("取得中…").controlSize(.small) }
            if snapshot == nil {
                ContentUnavailableView("アクセス情報は未取得です", systemImage: "chart.bar.xaxis", description: Text("「更新」で記事別のアクセス情報を取得します。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(articles) {
                    TableColumn("記事") { article in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.title).lineLimit(2)
                            Text(article.publishedAt.map { String($0.prefix(10)) } ?? "公開日なし").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.width(min: 240, ideal: 360)
                    TableColumn("インプレッション") { Text(countText($0.metrics.impressions)).monospacedDigit() }.width(125)
                    TableColumn("PV") { Text(countText($0.metrics.pv)).monospacedDigit() }.width(90)
                    TableColumn("スキ") { Text(countText($0.metrics.likes)).monospacedDigit() }.width(80)
                    TableColumn("コメント") { Text(countText($0.metrics.comments)).monospacedDigit() }.width(80)
                }
                if articles.isEmpty { Text(search.isEmpty ? "この期間に表示できる記事はありません。" : "検索に一致する記事はありません。") .foregroundStyle(.secondary) }
                if let snapshot {
                    Text("\(articles.count)記事 · 取得: \(timestamp(snapshot.fetchedAt))\(snapshot.sourceUpdatedAt.map { " · note集計: " + timestamp($0) } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(24).frame(width: 950, height: 620)
    }
}
