import Foundation
import SwiftData
import SwiftUI
import CoreLocation

/// 여행·Day·일정의 생성, 정렬, 휴지통 처리
@MainActor
enum TripService {
    static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    // MARK: 여행

    @discardableResult
    static func createTrip(title: String, emoji: String, start: Date, end: Date, cover: Data?, context: ModelContext) -> Trip {
        let trip = Trip(title: title, emoji: emoji, startDate: start, endDate: max(start, end))
        trip.coverImageData = cover
        context.insert(trip)
        syncDays(for: trip, context: context)
        return trip
    }

    /// 기간에 맞춰 Day를 만든다. 기간 밖으로 밀려난 빈 Day는 지우고, 기록이 있는 Day는 남긴다.
    static func syncDays(for trip: Trip, context: ModelContext) {
        let existing = Set((trip.days ?? []).map(\.date))
        for date in DayMath.days(from: trip.startDate, to: trip.endDate) where !existing.contains(date) {
            let day = Day(date: date)
            context.insert(day)
            day.trip = trip
        }
        for day in Array(trip.days ?? []) where day.date < trip.startDate || day.date > trip.endDate {
            if (day.stops ?? []).isEmpty {
                context.delete(day)
            }
        }
    }

    /// 날짜에 해당하는 Day. 없으면 만든다 (여행 기간 밖의 소급 기록도 받는다).
    static func day(for date: Date, timeZone: TimeZone, in trip: Trip, context: ModelContext) -> Day {
        let key = DayMath.normalize(date, in: timeZone)
        if let found = trip.days?.first(where: { $0.date == key }) {
            return found
        }
        let day = Day(date: key)
        context.insert(day)
        day.trip = trip
        return day
    }

    /// 오늘을 포함하는 여행. 여러 개면 고정된 것을 먼저 고른다.
    static func tripCovering(_ date: Date, in trips: [Trip]) -> Trip? {
        let live = trips.filter { $0.deletedAt == nil && $0.contains(date: date) }
        return live.first(where: \.isPinned) ?? live.first
    }

    static func moveToTrash(_ trip: Trip) {
        trip.deletedAt = .now
        trip.isPinned = false
    }

    static func restore(_ trip: Trip) {
        trip.deletedAt = nil
    }

    // MARK: 일정

    @discardableResult
    static func addStop(
        to day: Day,
        name: String,
        address: String = "",
        coordinate: CLLocationCoordinate2D?,
        time: Date,
        timeZoneID: String = TimeZone.current.identifier,
        context: ModelContext
    ) -> Stop {
        let stop = Stop(placeName: name, timestamp: time, timeZoneID: timeZoneID)
        stop.address = address
        stop.coordinate = coordinate
        stop.blocks = [Block(kind: .paragraph)]
        context.insert(stop)
        stop.day = day
        insertByTime(stop, in: day)
        return stop
    }

    /// 수동으로 바꾼 순서는 유지하면서, 새 일정을 시각에 맞는 자리에 끼운다.
    static func insertByTime(_ stop: Stop, in day: Day) {
        var list = day.liveStops.filter { $0 !== stop }
        let index = list.firstIndex { $0.timestamp > stop.timestamp } ?? list.count
        list.insert(stop, at: index)
        renumber(list)
    }

    /// 전부 시각순으로 다시 정렬
    static func sortByTime(_ day: Day) {
        renumber(day.liveStops.sorted { $0.timestamp < $1.timestamp })
    }

    /// 드래그로 순서 바꾸기
    static func move(in day: Day, from source: IndexSet, to destination: Int) {
        var list = day.liveStops
        list.move(fromOffsets: source, toOffset: destination)
        renumber(list)
    }

    private static func renumber(_ list: [Stop]) {
        for (index, stop) in list.enumerated() where stop.sortIndex != index {
            stop.sortIndex = index
        }
    }

    /// 일정 시각이 바뀌면 알맞은 Day로 옮기고 자리를 다시 잡는다.
    static func timeChanged(_ stop: Stop, context: ModelContext) {
        guard let trip = stop.day?.trip else { return }
        let target = day(for: stop.timestamp, timeZone: stop.timeZone, in: trip, context: context)
        if stop.day !== target {
            stop.day = target
        }
        insertByTime(stop, in: target)
    }

    static func moveToTrash(_ stop: Stop) {
        stop.deletedAt = .now
    }

    static func restore(_ stop: Stop) {
        stop.deletedAt = nil
        if let day = stop.day {
            insertByTime(stop, in: day)
        }
    }

    // MARK: 태그

    static func tag(named raw: String, context: ModelContext) -> Tag? {
        let name = Tag.clean(raw)
        guard !name.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: name)
        context.insert(tag)
        return tag
    }

    static func addTag(_ raw: String, to stop: Stop, context: ModelContext) {
        guard let found = tag(named: raw, context: context) else { return }
        if stop.tags?.contains(where: { $0 === found }) == true { return }
        if stop.tags == nil { stop.tags = [] }
        stop.tags?.append(found)
        stop.updatedAt = .now
    }

    static func removeTag(_ tag: Tag, from stop: Stop) {
        stop.tags?.removeAll { $0 === tag }
        stop.updatedAt = .now
    }

    // MARK: 휴지통

    /// 30일이 지난 휴지통 항목을 완전히 지운다. 앱을 열 때마다 부른다.
    static func purgeTrash(context: ModelContext, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-trashRetention)
        let trips = (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
        for trip in trips where (trip.deletedAt ?? now) < cutoff {
            context.delete(trip)
        }
        let stops = (try? context.fetch(FetchDescriptor<Stop>(predicate: #Predicate { $0.deletedAt != nil }))) ?? []
        for stop in stops where (stop.deletedAt ?? now) < cutoff {
            context.delete(stop)
        }
        // 어느 일정에도 붙어 있지 않은 태그 정리
        let tags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        for tag in tags where (tag.stops ?? []).isEmpty {
            context.delete(tag)
        }
        try? context.save()
    }

    static func deletePermanently(_ trip: Trip, context: ModelContext) {
        context.delete(trip)
        try? context.save()
    }

    static func deletePermanently(_ stop: Stop, context: ModelContext) {
        context.delete(stop)
        try? context.save()
    }
}
