import Foundation
import CoreLocation
import Network

/// Turns phone signals into ride events. Underground you lose signal between stations,
/// so "lost network" means the train left and "got it back" means you pulled into the next stop.
/// Above ground GPS works, so we use distance to the nearest station on your line instead.
/// Real sensors and the debug panel both feed `handle(_:)`, so everything can be tested from the couch.
enum RideSignal {
    case location(lat: Double, lon: Double, speed: Double)   // speed in m/s, negative if unknown
    case network(online: Bool)
    case forceDepart
    case forceArrive(stationId: String?)                     // nil = next stop
}

enum RideEvent {
    case departed(fromIndex: Int)
    case arrived(atIndex: Int)
}

final class RideTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var online = true
    @Published private(set) var lastFix: CLLocationCoordinate2D?
    @Published private(set) var inTransit = false
    @Published var mockMode = false { didSet { if mockMode { stopSensors() } else { startSensors() } } }

    var onEvent: ((RideEvent) -> Void)?

    private(set) var stops: [Station] = []
    private(set) var index = 0
    private(set) var direction = 1
    private let location = CLLocationManager()
    private var monitor: NWPathMonitor?
    private var arriveTimer: Timer?

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        location.activityType = .otherNavigation
    }

    func begin(stops: [Station], startIndex: Int, direction: Int) {
        self.stops = stops; index = startIndex; self.direction = direction; inTransit = false
        if !mockMode { startSensors() }
    }

    func end() { stopSensors(); stops = [] }

    // MARK: sensors

    func startSensors() {
        location.requestWhenInUseAuthorization()
        location.allowsBackgroundLocationUpdates = location.authorizationStatus == .authorizedAlways
        location.startUpdatingLocation()
        if monitor == nil {
            let m = NWPathMonitor()
            m.pathUpdateHandler = { [weak self] path in
                DispatchQueue.main.async { self?.handle(.network(online: path.status == .satisfied)) }
            }
            m.start(queue: DispatchQueue(label: "net"))
            monitor = m
        }
    }

    func stopSensors() {
        location.stopUpdatingLocation()
        monitor?.cancel(); monitor = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !mockMode, let l = locations.last, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 200 else { return }
        handle(.location(lat: l.coordinate.latitude, lon: l.coordinate.longitude, speed: l.speed))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if !mockMode && !stops.isEmpty { manager.startUpdatingLocation() }
    }

    // MARK: the logic

    func handle(_ signal: RideSignal) {
        guard !stops.isEmpty else {
            if case .network(let on) = signal { online = on }
            if case .location(let lat, let lon, _) = signal { lastFix = .init(latitude: lat, longitude: lon) }
            return
        }
        switch signal {
        case .network(let on):
            let was = online
            online = on
            if was && !on && !inTransit { depart() }
            if !was && on && inTransit {
                // Signal's back: we're at the next stop, unless GPS says otherwise in the next few seconds.
                arriveTimer?.invalidate()
                arriveTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                    guard let self, self.inTransit else { return }
                    self.arrive(self.index + self.direction)
                }
            }
        case .location(let lat, let lon, let speed):
            lastFix = .init(latitude: lat, longitude: lon)
            let near = stops.indices.map { ($0, distance(lat, lon, stops[$0].lat, stops[$0].lon)) }.min { $0.1 < $1.1 }
            guard let (i, d) = near else { return }
            let slow = speed < 4   // also true when unknown (-1)
            if inTransit && d < 150 && slow && i != index && isAhead(i) {
                arrive(i)
            } else if !inTransit && distance(lat, lon, stops[index].lat, stops[index].lon) > 350 {
                depart()
            }
        case .forceDepart:
            if !inTransit { depart() }
        case .forceArrive(let id):
            if !inTransit { depart() }
            let target = id.flatMap { sid in stops.firstIndex { $0.id == sid } } ?? (index + direction)
            arrive(target)
        }
    }

    private func isAhead(_ i: Int) -> Bool { direction > 0 ? i > index : i < index }

    private func depart() {
        guard stops.indices.contains(index + direction) else { return }   // end of the line
        inTransit = true
        onEvent?(.departed(fromIndex: index))
    }

    private func arrive(_ i: Int) {
        arriveTimer?.invalidate()
        let clamped = max(0, min(stops.count - 1, i))
        guard inTransit else { return }
        inTransit = false
        index = clamped
        onEvent?(.arrived(atIndex: clamped))
    }
}

/// Meters between two coordinates (haversine). Good enough for "am I at this station".
func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6_371_000.0, p = Double.pi / 180
    let dLat = (lat2 - lat1) * p, dLon = (lon2 - lon1) * p
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * p) * cos(lat2 * p) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(min(1, sqrt(a)))
}
