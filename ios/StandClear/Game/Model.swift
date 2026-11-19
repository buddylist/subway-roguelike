import Foundation

// MARK: - Map

struct Station: Identifiable, Hashable, Codable {
    let id: String          // GTFS stop id, e.g. "L08"
    let name: String
    let lat: Double
    let lon: Double
    let aboveGround: Bool   // elevated / at grade: GPS and signal work here
    let trait: Trait
}

struct Line: Identifiable, Hashable {
    let id: String          // "L", "G", "R"
    let name: String
    let colorHex: UInt32
    let northLabel: String  // terminus at index 0
    let southLabel: String  // terminus at the last index
    let stations: [Station]

    static func named(_ id: String) -> Line? { all.first { $0.id == id } }
}

/// Which way the train is going along `Line.stations`.
enum Heading: Int, Codable { case north = -1, south = 1 }

// MARK: - Shop traits (every station has one)

enum Trait: String, Codable, CaseIterable {
    case dollarSlice, luxury, transferHub, freeTransfer, thrift, bodega, lastStop, chaos, knockoffs, express, foodCourt

    var title: String {
        switch self {
        case .dollarSlice: return "Dollar slice"
        case .luxury: return "Luxury condos"
        case .transferHub: return "Transfer hub"
        case .freeTransfer: return "Free transfer"
        case .thrift: return "Thrift store"
        case .bodega: return "Bodega"
        case .lastStop: return "Last stop"
        case .chaos: return "Total chaos"
        case .knockoffs: return "Knockoffs"
        case .express: return "Express stop"
        case .foodCourt: return "Food court"
        }
    }

    var blurb: String {
        switch self {
        case .dollarSlice: return "Everything costs 1 less."
        case .luxury: return "Prices +1, but everyone comes with +1/+1."
        case .transferHub: return "Six slots instead of four."
        case .freeTransfer: return "Rerolls are free."
        case .thrift: return "Mystery boxes. One of them is free."
        case .bodega: return "A Bodega Cat is always in stock."
        case .lastStop: return "Everybody off. Get back a lost swipe."
        case .chaos: return "+3 gold, but the shop reshuffles after every purchase."
        case .knockoffs: return "Everything costs 1. Everything has -1 hp."
        case .express: return "+4 gold, only three slots."
        case .foodCourt: return "Your whole crew gets +1 hp, for good."
        }
    }
}

// MARK: - Units

enum Kind: String, Codable, CaseIterable {
    case cat, rat, slice, dancer, manspreader, swiper, busker, preacher, courier, conductor, ratKing

    struct Info { let emoji: String; let name: String; let atk: Int; let hp: Int; let tier: Int; let text: String }

    var info: Info {
        switch self {
        case .cat:         return Info(emoji: "🐈", name: "Bodega Cat", atk: 2, hp: 3, tier: 1, text: "Hurt: +2 attack.")
        case .rat:         return Info(emoji: "🐀", name: "Pizza Rat", atk: 1, hp: 2, tier: 1, text: "Dies: leaves a 2/2 Slice.")
        case .slice:       return Info(emoji: "🍕", name: "Slice", atk: 2, hp: 2, tier: 0, text: "Still warm.")
        case .dancer:      return Info(emoji: "🕺", name: "Showtime Dancer", atk: 2, hp: 2, tier: 1, text: "Start: kicks a random enemy for 2.")
        case .manspreader: return Info(emoji: "🧍", name: "Manspreader", atk: 1, hp: 7, tier: 1, text: "Takes 1 less damage from hits.")
        case .swiper:      return Info(emoji: "💳", name: "MetroCard Swiper", atk: 1, hp: 3, tier: 1, text: "After a ride: +1 gold.")
        case .busker:      return Info(emoji: "🎷", name: "Busker", atk: 1, hp: 3, tier: 2, text: "Start: all allies +1 attack.")
        case .preacher:    return Info(emoji: "📢", name: "Subway Preacher", atk: 2, hp: 4, tier: 2, text: "Start: front ally +3 hp.")
        case .courier:     return Info(emoji: "🚲", name: "Delivery Guy", atk: 4, hp: 2, tier: 2, text: "Start: hits the back enemy for 3.")
        case .conductor:   return Info(emoji: "🧢", name: "Conductor", atk: 3, hp: 5, tier: 3, text: "Start: all allies +1/+1. Stand clear.")
        case .ratKing:     return Info(emoji: "🐁", name: "Rat King", atk: 5, hp: 6, tier: 3, text: "Dies: two Pizza Rats.")
        }
    }
}

struct Unit: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: Kind
    var atk: Int
    var hp: Int
    var lv: Int = 1

    init(_ kind: Kind, lv: Int = 1) {
        self.kind = kind
        self.lv = lv
        atk = kind.info.atk * lv
        hp = kind.info.hp * lv
    }

    var emoji: String { kind.info.emoji }
    var name: String { kind.info.name }
}

/// A team someone else saved at a station. You fight these in the tunnel.
struct Ghost: Codable, Hashable {
    var player: String
    var line: String
    var round: Int
    var team: [Unit]
}

// MARK: - Deterministic RNG, so a battle replays the same everywhere

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {   // splitmix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
