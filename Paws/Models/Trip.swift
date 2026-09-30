import Foundation
import SwiftData

/// 여행. CloudKit 동기화를 위해 모든 속성은 기본값이 있거나 옵셔널이다.
@Model
final class Trip {
    var title: String = ""
    var emoji: String = "✈️"
    /// 달력 날짜. DayMath.normalize로 UTC 정오에 맞춰 저장한다.
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    @Attribute(.externalStorage) var coverImageData: Data?
    var isPinned: Bool = false
    var createdAt: Date = Date.now
    /// 휴지통으로 옮긴 시각. nil이면 살아 있는 여행이다.
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Day.trip)
    var days: [Day]? = []

    init(title: String, emoji: String, startDate: Date, endDate: Date) {
        self.title = title
        self.emoji = emoji
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = .now
    }
}

extension Trip {
    var sortedDays: [Day] {
        (days ?? []).sorted { $0.date < $1.date }
    }

    var liveStops: [Stop] {
        sortedDays.flatMap(\.liveStops)
    }

    var displayTitle: String {
        title.isEmpty ? "제목 없는 여행" : title
    }

    /// 1부터 시작하는 Day 번호
    func dayNumber(of day: Day) -> Int {
        (sortedDays.firstIndex { $0 === day } ?? 0) + 1
    }

    func contains(date: Date) -> Bool {
        let key = DayMath.normalize(date)
        return key >= startDate && key <= endDate
    }
}
