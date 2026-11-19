import Foundation

/// Async multiplayer. At a station (with signal) your crew is uploaded and ghosts for the next legs
/// are downloaded. In the tunnel you fight those cached ghosts, offline. Turf claims queue up until
/// you get signal again. Talks to backend/modal_app.py; set its URL in the debug panel.
struct Ghost: Codable {
    let player: String
    let team: [Unit]
}

struct TurfClaim: Codable {
    let player: String
    let station: String
    let route: String
    let power: Int
}

final class GhostClient {
    private let defaults = UserDefaults.standard
    var baseURL: URL? {
        guard let s = defaults.string(forKey: "serverURL"), !s.isEmpty else { return nil }
        return URL(string: s.hasSuffix("/") ? String(s.dropLast()) : s)
    }

    /// round -> ghost, for the current route
    private(set) var cache: [Int: Ghost] = [:]
    private(set) var turf: [String: String] = [:]   // station id -> player
    private var pending: [Data] {
        get { defaults.array(forKey: "pendingPosts") as? [Data] ?? [] }
        set { defaults.set(newValue, forKey: "pendingPosts") }
    }

    func ghost(round: Int) -> Ghost? { cache[round] }

    /// Call at every station. Never throws: if there's no signal it just quietly does nothing.
    func sync(player: String, route: String, round: Int, team: [Unit]) async {
        guard let base = baseURL else { return }
        struct Up: Codable { let player: String; let route: String; let round: Int; let team: [Unit] }
        if !team.isEmpty, let body = try? JSONEncoder().encode(Up(player: player, route: route, round: round, team: team)) {
            enqueue(path: "teams", body: body)
        }
        await flush(base)
        if let url = URL(string: "\(base.absoluteString)/ghosts?route=\(route)&from_round=\(round)&count=6&player=\(player.urlEscaped)"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let got = try? JSONDecoder().decode([String: Ghost].self, from: data) {
            for (k, g) in got { if let r = Int(k) { cache[r] = g } }
        }
        if let url = URL(string: "\(base.absoluteString)/turf?route=\(route)"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let got = try? JSONDecoder().decode([String: TurfClaim].self, from: data) {
            turf = got.mapValues { $0.player }
        }
    }

    func claim(_ c: TurfClaim) {
        turf[c.station] = c.player
        if let body = try? JSONEncoder().encode(c) { enqueue(path: "turf", body: body) }
    }

    func resetCache() { cache = [:] }

    private func enqueue(path: String, body: Data) {
        let item = try? JSONEncoder().encode(["path": path, "body": body.base64EncodedString()])
        if let item { pending = (pending + [item]).suffix(50) }
    }

    private func flush(_ base: URL) async {
        var left: [Data] = []
        for item in pending {
            guard let d = try? JSONDecoder().decode([String: String].self, from: item),
                  let path = d["path"], let b64 = d["body"], let body = Data(base64Encoded: b64) else { continue }
            var req = URLRequest(url: base.appendingPathComponent(path))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 8
            if let (_, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 { continue }
            left.append(item)
        }
        pending = left
    }
}

extension String {
    var urlEscaped: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self }
}
