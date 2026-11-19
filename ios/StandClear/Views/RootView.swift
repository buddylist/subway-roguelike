import SwiftUI

struct RootView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var tracker: RideTracker
    @State private var showDebug = false

    var body: some View {
        NavigationStack {
            Group {
                switch game.phase {
                case .boarding: BoardingView()
                case .station: StationView()
                case .tunnel: TunnelView()
                case .over: RunOverView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDebug = true } label: {
                        Image(systemName: tracker.usingMock ? "ladybug.fill" : "ladybug")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: tracker.online ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(tracker.online ? .green : .red)
                }
            }
        }
        .sheet(isPresented: $showDebug) { DebugPanel().presentationDetents([.medium, .large]) }
    }
}
