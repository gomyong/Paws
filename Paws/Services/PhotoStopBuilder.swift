import Foundation
import CoreLocation
import SwiftData

/// 사진 여러 장을 촬영 시각과 위치로 묶어 일정 초안을 만든다.
/// 여행 중엔 사진만 찍고, 저녁에 한 번에 정리하는 흐름을 위한 기능이다.
@MainActor
enum PhotoStopBuilder {
    /// 이 시간 이상 벌어지면 다른 일정으로 본다
    static let timeGap: TimeInterval = 60 * 60
    /// 이 거리 이상 떨어지면 다른 일정으로 본다
    static let distanceGap: CLLocationDistance = 500

    struct Cluster {
        var photos: [ImportedPhoto]

        var start: Date? { photos.first?.capturedAt }

        var coordinate: CLLocationCoordinate2D? {
            let located = photos.compactMap { photo -> CLLocationCoordinate2D? in
                guard let lat = photo.latitude, let lon = photo.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            guard !located.isEmpty else { return nil }
            let lat = located.map(\.latitude).reduce(0, +) / Double(located.count)
            let lon = located.map(\.longitude).reduce(0, +) / Double(located.count)
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        var timeZone: TimeZone {
            photos.lazy.compactMap(\.timeZone).first ?? .current
        }
    }

    static func cluster(_ photos: [ImportedPhoto]) -> [Cluster] {
        let dated = photos.filter { $0.capturedAt != nil }.sorted { $0.capturedAt! < $1.capturedAt! }
        let undated = photos.filter { $0.capturedAt == nil }
        var clusters: [Cluster] = []
        for photo in dated {
            guard var current = clusters.last, let last = current.photos.last,
                  let lastDate = last.capturedAt, let date = photo.capturedAt
            else {
                clusters.append(Cluster(photos: [photo]))
                continue
            }
            var split = date.timeIntervalSince(lastDate) > timeGap
            if !split,
               let a = current.coordinate,
               let lat = photo.latitude, let lon = photo.longitude {
                let distance = CLLocation(latitude: a.latitude, longitude: a.longitude)
                    .distance(from: CLLocation(latitude: lat, longitude: lon))
                split = distance > distanceGap
            }
            if split {
                clusters.append(Cluster(photos: [photo]))
            } else {
                current.photos.append(photo)
                clusters[clusters.count - 1] = current
            }
        }
        if !undated.isEmpty {
            clusters.append(Cluster(photos: undated))
        }
        return clusters
    }

    /// 묶음마다 일정을 만든다. 온라인이면 장소 이름을 역지오코딩으로 채운다.
    static func makeStops(from photos: [ImportedPhoto], in trip: Trip, fallbackDay: Day?, context: ModelContext) async -> [Stop] {
        var created: [Stop] = []
        for (index, group) in cluster(photos).enumerated() {
            let timeZone = group.timeZone
            let time = group.start ?? fallbackDay.map { DayMath.time(on: $0.date, hour: 12, minute: 0, in: timeZone) } ?? .now
            let day: Day
            if group.start == nil, let fallbackDay {
                day = fallbackDay
            } else {
                day = TripService.day(for: time, timeZone: timeZone, in: trip, context: context)
            }

            var name = "사진 기록 \(index + 1)"
            var address = ""
            if let coordinate = group.coordinate,
               let described = await LocationService.shared.describe(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) {
                name = described.name
                address = described.address
            }

            let stop = TripService.addStop(
                to: day,
                name: name,
                address: address,
                coordinate: group.coordinate,
                time: time,
                timeZoneID: timeZone.identifier,
                context: context
            )
            for photo in group.photos {
                PhotoFactory.attach(photo, to: stop, context: context)
            }
            created.append(stop)
        }
        try? context.save()
        return created
    }
}
