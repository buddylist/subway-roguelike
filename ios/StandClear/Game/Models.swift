import Foundation

// MARK: - Map

struct Station: Identifiable, Hashable, Codable {
    let id: String          // GTFS stop id, e.g. "L08"
    let name: String
    let lat: Double
    let lon: Double
    let aboveGround: Bool   // elevated / at grade: you'll usually have signal here
    let trait: Trait
}

struct Line: Identifiable, Hashable {
    let id: String          // "L"
    let name: String
    let colorHex: UInt32
    let northLabel: String
    let southLabel: String
    let stations: [Station]

    static func named(_ id: String) -> Line? { all.first { $0.id == id } }
}

enum Direction: String, Codable { case north, south }

/// Every station's shop has a personality.
enum Trait: String, Codable, CaseIterable {
    case dollarSlice, luxury, transferHub, freeTransfer, thrift, bodega, lastStop, chaos, knockoffs, express, foodCourt

    var title: String {
        switch self {
        case .dollarSlice: "Dollar Slice"
        case .luxury: "Luxury Condos"
        case .transferHub: "Transfer Hub"
        case .freeTransfer: "Free Transfer"
        case .thrift: "Thrift Store"
        case .bodega: "Bodega"
        case .lastStop: "Last Stop"
        case .chaos: "Total Chaos"
        case .knockoffs: "Knockoffs"
        case .express: "Express Stop"
        case .foodCourt: "Food Court"
        }
    }

    var blurb: String {
        switch self {
        case .dollarSlice: "Everything costs 1 less."
        case .luxury: "Prices +1, but everyone comes with +1/+1."
        case .transferHub: "Six slots instead of four."
        case .freeTransfer: "Rerolls are free."
        case .thrift: "Mystery boxes. One of them is free."
        case .bodega: "There's always a Bodega Cat."
        case .lastStop: "Get a swipe back."
        case .chaos: "+3 coins. The shop reshuffles every time you buy."
        case .knockoffs: "Everything costs 1. Everything has -1 HP."
        case .express: "+4 coins, only three slots."
        case .foodCourt: "Your whole crew gets +1 HP, for good."
        }
    }
}

// MARK: - Units

enum Ability: String, Codable {
    case none
    case hurtRage          // when hurt and alive: +2 atk per level
    case dieSlice          // dies: leaves a 2/2 Slice
    case startKick         // start: 2 dmg to random enemy
    case afterGold         // after battle: +1 coin per level
    case startTeamAtk      // start: allies +1 atk per level
    case startBlessFront   // start: front ally +3 hp per level
    case startSnipeBack    // start: 3 dmg to the back enemy
    case startTeamBuff     // start: allies +1/+1 per level
    case dieRats           // dies: two Pizza Rats
    case tank              // takes 1 less damage (min 1)
}

struct UnitKind: Codable, Hashable {
    let key: String
    let emoji: String
    let name: String
    let atk: Int
    let hp: Int
    let tier: Int          // 0 = never in shops
    let ability: Ability
    let text: String

    static let catalog: [UnitKind] = [
        .init(key: "cat", emoji: "🐈", name: "Bodega Cat", atk: 2, hp: 3, tier: 1, ability: .hurtRage, text: "Hurt: +2 attack."),
        .init(key: "rat", emoji: "🐀", name: "Pizza Rat", atk: 1, hp: 2, tier: 1, ability: .dieSlice, text: "Dies: leaves a 2/2 Slice."),
        .init(key: "slice", emoji: "🍕", name: "Slice", atk: 2, hp: 2, tier: 0, ability: .none, text: "Still warm."),
        .init(key: "dancer", emoji: "🕺", name: "Showtime Dancer", atk: 2, hp: 2, tier: 1, ability: .startKick, text: "Start: kicks a random enemy for 2."),
        .init(key: "spreader", emoji: "🧍", name: "Manspreader", atk: 1, hp: 6, tier: 1, ability: .tank, text: "Takes 1 less damage."),
        .init(key: "swiper", emoji: "💳", name: "MetroCard Swiper", atk: 1, hp: 3, tier: 1, ability: .afterGold, text: "After a fight: +1 coin."),
        .init(key: "busker", emoji: "🎷", name: "Busker", atk: 1, hp: 3, tier: 2, ability: .startTeamAtk, text: "Start: allies +1 attack."),
        .init(key: "preacher", emoji: "📢", name: "Subway Preacher", atk: 2, hp: 4, tier: 2, ability: .startBlessFront, text: "Start: front ally +3 HP."),
        .init(key: "courier", emoji: "🚲", name: "Delivery Guy", atk: 4, hp: 2, tier: 2, ability: .startSnipeBack, text: "Start: hits the back enemy for 3."),
        .init(key: "conductor", emoji: "🧢", name: "Conductor", atk: 3, hp: 5, tier: 3, ability: .startTeamBuff, text: "Start: allies +1/+1. Stand clear."),
        .init(key: "ratking", emoji: "👑", name: "Rat King", atk: 5, hp: 6, tier: 3, ability: .dieRats, text: "Dies: two Pizza Rats."),
    ]
    static func get(_ key: String) -> UnitKind { catalog.first { $0.key == key }! }
}

struct Unit: Codable, Hashable, Identifiable {
    var id = UUID()
    let key: String
    var atk: Int
    var hp: Int
    var level = 1
    var mystery = false    // thrift store: stats hidden until bought
    var free = false

    init(_ key: String, level: Int = 1) {
        let k = UnitKind.get(key)
        self.key = key; self.atk = k.atk * level; self.hp = k.hp * level; self.level = level
    }
    var kind: UnitKind { UnitKind.get(key) }
}

/// What gets uploaded and fought as a ghost. Small on purpose: it has to fit through a flaky connection.
struct Team: Codable, Hashable {
    var player: String
    var units: [Unit]
}
