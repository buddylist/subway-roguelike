import SwiftUI

struct RunOverView: View {
    @EnvironmentObject var game: Game

    var body: some View {
        VStack(spacing: 16) {
            Text(game.madeItToTheEnd ? "🏁 End of the line" : game.swipes <= 0 ? "💀 Out of swipes" : "🚶 You got off")
                .font(.largeTitle.bold())
            if let line = game.line, let station = game.station {
                HStack { Bullet(line: line); Text(station.name).font(.title3) }
            }
            Text("\(game.stopsRidden) stops · \(game.wins) wins · round \(game.round)")
            HStack { ForEach(game.team) { UnitCard(unit: $0) } }
            Button("Swipe in again 🎫") { game.newRun() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
