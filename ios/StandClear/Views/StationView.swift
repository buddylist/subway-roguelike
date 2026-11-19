import SwiftUI

struct StationView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var ghosts: GhostClient
    @State private var replay: Game.LegRecap?

    var body: some View {
        if let line = game.line, let station = game.station {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Bullet(line: line)
                        VStack(alignment: .leading) {
                            Text(station.name).font(.title2.bold())
                            Text("toward \(game.towardLabel) · next: \(game.nextStation?.name ?? "end of the line")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Hud()

                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.trait.title).font(.headline)
                        Text(station.trait.blurb).font(.subheadline).foregroundStyle(.secondary)
                        if let owner = ghosts.turf[station.id] {
                            Text("👑 \(owner) holds this station").font(.subheadline)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: line.colorHex).opacity(0.18)))

                    if let leg = game.lastLeg {
                        Button { replay = leg } label: {
                            Text("Last leg: \(leg.result.outcome.rawValue.uppercased()) vs \(leg.opponent.player) · replay")
                                .font(.footnote)
                        }
                    }

                    Text("Shop").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                        ForEach(game.shop) { offer in
                            VStack(spacing: 4) {
                                UnitCard(unit: offer.unit, mystery: offer.mystery)
                                Button(offer.price == 0 ? "FREE" : "$\(offer.price)") { game.buy(offer) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!game.canBuy(offer))
                            }
                        }
                    }
                    Button("🔄 Reroll (\(game.rerollCost == 0 ? "free" : "$\(game.rerollCost)"))") { game.reroll() }
                        .disabled(game.gold < game.rerollCost)

                    Text("Your crew (front first) \(game.team.count)/\(Game.maxTeam)").font(.headline)
                    if game.team.isEmpty {
                        Text("Nobody yet. Buy someone before the doors close.").foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(game.team) { u in
                                VStack(spacing: 4) {
                                    UnitCard(unit: u)
                                    HStack(spacing: 4) {
                                        Button { game.moveForward(u) } label: { Image(systemName: "arrow.left") }
                                        Button("$\(u.lv)") { game.sell(u) }
                                    }
                                    .font(.caption).buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    Text("The fight starts when you lose signal. Above ground or on wifi, ride manually:")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("🚪 Stand clear, ride now") { game.depart() }
                            .buttonStyle(.borderedProminent)
                            .disabled(game.nextStation == nil)
                        Button("Get off") { game.getOff() }.buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .sheet(item: Binding(get: { replay.map(ReplayItem.init) }, set: { replay = $0?.leg })) { item in
                BattlePlayback(leg: item.leg, autoplay: true).padding()
            }
        }
    }
}

private struct ReplayItem: Identifiable {
    let leg: Game.LegRecap
    var id: String { leg.from + leg.to + leg.opponent.player }
}
