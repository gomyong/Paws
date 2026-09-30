import SwiftUI
import MapKit

/// 지도에 올릴 일정 핀
struct StopPin: Identifiable {
    let stop: Stop
    let number: Int
    let coordinate: CLLocationCoordinate2D
    var dayIndex: Int = 0

    var id: PersistentIdentifierHashable { PersistentIdentifierHashable(stop) }

    /// Day 안의 일정을 시간순 번호로
    static func pins(for day: Day, dayIndex: Int = 0) -> [StopPin] {
        day.liveStops.enumerated().compactMap { index, stop in
            guard let coordinate = stop.coordinate else { return nil }
            return StopPin(stop: stop, number: index + 1, coordinate: coordinate, dayIndex: dayIndex)
        }
    }
}

/// SwiftData 모델을 식별자로 쓰기 위한 래퍼
struct PersistentIdentifierHashable: Hashable {
    let id: ObjectIdentifier

    init(_ object: AnyObject) {
        id = ObjectIdentifier(object)
    }
}

enum MapMath {
    /// 좌표들이 모두 들어오는 영역 (여백 포함)
    static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    static func position(for coordinates: [CLLocationCoordinate2D]) -> MapCameraPosition {
        region(for: coordinates).map { .region($0) } ?? .automatic
    }

    static func focus(_ coordinate: CLLocationCoordinate2D) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
    }
}

/// 시간순 번호가 적힌 원형 핀
struct NumberPin: View {
    let number: Int
    var color: Color = Theme.teal
    var selected = false

    var body: some View {
        Text("\(number)")
            .font(.system(size: selected ? 15 : 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: selected ? 34 : 28, height: selected ? 34 : 28)
            .background(color, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .animation(.snappy, value: selected)
    }
}

/// 여행 목록 머리의 작은 동선 지도 (누르면 여행 지도)
struct TripMiniMap: View {
    let trip: Trip

    var body: some View {
        let days = trip.sortedDays
        let allPins = days.enumerated().flatMap { index, day in StopPin.pins(for: day, dayIndex: index) }
        Map(initialPosition: MapMath.position(for: allPins.map(\.coordinate)), interactionModes: []) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let coords = StopPin.pins(for: day).map(\.coordinate)
                if coords.count > 1 {
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.dayColor(index), lineWidth: 3)
                }
            }
            ForEach(allPins) { pin in
                Annotation("", coordinate: pin.coordinate) {
                    Circle()
                        .fill(Theme.dayColor(pin.dayIndex))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
