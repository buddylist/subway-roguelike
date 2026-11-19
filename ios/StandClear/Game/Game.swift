import Foundation

/// One run: you board a train, fight in every tunnel, shop at every station, get off whenever.
@MainActor
final class Game: ObservableObject {
    enum Phase: Equatable { case boarding, station, tunnel, over }

    struct Offer: Identifiable {
        let id = UUID()
        var unit: Unit
        var price: Int
        var mystery = false
    }

    struct LegRecap {
        let from: String
        let to: String
        let opponent: Ghost
        let result: BattleResult
    }

    @Published private(set) var phase: Phase = .boarding
    @Published private(set) var line: Line?
    @Published private(set) var heading: Heading = .south
    @Published private(set) var stationIndex = 0
    @Published private(set) var gold = 0
    @Published private(set) var swipes = 3
    @Published private(set) var team: [Unit] = []
    @Published private(set) var shop: [Offer] = []
    @Published private(set) var round = 0            // battles fought this run
    @Published private(set) var wins = 0
    @Published private(set) var stopsRidden = 0
    @Published private(set) var current: LegRecap?    // the fight in this tunnel
    @Published private(set) var lastLeg: LegRecap?    // the fight you just finished
    @Published private(set) var madeItToTheEnd = false

    let ghosts: GhostClient
    init(ghosts: GhostClient) { self.ghosts = ghosts }

    static let maxTeam = 5
    static let unitCost = 3

    var player: String {
        get { UserDefaults.standard.string(forKey: "player") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "player"); objectWillChange.send() }
    }

    var station: Station? { line?.stations[stationIndex] }
    var nextIndex: Int? {
        guard let line else { return nil }
        let n = stationIndex + heading.rawValue
        return line.stations.indices.contains(n) ? n : nil
    }
    var nextStation: Station? { nextIndex.flatMap { line?.stations[$0] } }
    var towardLabel: String {
        guard let line else { return "" }
        return heading == .north ? line.northLabel : line.southLabel
    }

    // MARK: - Run lifecycle

    func board(line: Line, at index: Int, heading: Heading) {
        self.line = line
        self.stationIndex = index
        self.heading = heading
        // At a terminus there's only one way to go.
        if nextIndex == nil { self.heading = heading == .north ? .south : .north }
        gold = 0; swipes = 3; team = []; round = 0; wins = 0; stopsRidden = 0
        current = nil; lastLeg = nil; madeItToTheEnd = false
        phase = .station
        enterStation()
    }

    func getOff() {
        guard phase == .station || phase == .tunnel else { return }
        finish(madeIt: false)
    }

    func newRun() { phase = .boarding }

    // MARK: - Moving (called by RideTracker, or by the manual buttons)

    /// Doors close: pick an opponent and simulate the fight. The view plays it back during the ride.
    func depart() {
        guard phase == .station, let line, let station, let next = nextStation else { return }
        round += 1
        let seed = UInt64(bitPattern: Int64(station.id.hashValue)) &+ UInt64(round) &* 7919 &+ UInt64(Date().timeIntervalSince1970)
        let opponent = ghosts.takeGhost(line: line.id, round: round, notFrom: player)
            ?? LocalGhosts.make(line: line.id, round: round, seed: seed)
        let result = Battle.run(ours: team, theirs: opponent.team, seed: seed)
        current = LegRecap(from: station.name, to: next.name, opponent: opponent, result: result)
        phase = .tunnel
    }

    /// Doors open. `index` is where GPS says we are; nil means "the next stop".
    func arrive(at index: Int? = nil) {
        guard phase == .tunnel, let line, let leg = current else { return }
        let target = index ?? nextIndex ?? stationIndex
        if target != stationIndex { heading = target > stationIndex ? .south : .north }
        stopsRidden += max(1, abs(target - stationIndex))
        stationIndex = target

        switch leg.result.outcome {
        case .win:
            wins += 1
            gold += leg.result.goldAfter
            ghosts.claimTurf(line: line.id, station: line.stations[target], player: player, team: team)
        case .loss:
            swipes -= 1
        case .draw:
            break
        }
        lastLeg = leg
        current = nil

        if swipes <= 0 { finish(madeIt: false); return }
        if nextIndex == nil { finish(madeIt: true); return }
        phase = .station
        enterStation()
    }

    private func finish(madeIt: Bool) {
        madeItToTheEnd = madeIt
        phase = .over
        if let line, let station {
            ghosts.postRun(line: line.id, endedAt: station.name, player: player, wins: wins, stops: stopsRidden, madeIt: madeIt, team: team)
        }
    }

    // MARK: - Station / shop

    private func enterStation() {
        guard let line, let station else { return }
        gold += 10
        switch station.trait {
        case .chaos: gold += 3
        case .express: gold += 4
        case .lastStop: swipes = min(3, swipes + 1)
        case .foodCourt: for i in team.indices { team[i].hp += 1 }
        default: break
        }
        restock()
        // Save this team so other riders can fight it, and look ahead while we have signal.
        if !team.isEmpty {
            ghosts.upload(Ghost(player: player, line: line.id, round: round + 1, team: team))
        }
        ghosts.prefetch(line: line.id, rounds: (round + 1)...(round + 6))
        ghosts.loadTurf(line: line.id)
    }

    private var slots: Int {
        switch station?.trait ?? .dollarSlice {
        case .transferHub: 6
        case .express: 3
        default: 4
        }
    }

    private func price(for trait: Trait) -> Int {
        switch trait {
        case .dollarSlice: Self.unitCost - 1
        case .luxury: Self.unitCost + 1
        case .knockoffs: 1
        default: Self.unitCost
        }
    }

    private func restock() {
        guard let trait = station?.trait else { return }
        let tier = min(3, 1 + round / 3)
        let pool = Kind.allCases.filter { $0.info.tier >= 1 && $0.info.tier <= tier && $0 != .cat }
        shop = (0..<slots).map { _ in
            var u = Unit(pool.randomElement()!)
            if trait == .luxury { u.atk += 1; u.hp += 1 }
            if trait == .knockoffs { u.hp = max(1, u.hp - 1) }
            return Offer(unit: u, price: price(for: trait), mystery: trait == .thrift)
        }
        if trait == .bodega || Int.random(in: 0..<10) == 0 {
            shop[0] = Offer(unit: Unit(.cat), price: price(for: trait))
        }
        if trait == .thrift, let i = shop.indices.randomElement() { shop[i].price = 0 }
    }

    func canBuy(_ offer: Offer) -> Bool {
        gold >= offer.price && (team.count < Self.maxTeam || team.contains { $0.kind == offer.unit.kind })
    }

    func buy(_ offer: Offer) {
        guard phase == .station, canBuy(offer), let i = shop.firstIndex(where: { $0.id == offer.id }) else { return }
        gold -= offer.price
        shop.remove(at: i)
        if let j = team.firstIndex(where: { $0.kind == offer.unit.kind }) {
            team[j].lv += 1; team[j].atk += 1; team[j].hp += 1
        } else {
            team.append(offer.unit)
        }
        if station?.trait == .chaos { restock() }
    }

    func sell(_ unit: Unit) {
        guard phase == .station, let i = team.firstIndex(of: unit) else { return }
        gold += unit.lv
        team.remove(at: i)
    }

    func moveForward(_ unit: Unit) {
        guard let i = team.firstIndex(of: unit), i > 0 else { return }
        team.swapAt(i, i - 1)
    }

    var rerollCost: Int { station?.trait == .freeTransfer ? 0 : 1 }

    func reroll() {
        guard phase == .station, gold >= rerollCost else { return }
        gold -= rerollCost
        restock()
    }
}
