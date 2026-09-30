import Foundation

/// 달력 날짜 계산.
/// 여행 날짜와 Day 날짜는 "어느 나라에서 보든 같은 날"이어야 하므로
/// 달력 날짜를 UTC 정오의 Date로 정규화해서 저장한다.
enum DayMath {
    static let utc = TimeZone(identifier: "UTC")!

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()

    /// 주어진 시간대에서 본 date의 달력 날짜 → UTC 정오
    static func normalize(_ date: Date, in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return utcCalendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)) ?? date
    }

    /// 정규화된 날짜 → 현재 시간대의 같은 달력 날짜 (DatePicker 바인딩용)
    static func localDate(from normalized: Date) -> Date {
        let parts = utcCalendar.dateComponents([.year, .month, .day], from: normalized)
        return Calendar.current.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)) ?? normalized
    }

    /// start...end의 모든 달력 날짜 (둘 다 정규화된 값)
    static func days(from start: Date, to end: Date) -> [Date] {
        guard start <= end else { return [start] }
        var result: [Date] = []
        var cursor = start
        while cursor <= end, result.count < 366 {
            result.append(cursor)
            guard let next = utcCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// 정규화된 날짜 day에서, 시간대 tz의 hour:minute 시각
    static func time(on day: Date, hour: Int, minute: Int, in timeZone: TimeZone) -> Date {
        let parts = utcCalendar.dateComponents([.year, .month, .day], from: day)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: hour, minute: minute)) ?? day
    }
}

/// 한국어 날짜·시각 표시
enum Fmt {
    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static let dayFormatter = formatter("M월 d일 (E)", timeZone: DayMath.utc)
    private static let fullDayFormatter = formatter("yyyy년 M월 d일 (E)", timeZone: DayMath.utc)
    private static let rangeStart = formatter("yyyy. M. d", timeZone: DayMath.utc)
    private static let rangeEndSameYear = formatter("M. d", timeZone: DayMath.utc)
    private static let isoDay = formatter("yyyy-MM-dd", timeZone: DayMath.utc)

    /// "10월 3일 (금)"
    static func day(_ normalized: Date) -> String {
        dayFormatter.string(from: normalized)
    }

    /// "2026년 10월 3일 (금)"
    static func fullDay(_ normalized: Date) -> String {
        fullDayFormatter.string(from: normalized)
    }

    /// "2026-10-03"
    static func iso(_ normalized: Date) -> String {
        isoDay.string(from: normalized)
    }

    /// "2026. 10. 1 – 10. 5"
    static func range(_ start: Date, _ end: Date) -> String {
        if start == end { return rangeStart.string(from: start) }
        let sameYear = DayMath.utcCalendar.component(.year, from: start) == DayMath.utcCalendar.component(.year, from: end)
        let endText = sameYear ? rangeEndSameYear.string(from: end) : rangeStart.string(from: end)
        return "\(rangeStart.string(from: start)) – \(endText)"
    }

    /// 기록한 곳의 현지 시각. "오후 3:05"
    static func time(_ date: Date, timeZoneID: String) -> String {
        let timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return formatter("a h:mm", timeZone: timeZone).string(from: date)
    }

    /// 현지 시간대가 지금 기기의 시간대와 다르면 "GMT+9" 같은 표시
    static func timeZoneBadge(_ timeZoneID: String, at date: Date) -> String? {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return nil }
        if timeZone.secondsFromGMT(for: date) == TimeZone.current.secondsFromGMT(for: date) { return nil }
        return timeZone.abbreviation(for: date) ?? timeZone.identifier
    }
}
