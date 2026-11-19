import SwiftUI

/// "Which train are you on?" No route planning: pick a line, we guess the station from GPS.
struct BoardingView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var tracker: RideTracker
    @State private var lineID = "L"
    @State private var stationIndex = 0
    @State private var heading: Heading = .south
    @State private var name = ""
    @State private var didGuess = false

    private var line: Line { Line.named(lineID) ?? Line.all[0] }

    var body: some View {
        Form {
            Section {
                Text("Stand Clear").font(.largeTitle.bold())
                Text("Get on a train. Every tunnel is a fight, every station is a shop. Get off whenever.")
                    .foregroundStyle(.secondary)
            }
            Section("You") {
                TextField("Your name (other riders see it)", text: $name)
                    .textInputAutocapitalization(.never)
            }
            Section("Which train are you on?") {
                HStack(spacing: 16) {
                    ForEach(Line.all) { l in
                        Button { lineID = l.id; stationIndex = 0 } label: {
                            Bullet(line: l, size: 46)
                                .overlay(Circle().stroke(.white, lineWidth: l.id == lineID ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Picker("Going toward", selection: $heading) {
                    Text(line.northLabel).tag(Heading.north)
                    Text(line.southLabel).tag(Heading.south)
                }
                .pickerStyle(.segmented)
            }
            Section(didGuess ? "You're at (from GPS)" : "Where are you?") {
                Picker("Station", selection: $stationIndex) {
                    ForEach(line.stations.indices, id: \.self) { i in Text(line.stations[i].name).tag(i) }
                }
            }
            Section {
                Button {
                    game.player = name.isEmpty ? "anon" : name
                    game.board(line: line, at: stationIndex, heading: heading)
                } label: {
                    Text("Swipe in 🎫").frame(maxWidth: .infinity).font(.headline)
                }
            }
        }
        .onAppear { name = game.player; guess() }
        .onChange(of: tracker.lastFix) { _, _ in guess() }
    }

    private func guess() {
        guard !didGuess, let found = tracker.nearestStation() else { return }
        lineID = found.0.id
        stationIndex = found.1
        didGuess = true
    }
}
