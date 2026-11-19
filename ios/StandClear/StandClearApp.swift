import SwiftUI

@main
struct StandClearApp: App {
    @StateObject private var ghosts: GhostClient
    @StateObject private var game: Game
    @StateObject private var tracker = RideTracker()

    init() {
        let g = GhostClient()
        _ghosts = StateObject(wrappedValue: g)
        _game = StateObject(wrappedValue: Game(ghosts: g))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .environmentObject(tracker)
                .environmentObject(ghosts)
                .preferredColorScheme(.dark)
                .onAppear { tracker.start(game: game) }
        }
    }
}
