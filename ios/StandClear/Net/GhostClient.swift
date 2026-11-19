import Foundation

/// Talks to the Modal backend (backend/app.py). Everything is best effort: underground you have no
/// signal, so ghosts are prefetched at stations and uploads wait in a queue until you're back online.
@MainActor
final class GhostClient: ObservableObject {
    /// station id -> who holds it. Win the leg into a station to take it.
    @Published private(set) var turf: [String: String] = [:]
    @Published private(set) var lastError: String?

    let baseURL: URL?
    private var cache: [String: [Ghost]] = [:]   // "L:3" -> ghosts for round 3 on the L
    private var outbox: [(path: String, body: Data)] = []

    init() {
        let s = (Bundle.main.object(forInfoDictionaryKey: "StandClearAPI") as? String ?? "").trimmingCharacters(in: .whitespaces)
        baseURL = s.isEmpty || s.contains("YOUR-") ? nil : URL(string: s)
        if let data = UserDefaults.standard.data(forKey: "ghostCache"),
           let saved = try? JSONDecoder().decode([String: [Ghost]].self, from: data) {
            cache = saved
        }
    }

    var isConfigured: Bool { baseURL != nil }

    // MARK: - Ghosts

    func takeGhost(line: String, round: Int, notFrom player: String) -> Ghost? {
        let key = "\(line):\(round)"
        guard var list = cache[key], !list.isEmpty else { return nil }
        let candidates = list.indices.filter { list[$0].player != player }
        guard let i = candidates.randomElement() else { return nil }
        let g = list.remove(at: i)
        cache[key] = list
        save()
        return g
    }

    func prefetch(line: String, rounds: ClosedRange<Int>) {
        guard let baseURL else { return }
        flush()
        var c = URLComponents(url: baseURL.appendingPathComponent("ghosts"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "line", value: line), .init(name: "from", value: "\(rounds.lowerBound)"), .init(name: "to", value: "\(rounds.upperBound)")]
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: c.url!)
                let ghosts = try JSONDecoder().decode([Ghost].self, from: data)
                for g in ghosts {
                    let key = "\(g.line):\(g.round)"
                    var list = cache[key] ?? []
                    if !list.contains(g) { list.append(g) }
                    cache[key] = Array(list.suffix(10))
                }
                save()
                lastError = nil
            } catch {
                lastError = "ghosts: \(error.localizedDescription)"
            }
        }
    }

    func upload(_ ghost: Ghost) {
        send("teams", ghost)
    }

    // MARK: - Turf

    func loadTurf(line: String) {
        guard let baseURL else { return }
        var c = URLComponents(url: baseURL.appendingPathComponent("turf"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "line", value: line)]
        Task {
            if let result = try? await URLSession.shared.data(from: c.url!),
               let t = try? JSONDecoder().decode([String: String].self, from: result.0) {
                turf = t
            }
        }
    }

    func claimTurf(line: String, station: Station, player: String, team: [Unit]) {
        turf[station.id] = player   // optimistic, so you see it even underground
        send("turf", TurfClaim(line: line, station: station.id, player: player, team: team))
    }

    // MARK: - Runs (for the leaderboard and Tim's fridge)

    func postRun(line: String, endedAt: String, player: String, wins: Int, stops: Int, madeIt: Bool, team: [Unit]) {
        send("runs", RunReport(line: line, endedAt: endedAt, player: player, wins: wins, stops: stops, madeIt: madeIt,
                               crew: team.map { "\($0.emoji)\($0.atk)/\($0.hp)" }.joined(separator: " ")))
    }

    // MARK: - Plumbing

    private struct TurfClaim: Codable { let line: String; let station: String; let player: String; let team: [Unit] }
    private struct RunReport: Codable { let line: String; let endedAt: String; let player: String; let wins: Int; let stops: Int; let madeIt: Bool; let crew: String }

    private func send<T: Encodable>(_ path: String, _ body: T) {
        guard baseURL != nil, let data = try? JSONEncoder().encode(body) else { return }
        outbox.append((path, data))
        flush()
    }

    /// Try to deliver everything queued. Anything that fails stays for next time.
    private func flush() {
        guard let baseURL, !outbox.isEmpty else { return }
        let pending = outbox
        outbox = []
        Task {
            for item in pending {
                var req = URLRequest(url: baseURL.appendingPathComponent(item.path))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = item.body
                req.timeoutInterval = 8
                do {
                    let (_, resp) = try await URLSession.shared.data(for: req)
                    if ((resp as? HTTPURLResponse)?.statusCode ?? 500) >= 300 { outbox.append(item) }
                } catch {
                    outbox.append(item)
                }
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: "ghostCache") }
    }
}
