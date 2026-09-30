import Foundation
import SwiftData

@Model
final class Day {
    /// 달력 날짜 (UTC 정오로 정규화)
    var date: Date = Date.now
    var title: String = ""
    var emoji: String = ""
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \Stop.day)
    var stops: [Stop]? = []

    init(date: Date) {
        self.date = date
    }
}

extension Day {
    /// 휴지통에 없는 일정을 정렬 순서대로
    var liveStops: [Stop] {
        (stops ?? [])
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
                return $0.timestamp < $1.timestamp
            }
    }

    var number: Int {
        trip?.dayNumber(of: self) ?? 1
    }

    /// "🍜 Day 3 · 교토"
    var headline: String {
        var text = "Day \(number)"
        if !title.isEmpty { text += " · \(title)" }
        if !emoji.isEmpty { text = "\(emoji) " + text }
        return text
    }
}
