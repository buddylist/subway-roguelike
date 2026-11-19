import Foundation

enum Outcome: String, Codable { case win, loss, draw }

struct BattleFrame: Identifiable {
    let id: Int
    let text: String
    let ours: [Unit]
    let theirs: [Unit]
}

struct BattleResult {
    let frames: [BattleFrame]
    let outcome: Outcome
    let survivors: [Unit]      // your side after the fight (dead ones removed)
    let goldAfter: Int         // from Swipers
}

/// The auto-battle. Front of each array fights first. Pure and seeded: same input, same fight.
struct Battle {
    private var ours: [Unit]
    private var theirs: [Unit]
    private var rng: SeededRNG
    private var frames: [BattleFrame] = []

    static func run(ours: [Unit], theirs: [Unit], seed: UInt64) -> BattleResult {
        var b = Battle(ours: ours, theirs: theirs, rng: SeededRNG(seed: seed))
        return b.fight()
    }

    private init(ours: [Unit], theirs: [Unit], rng: SeededRNG) {
        self.ours = ours; self.theirs = theirs; self.rng = rng
    }

    private mutating func say(_ text: String) {
        frames.append(BattleFrame(id: frames.count, text: text, ours: ours, theirs: theirs))
    }

    private mutating func fight() -> BattleResult {
        say("Doors closing. \(ours.count) vs \(theirs.count).")

        // Start-of-battle abilities, ours first.
        for i in ours.indices { startAbility(side: 0, index: i) }
        for i in theirs.indices { startAbility(side: 1, index: i) }
        cleanup()

        var turns = 0
        while !ours.isEmpty && !theirs.isEmpty && turns < 60 {
            turns += 1
            let a = ours[0], e = theirs[0]
            hit(side: 1, index: 0, amount: a.atk)
            hit(side: 0, index: 0, amount: e.atk)
            say("\(a.emoji) \(a.name) ⚔️ \(e.emoji) \(e.name)")
            cleanup()
        }

        let outcome: Outcome
        if ours.isEmpty && theirs.isEmpty { outcome = .draw }
        else if theirs.isEmpty { outcome = .win }
        else if ours.isEmpty { outcome = .loss }
        else { outcome = .draw }
        var gold = 0
        for u in ours where u.kind == .swiper { gold += u.lv }
        say(outcome == .win ? "You held the car." : outcome == .loss ? "You got shoved off the train." : "Everyone's too tired. Draw.")
        return BattleResult(frames: frames, outcome: outcome, survivors: ours, goldAfter: gold)
    }

    // side 0 = ours, 1 = theirs
    private func team(_ side: Int) -> [Unit] { side == 0 ? ours : theirs }
    private mutating func modify(_ side: Int, _ f: (inout [Unit]) -> Void) {
        if side == 0 { f(&ours) } else { f(&theirs) }
    }

    private mutating func startAbility(side: Int, index: Int) {
        guard index < team(side).count else { return }
        let u = team(side)[index]
        let foe = 1 - side
        switch u.kind {
        case .dancer:
            let foes = team(foe)
            let live = foes.indices.filter { foes[$0].hp > 0 }
            guard let t = live.randomElement(using: &rng) else { return }
            hit(side: foe, index: t, amount: 2 * u.lv, isAbility: true)
            say("\(u.emoji) \"SHOWTIME!\" kicks \(foes[t].emoji) for \(2 * u.lv)")
        case .busker:
            modify(side) { t in for i in t.indices { t[i].atk += u.lv } }
            say("\(u.emoji) Busker plays. Allies +\(u.lv) atk")
        case .preacher:
            modify(side) { t in if !t.isEmpty { t[0].hp += 3 * u.lv } }
            say("\(u.emoji) The preacher blesses the front (+\(3 * u.lv) hp)")
        case .courier:
            let foes = team(foe)
            guard let t = foes.indices.last(where: { foes[$0].hp > 0 }) else { return }
            hit(side: foe, index: t, amount: 3 * u.lv, isAbility: true)
            say("\(u.emoji) Delivery guy clips \(foes[t].emoji) for \(3 * u.lv)")
        case .conductor:
            modify(side) { t in for i in t.indices { t[i].atk += u.lv; t[i].hp += u.lv } }
            say("\(u.emoji) \"Stand clear!\" Allies +\(u.lv)/+\(u.lv)")
        default:
            break
        }
    }

    private mutating func hit(side: Int, index: Int, amount: Int, isAbility: Bool = false) {
        guard index < team(side).count else { return }
        modify(side) { t in
            var dmg = amount
            if t[index].kind == .manspreader && !isAbility { dmg = max(1, dmg - 1) }
            t[index].hp -= dmg
            if t[index].kind == .cat && t[index].hp > 0 { t[index].atk += 2 * t[index].lv }
        }
    }

    /// Remove the dead, front to back, and let their death abilities fire.
    private mutating func cleanup() {
        for side in [0, 1] {
            var i = 0
            while i < team(side).count {
                let u = team(side)[i]
                if u.hp > 0 { i += 1; continue }
                modify(side) { t in t.remove(at: i) }
                switch u.kind {
                case .rat:
                    modify(side) { t in t.insert(Unit(.slice, lv: u.lv), at: i) }
                    say("\(u.emoji) Pizza Rat drops a slice")
                case .ratKing:
                    modify(side) { t in t.insert(contentsOf: [Unit(.rat, lv: u.lv), Unit(.rat, lv: u.lv)], at: i) }
                    say("\(u.emoji) The Rat King falls. The rats scatter")
                default:
                    say("\(u.emoji) \(u.name) is out")
                }
                modify(side) { t in if t.count > 5 { t.removeLast(t.count - 5) } }
            }
        }
    }
}

/// Bots for when nobody has ridden this far yet, or you're offline.
enum LocalGhosts {
    static func make(line: String, round: Int, seed: UInt64) -> Ghost {
        var rng = SeededRNG(seed: seed)
        let tier = min(3, 1 + round / 3)
        let pool = Kind.allCases.filter { $0.info.tier >= 1 && $0.info.tier <= tier }
        let count = min(5, 1 + (round + 1) / 2)
        var team: [Unit] = []
        for _ in 0..<count {
            var u = Unit(pool.randomElement(using: &rng)!)
            u.atk += round / 3
            u.hp += round / 2
            team.append(u)
        }
        let names = ["a guy with a bike", "showtime crew", "rush hour", "a tourist family", "the 3am crowd", "a mariachi band"]
        return Ghost(player: names.randomElement(using: &rng)!, line: line, round: round, team: team)
    }
}
