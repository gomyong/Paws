import Foundation
import SwiftData
import CoreLocation

/// 일정. 사진·글·좌표·태그는 모두 일정 하나에 붙는다.
@Model
final class Stop {
    var placeName: String = ""
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    /// 절대 시각
    var timestamp: Date = Date.now
    /// 기록한 곳의 시간대. 귀국 후에도 현지 시각으로 보이게 한다.
    var timeZoneID: String = TimeZone.current.identifier
    var sortIndex: Int = 0
    /// [Block]을 JSON으로 저장한다.
    var bodyData: Data?
    /// 검색용 본문 평문 (bodyData에서 파생)
    var searchText: String = ""
    var coverPhotoID: UUID?
    var isFavorite: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    var day: Day?

    @Relationship(deleteRule: .cascade, inverse: \Photo.stop)
    var photos: [Photo]? = []

    @Relationship(inverse: \Tag.stops)
    var tags: [Tag]? = []

    init(placeName: String, timestamp: Date, timeZoneID: String) {
        self.placeName = placeName
        self.timestamp = timestamp
        self.timeZoneID = timeZoneID
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension Stop {
    var blocks: [Block] {
        get {
            guard let bodyData, let decoded = try? JSONDecoder().decode([Block].self, from: bodyData) else {
                return []
            }
            return decoded
        }
        set {
            bodyData = try? JSONEncoder().encode(newValue)
            searchText = newValue
                .map(\.plainText)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            updatedAt = .now
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        get {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        set {
            latitude = newValue?.latitude
            longitude = newValue?.longitude
        }
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .current
    }

    var displayName: String {
        placeName.isEmpty ? "이름 없는 장소" : placeName
    }

    var sortedPhotos: [Photo] {
        (photos ?? []).sorted {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return $0.createdAt < $1.createdAt
        }
    }

    func photo(withID id: UUID?) -> Photo? {
        guard let id else { return nil }
        return photos?.first { $0.uuid == id }
    }

    var coverPhoto: Photo? {
        photo(withID: coverPhotoID) ?? sortedPhotos.first
    }

    var tagNames: [String] {
        (tags ?? []).map(\.name).sorted()
    }

    var previewText: String {
        let flat = searchText.replacingOccurrences(of: "\n", with: " ")
        return String(flat.prefix(140))
    }

    var trip: Trip? { day?.trip }

    /// 휴지통에 있지 않고, 속한 여행도 휴지통에 있지 않은지
    var isLive: Bool {
        deletedAt == nil && day?.trip?.deletedAt == nil
    }
}
