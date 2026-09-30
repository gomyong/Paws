import Foundation
import CoreLocation
import MapKit

/// 장소 선택 결과 (검색, 현재 위치, 지도 핀)
struct PlaceSelection: Hashable, Identifiable {
    var id = UUID()
    var name: String
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var timeZoneID: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, address: String = "", coordinate: CLLocationCoordinate2D?, timeZoneID: String? = nil) {
        self.name = name
        self.address = address
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.timeZoneID = timeZoneID
    }
}

/// 위치는 일정을 만들 때 한 번만 조회한다. 백그라운드 추적은 하지 않는다.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// 1분 이내의 위치가 있으면 그대로 쓰고, 없으면 한 번 조회한다. 10초가 넘으면 nil.
    func currentLocation() async -> CLLocation? {
        #if DEBUG
        if let mock = LaunchOptions.mockPlace, let coordinate = mock.coordinate {
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        #endif
        if let recent = manager.location, abs(recent.timestamp.timeIntervalSinceNow) < 60 {
            return recent
        }
        if isDenied { return nil }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            if waiters.count == 1 {
                start()
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finish(with: self?.manager.location)
            }
        }
    }

    private func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            finish(with: nil)
        }
    }

    private func finish(with location: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard !self.waiters.isEmpty else { return }
            switch self.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.finish(with: nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(with: last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(with: nil) }
    }

    /// 좌표 → 장소 이름과 주소. 오프라인이면 nil.
    func describe(_ location: CLLocation) async -> PlaceSelection? {
        if geocoder.isGeocoding { geocoder.cancelGeocode() }
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ko_KR")).first else {
            return nil
        }
        let name = placemark.areasOfInterest?.first
            ?? placemark.name
            ?? placemark.subLocality
            ?? placemark.locality
            ?? "현재 위치"
        let address = [placemark.locality, placemark.subLocality, placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        return PlaceSelection(
            name: name,
            address: address,
            coordinate: location.coordinate,
            timeZoneID: placemark.timeZone?.identifier
        )
    }

    /// 현재 위치를 장소로. 역지오코딩이 안 되면(오프라인) 좌표만 담는다.
    func currentPlace() async -> PlaceSelection? {
        #if DEBUG
        if let mock = LaunchOptions.mockPlace { return mock }
        #endif
        guard let location = await currentLocation() else { return nil }
        if let described = await describe(location) {
            return described
        }
        return PlaceSelection(name: "현재 위치", coordinate: location.coordinate, timeZoneID: TimeZone.current.identifier)
    }
}

/// Apple Maps 장소 검색
enum PlaceSearch {
    static func search(_ query: String, near region: MKCoordinateRegion?) async -> [PlaceSelection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]
        if let region {
            request.region = region
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.map { item in
            PlaceSelection(
                name: item.name ?? trimmed,
                address: item.placemark.title ?? "",
                coordinate: item.placemark.coordinate,
                timeZoneID: item.timeZone?.identifier
            )
        }
    }
}
