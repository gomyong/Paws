import SwiftUI
import SwiftData

/// 휴지통: 30일 보관 후 자동 삭제. iCloud 동기화는 백업이 아니므로 여기서 한 번 더 지킨다.
struct TrashView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Trip> { $0.deletedAt != nil }, sort: \Trip.startDate, order: .reverse)
    private var trips: [Trip]
    @Query(filter: #Predicate<Stop> { $0.deletedAt != nil }, sort: \Stop.timestamp, order: .reverse)
    private var stops: [Stop]

    @State private var confirmEmpty = false

    /// 여행째로 지운 경우 그 안의 일정은 따로 보여 주지 않는다
    private var looseStops: [Stop] {
        stops.filter { $0.day?.trip?.deletedAt == nil }
    }

    var body: some View {
        List {
            Section {
                Text("휴지통의 항목은 30일 뒤 완전히 지워집니다.")
                    .font(.pawsCaption)
                    .foregroundStyle(.secondary)
            }
            if !trips.isEmpty {
                Section("여행") {
                    ForEach(trips) { trip in
                        HStack {
                            Text(trip.emoji)
                            VStack(alignment: .leading) {
                                Text(trip.displayTitle).font(.pawsHeadline)
                                Text(remaining(trip.deletedAt)).font(.pawsCaption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("복원") { TripService.restore(trip) }
                                .buttonStyle(.bordered)
                        }
                        .swipeActions {
                            Button("완전히 삭제", role: .destructive) {
                                TripService.deletePermanently(trip, context: context)
                            }
                        }
                    }
                }
            }
            if !looseStops.isEmpty {
                Section("일정") {
                    ForEach(looseStops) { stop in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(stop.displayName).font(.pawsHeadline)
                                Text("\(stop.trip?.displayTitle ?? "") · \(remaining(stop.deletedAt))")
                                    .font(.pawsCaption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("복원") { TripService.restore(stop) }
                                .buttonStyle(.bordered)
                        }
                        .swipeActions {
                            Button("완전히 삭제", role: .destructive) {
                                TripService.deletePermanently(stop, context: context)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if trips.isEmpty && looseStops.isEmpty {
                ContentUnavailableView("휴지통이 비어 있어요", systemImage: "trash")
            }
        }
        .navigationTitle("휴지통")
        .toolbar {
            if !trips.isEmpty || !looseStops.isEmpty {
                Button("비우기", role: .destructive) { confirmEmpty = true }
            }
        }
        .confirmationDialog("휴지통을 비울까요? 되돌릴 수 없습니다.", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("모두 완전히 삭제", role: .destructive) {
                for trip in trips { context.delete(trip) }
                for stop in looseStops { context.delete(stop) }
                try? context.save()
            }
        }
    }

    private func remaining(_ deletedAt: Date?) -> String {
        guard let deletedAt else { return "" }
        let left = deletedAt.addingTimeInterval(TripService.trashRetention).timeIntervalSinceNow
        let days = max(0, Int(ceil(left / 86_400)))
        return "\(days)일 뒤 삭제"
    }
}
