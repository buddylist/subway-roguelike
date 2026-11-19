import SwiftUI

struct TunnelView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var tracker: RideTracker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let line = game.line, let leg = game.current {
                HStack {
                    Bullet(line: line)
                    VStack(alignment: .leading) {
                        Text("\(leg.from) → \(leg.to)").font(.headline)
                        Text("in the tunnel vs \(leg.opponent.player)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Hud()
                BattlePlayback(leg: leg, autoplay: true)
                Spacer()
                Text(tracker.online ? "Waiting for the doors…" : "No signal. The doors open when it comes back.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("🚪 Doors open (arrive now)") { game.arrive() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

/// Plays a battle's frames back one by one.
struct BattlePlayback: View {
    let leg: Game.LegRecap
    var autoplay = true
    @State private var step = 0
    private let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()

    private var frames: [BattleFrame] { leg.result.frames }
    private var frame: BattleFrame? { frames.isEmpty ? nil : frames[min(step, frames.count - 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(leg.opponent.player).font(.caption).foregroundStyle(.secondary)
            row(frame?.theirs ?? leg.opponent.team)
            Text("⚔️").frame(maxWidth: .infinity)
            row(frame?.ours ?? [])
            Text("You").font(.caption).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(frames.prefix(step + 1)) { f in
                            Text(f.text).font(.system(.caption, design: .monospaced)).id(f.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black))
                .onChange(of: step) { _, s in withAnimation { proxy.scrollTo(min(s, frames.count - 1)) } }
            }
        }
        .onReceive(timer) { _ in
            if autoplay && step < frames.count - 1 { withAnimation { step += 1 } }
        }
    }

    private func row(_ units: [Unit]) -> some View {
        ScrollView(.horizontal) {
            HStack { ForEach(units) { UnitCard(unit: $0) } }
        }
    }
}
