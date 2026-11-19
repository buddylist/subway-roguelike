import SwiftUI

/// Fake the subway from your couch: drop signal, get it back, teleport between stations, or auto-ride.
struct DebugPanel: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var tracker: RideTracker
    @EnvironmentObject var ghosts: GhostClient
    @State private var target = 0

    var body: some View {
        Form {
            Section {
                Toggle("Mock ride (ignore real GPS and signal)", isOn: Binding(get: { tracker.usingMock }, set: { tracker.useMock($0) }))
                Toggle("Auto-ride (every 6 s)", isOn: $tracker.autoRide)
            }
            Section("Signal") {
                HStack {
                    Button("📵 Lose signal") { tracker.mock.send(.network(false)) }
                    Spacer()
                    Button("📶 Signal back") { tracker.mock.send(.network(true)) }
                }
                .buttonStyle(.bordered)
                .disabled(!tracker.usingMock)
            }
            if let line = game.line {
                Section("Teleport (fake GPS fix)") {
                    Picker("Station", selection: $target) {
                        ForEach(line.stations.indices, id: \.self) { Text(line.stations[$0].name).tag($0) }
                    }
                    Button("Go") { tracker.mockTeleport(to: target) }.disabled(!tracker.usingMock)
                }
            }
            Section("State") {
                LabeledContent("Phase", value: "\(game.phase)")
                LabeledContent("Online", value: tracker.online ? "yes" : "no")
                LabeledContent("Backend", value: ghosts.baseURL?.host() ?? "not set (bots only)")
                if let e = ghosts.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                if let fix = tracker.lastFix {
                    LabeledContent("Last fix", value: String(format: "%.5f, %.5f", fix.coordinate.latitude, fix.coordinate.longitude))
                }
            }
        }
        .onAppear { target = game.stationIndex }
    }
}
