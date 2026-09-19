import Foundation

enum AnalyticsPeriod: String, CaseIterable, Codable, Identifiable {
    case week = "LAST_7_DAYS", month = "LAST_28_DAYS", year = "LAST_365_DAYS", all = "ALL"
    var id: String { rawValue }
    var label: String {
        switch self { case .week: "直近7日"; case .month: "直近28日"; case .year: "直近365日"; case .all: "全期間" }
    }
}

struct Metrics: Codable {
    let impressions: Int?
    let pv: Int
    let likes: Int
    let comments: Int
}

struct ArticleStats: Codable, Identifiable {
    let id: String
    let title: String
    let publishedAt: String?
    let url: String?
    let metrics: Metrics
}

struct AnalyticsSnapshot: Codable {
    let period: String
    let date: String
    let fetchedAt: String
    let sourceUpdatedAt: String?
    let totals: Metrics
    let articles: [ArticleStats]
}

struct AnalyticsResult: Decodable {
    let ok: Bool
    let code: String?
    let snapshot: AnalyticsSnapshot?
}

enum AnalyticsError: LocalizedError {
    case unavailable, loginRequired, schemaChanged, network, tooManyArticles
    var errorDescription: String? {
        switch self {
        case .unavailable: "Chromeとの連携を開始できません。以前から開いている専用Chromeを終了して、もう一度更新してください。"
        case .loginRequired: "ログインが必要です。開いた専用Chromeでnoteへログインしてから、再度更新してください。"
        case .schemaChanged: "noteのデータ形式を確認できませんでした。連携処理の更新が必要な可能性があります。"
        case .network: "アクセス情報を取得できませんでした。接続を確認して再度更新してください。"
        case .tooManyArticles: "記事数が取得上限を超えました。前回のデータを保持しています。"
        }
    }
    static func from(_ code: String?) -> AnalyticsError {
        switch code { case "loginRequired": .loginRequired; case "schemaChanged": .schemaChanged;
        case "tooManyArticles": .tooManyArticles; default: .network }
    }
}

// One connection per refresh. No cookies or authentication headers cross this connection.
final class ChromeConnection {
    private let socket: URLSessionWebSocketTask
    private let session: URLSession
    private var nextID = 0

    init(url: URL) {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        session = URLSession(configuration: config)
        socket = session.webSocketTask(with: url)
        socket.resume()
    }
    func close() { socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }

    func call(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        let data = try JSONSerialization.data(withJSONObject: ["id":id,"method":method,"params":params])
        let timeout = Task { [socket] in
            try await Task.sleep(for: .seconds(130))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { timeout.cancel() }
        try await socket.send(.string(String(decoding:data, as:UTF8.self)))
        while true {
            let message = try await socket.receive()
            let responseData: Data
            switch message { case .data(let data): responseData = data; case .string(let text): responseData = Data(text.utf8); @unknown default: continue }
            guard let response = try JSONSerialization.jsonObject(with:responseData) as? [String:Any], response["id"] as? Int == id else { continue }
            guard response["error"] == nil, let result = response["result"] as? [String:Any] else { throw AnalyticsError.network }
            return result
        }
    }

    static func endpoint(profile: URL) async throws -> URL {
        let content = try String(contentsOf:profile.appendingPathComponent("DevToolsActivePort"), encoding:.utf8)
        let lines = content.split(separator:"\n")
        guard lines.count >= 2, let port = Int(lines[0]), (1...65535).contains(port) else { throw AnalyticsError.unavailable }
        var request = URLRequest(url:URL(string:"http://127.0.0.1:\(port)/json/version")!)
        request.timeoutInterval = 1
        let (data, _) = try await URLSession.shared.data(for:request)
        guard let result = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let address = result["webSocketDebuggerUrl"] as? String, let url = URL(string:address),
              url.host == "127.0.0.1" || url.host == "localhost",
              url.port == port, url.path == String(lines[1]) else { throw AnalyticsError.unavailable }
        return url
    }

    static func fetch(endpoint: URL, period: AnalyticsPeriod) async throws -> AnalyticsSnapshot {
        let browser = ChromeConnection(url:endpoint)
        defer { browser.close() }
        let target = try await browser.call("Target.createTarget", params:["url":"https://note.com/dashboard", "background":true])
        guard let targetID = target["targetId"] as? String else { throw AnalyticsError.network }
        do {
        // Resolve the new tab's websocket without accessing any other profile or tab.
        let listURL = URL(string:"http://127.0.0.1:\(endpoint.port!)/json/list")!
        let (data, _) = try await URLSession.shared.data(from:listURL)
        guard let targets = try JSONSerialization.jsonObject(with:data) as? [[String:Any]],
              let address = targets.first(where:{$0["id"] as? String == targetID})?["webSocketDebuggerUrl"] as? String,
              let tabURL = URL(string:address), ["127.0.0.1","localhost"].contains(tabURL.host ?? "") else { throw AnalyticsError.network }
        let tab = ChromeConnection(url:tabURL)
        defer { tab.close() }
        for _ in 0..<60 {
            let state = try await tab.call("Runtime.evaluate", params:["expression":"JSON.stringify({url:location.href,ready:document.readyState})", "returnByValue":true])
            if let remote = state["result"] as? [String:Any], let value = remote["value"] as? String,
               let info = try JSONSerialization.jsonObject(with:Data(value.utf8)) as? [String:String],
               info["ready"] == "complete", info["url"]?.hasPrefix("https://note.com/") == true { break }
            try await Task.sleep(for:.milliseconds(500))
        }
        guard let resource = Bundle.main.url(forResource:"FetchAnalytics", withExtension:"js") else { throw AnalyticsError.schemaChanged }
        let script = try String(contentsOf:resource, encoding:.utf8)
        let result = try await tab.call("Runtime.evaluate", params:[
            "expression":script + "\nfetchNoteAnalytics('\(period.rawValue)')",
            "awaitPromise":true, "returnByValue":true, "timeout":120000
        ])
        guard result["exceptionDetails"] == nil, let remote = result["result"] as? [String:Any], let value = remote["value"] as? [String:Any] else { throw AnalyticsError.network }
        let response = try JSONDecoder().decode(AnalyticsResult.self, from:JSONSerialization.data(withJSONObject:value))
        guard response.ok, let snapshot = response.snapshot, snapshot.period == period.rawValue else {
            // Keep the login page available when authentication is required.
            if response.code == "loginRequired" { _ = try? await browser.call("Target.activateTarget", params:["targetId":targetID]) }
            throw AnalyticsError.from(response.code)
        }
        _ = try? await browser.call("Target.closeTarget", params:["targetId":targetID])
        return snapshot
        } catch {
            if case AnalyticsError.loginRequired = error {
                // Leave the tab open so the user can sign in themselves.
            } else {
                _ = try? await browser.call("Target.closeTarget", params:["targetId":targetID])
            }
            throw error
        }
    }
}
