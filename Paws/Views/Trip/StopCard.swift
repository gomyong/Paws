import SwiftUI

/// 일정 카드: 장소명 + 시간 + 메모 미리보기 + 대표 사진 썸네일
struct StopCard: View {
    let stop: Stop
    var number: Int? = nil
    var showTrip = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let number {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.teal, in: Circle())
                    .padding(.top, 1)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(stop.displayName)
                        .font(.pawsHeadline)
                        .lineLimit(1)
                    if stop.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.teal)
                    }
                }
                HStack(spacing: 6) {
                    Text(Fmt.time(stop.timestamp, timeZoneID: stop.timeZoneID))
                    if let badge = Fmt.timeZoneBadge(stop.timeZoneID, at: stop.timestamp) {
                        Text(badge)
                    }
                    if showTrip, let trip = stop.trip {
                        Text("· \(trip.emoji) \(trip.displayTitle)")
                            .lineLimit(1)
                    }
                }
                .font(.pawsCaption)
                .foregroundStyle(.secondary)

                if !stop.previewText.isEmpty {
                    Text(stop.previewText)
                        .font(.paws(15, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !stop.tagNames.isEmpty {
                    Text(stop.tagNames.map { "#\($0)" }.joined(separator: " "))
                        .font(.pawsCaption)
                        .foregroundStyle(Theme.teal)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let cover = stop.coverPhoto {
                PhotoThumbnail(photo: cover, size: 58)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stopCard")
    }
}

/// Day 줄: "🍜 Day 3 · 교토" + 날짜 + 일정 수
struct DayRow: View {
    let day: Day

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.headline)
                    .font(.paws(20, weight: .bold, relativeTo: .title3))
                Text(Fmt.day(day.date))
                    .font(.pawsCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let count = day.liveStops.count
            if count > 0 {
                Label("\(count)", systemImage: "map")
                    .font(.pawsCaption)
                    .foregroundStyle(Theme.teal)
                    .accessibilityLabel("일정 \(count)개, 지도 보기")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}
