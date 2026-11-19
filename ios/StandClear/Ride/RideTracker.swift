import CoreLocation
import Foundation
import Network

/// Raw things the phone notices. Live ones come from GPS + the network stack, mock ones from the debug panel.
enum RideSignal {
    case network(Bool)
    case location(lat: Double, lon: Double, accuracy: Double)
}

protocol RideSource: AnyObject {
    var onSignal: ((RideSignal) -> Void)? { get set }
    func start()
    func stop()
}

/// The real phone: CoreLocation for where you are, NWPathMonitor for whether you have signal.
final class LiveRideSource: NSObject, RideSource, CLLocationManagerDelegate {
    var onSignal: ((RideSignal) -> Void)?
    private let location = CLLocationManager()
    private var monitor: NWPathMonitor?

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        location.distanceFilter = 25
    }

    func start() {
        location.requestWhenInUseAuthorization()
        location.startUpdatingLocation()
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            DispatchQueue.main.async { self?.onSignal?(.network(up)) }
        }
        m.start(queue: DispatchQueue(label: "standclear.net"))
        monitor = m
    }

    func stop() {
        location.stopUpdatingLocation()
        monitor?.cancel()
        monitor = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        onSignal?(.location(lat: l.coordinate.latitude, lon: l.coordinate.longitude, accuracy: l.horizontalAccuracy))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Fake phone for testing on the couch. The debug panel calls `send`.
final class MockRideSource: RideSource {
    var onSignal: ((RideSignal) -> Void)?
    func start() {}
    func stop() {}
    func send(_ signal: RideSignal) { onSignal?(signal) }
}

/// Turns signals into "doors closed" / "doors open at station X" for the game.
///
/// Underground: losing signal means you're in a tunnel, getting it back means you're at the next stop.
/// Above ground (elevated lines): GPS fixes near a station move you there directly.
@MainActor
final class RideTracker: ObservableObject {
    @Published private(set) var online = true
    @Published private(set) var lastFix: CLLocation?
    @Published private(set) var usingMock = false
    @Published var autoRide = false { didSet { autoRideChanged() } }

    /// Ignore signal blips shorter than this (live only). Mock mode moves instantly.
    var minTunnelSeconds: TimeInterval { usingMock ? 0 : 20 }
    let arriveRadius: CLLocationDistance = 250

    weak var game: Game?
    private var source: RideSource = LiveRideSource()
    let mock = MockRideSource()
    private var tunnelStarted: Date?
    private var autoTimer: Timer?

    func start(game: Game) {
        self.game = game
        attach(LiveRideSource())
    }

    func useMock(_ on: Bool) {
        guard on != usingMock else { return }
        usingMock = on
        attach(on ? mock : LiveRideSource())
        if !on { autoRide = false }
    }

    private func attach(_ s: RideSource) {
        source.stop()
        source.onSignal = nil
        source = s
        s.onSignal = { [weak self] signal in
            Task { @MainActor in self?.handle(signal) }
        }
        s.start()
    }

    func handle(_ signal: RideSignal) {
        guard let game else { return }
        switch signal {
        case .network(let up):
            guard up != online else { return }
            online = up
            if !up, game.phase == .station {
                tunnelStarted = Date()
                game.depart()
            } else if up, game.phase == .tunnel {
                let elapsed = Date().timeIntervalSince(tunnelStarted ?? .distantPast)
                if elapsed >= minTunnelSeconds { game.arrive() }
            }

        case .location(let lat, let lon, let accuracy):
            let fix = CLLocation(latitude: lat, longitude: lon)
            lastFix = fix
            guard accuracy <= 200, let line = game.line, let idx = nearestIndex(on: line, to: fix) else { return }
            if game.phase == .tunnel {
                game.arrive(at: idx)
            } else if game.phase == .station, idx != game.stationIndex {
                // Above ground the signal never drops, so moving between stations is the ride.
                game.depart()
                game.arrive(at: idx)
            }
        }
    }

    /// Index of the closest station on `line` within the arrival radius.
    func nearestIndex(on line: Line, to fix: CLLocation, radius: CLLocationDistance? = nil) -> Int? {
        let r = radius ?? arriveRadius
        let best = line.stations.indices.min { a, b in
            distance(line.stations[a], fix) < distance(line.stations[b], fix)
        }
        guard let best, distance(line.stations[best], fix) <= r else { return nil }
        return best
    }

    /// For boarding: the closest station on any line, if you're near one.
    func nearestStation(radius: CLLocationDistance = 600) -> (Line, Int)? {
        guard let fix = lastFix else { return nil }
        var best: (Line, Int, CLLocationDistance)?
        for line in Line.all {
            for (i, s) in line.stations.enumerated() {
                let d = distance(s, fix)
                if d <= radius, d < (best?.2 ?? .infinity) { best = (line, i, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    private func distance(_ s: Station, _ fix: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: s.lat, longitude: s.lon).distance(from: fix)
    }

    // MARK: - Mock helpers

    func mockTeleport(to index: Int) {
        guard let s = game?.line?.stations[index] else { return }
        mock.send(.location(lat: s.lat, lon: s.lon, accuracy: 10))
    }

    /// Ride the line by itself: 6 s in each tunnel, 6 s at each station.
    private func autoRideChanged() {
        autoTimer?.invalidate()
        guard autoRide else { return }
        useMock(true)
        autoTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let game = self.game else { return }
                switch game.phase {
                case .station: self.mock.send(.network(false))
                case .tunnel: self.mock.send(.network(true))
                default: self.autoRide = false
                }
            }
        }
    }
}
