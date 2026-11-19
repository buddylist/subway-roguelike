import Foundation

/// Seeded RNG so a ghost fight plays out the same on every phone.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum Side: String { case you, them }

/// One thing that happened, for the battle screen to animate.
struct BattleEvent: Identifiable {
    let id = UUID()
    let text: String
    let you: [Unit]
    let them: [Unit]
    var hit: Set<UUID> = []
}

enum Outcome: String, Codable { case win, loss, draw }

struct Battle {
    static let maxRounds = 30

    /// Fight it out. Returns every step (for animation) and the outcome.
    static func run(you: [Unit], them: [Unit], seed: UInt64) -> (events: [BattleEvent], outcome: Outcome) {
        var rng = SplitMix64(seed: seed)
        var a = you, b = them
        var events: [BattleEvent] = []
        func log(_ t: String, hit: Set<UUID> = []) { events.append(.init(text: t, you: a, them: b, hit: hit)) }

        func team(_ s: Side) -> [Unit] { s == .you ? a : b }
        func set(_ s: Side, _ t: [Unit]) { if s == .you { a = t } else { b = t } }
        func other(_ s: Side) -> Side { s == .you ? .them : .you }

        func damage(_ s: Side, _ idx: Int, _ amount: Int) {
            var t = team(s)
            guard t.indices.contains(idx), t[idx].hp > 0 else { return }
            var d = amount
            if t[idx].kind.ability == .tank { d = max(1, d - 1) }
            t[idx].hp -= d
            if t[idx].hp > 0, t[idx].kind.ability == .hurtRage { t[idx].atk += 2 * t[idx].level }
            set(s, t)
        }

        /// Remove the dead, front to back, and let their death abilities fire.
        func cleanup(_ s: Side) {
            var t = team(s), out: [Unit] = []
            for u in t {
                if u.hp > 0 { out.append(u); continue }
                switch u.kind.ability {
                case .dieSlice: out.append(Unit("slice", level: u.level)); log("\(u.kind.emoji) \(u.kind.name) drops a slice")
                case .dieRats: out += [Unit("rat", level: u.level), Unit("rat", level: u.level)]; log("👑 The Rat King falls. The rats scatter.")
                default: break
                }
            }
            t = Array(out.prefix(5))
            set(s, t)
        }

        log("🚇 Doors closing…")
        // Start-of-battle abilities, your side first, front to back.
        for s in [Side.you, .them] {
            for i in team(s).indices {
                let u = team(s)[i], lv = u.level
                switch u.kind.ability {
                case .startKick:
                    let live = team(other(s)).indices.filter { team(other(s))[$0].hp > 0 }
                    if let j = live.randomElement(using: &rng) { damage(other(s), j, 2 * lv); log("🕺 \"SHOWTIME!\" kicks for \(2 * lv)", hit: [team(other(s))[j].id]) }
                case .startTeamAtk:
                    var t = team(s); for k in t.indices where k != i { t[k].atk += lv }; set(s, t); log("🎷 Busker plays, allies +\(lv) atk")
                case .startBlessFront:
                    var t = team(s); if !t.isEmpty { t[0].hp += 3 * lv }; set(s, t); log("📢 The Preacher blesses the front (+\(3 * lv) HP)")
                case .startSnipeBack:
                    if let j = team(other(s)).lastIndex(where: { $0.hp > 0 }) { damage(other(s), j, 3 * lv); log("🚲 Delivery Guy clips the back for \(3 * lv)", hit: [team(other(s))[j].id]) }
                case .startTeamBuff:
                    var t = team(s); for k in t.indices where k != i { t[k].atk += lv; t[k].hp += lv }; set(s, t); log("🧢 \"Stand clear of the closing doors!\" allies +\(lv)/+\(lv)")
                default: break
                }
            }
        }
        cleanup(.you); cleanup(.them)

        var rounds = 0
        while !a.isEmpty, !b.isEmpty, rounds < maxRounds {
            rounds += 1
            let x = a[0], y = b[0]
            damage(.them, 0, x.atk)
            damage(.you, 0, y.atk)
            log("\(x.kind.emoji) ⚔️ \(y.kind.emoji)", hit: [x.id, y.id])
            cleanup(.you); cleanup(.them)
        }

        let outcome: Outcome = (!a.isEmpty && b.isEmpty) ? .win : (a.isEmpty && !b.isEmpty) ? .loss : .draw
        log(outcome == .win ? "✅ You held the car." : outcome == .loss ? "❌ Shoved off the train." : "🤝 Everyone's too tired. Draw.")
        return (events, outcome)
    }
}
