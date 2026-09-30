import SwiftUI
import SwiftData

/// 새 일정: ＋ → 장소 → 저장, 3탭 안에 끝난다.
struct NewStopSheet: View {
    let trip: Trip
    var preferredDay: Day?
    var onCreated: (Stop) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var place: PlaceSelection?
    @State private var name = ""
    @State private var dayIndex = 0
    @State private var time = Date.now

    var body: some View {
        NavigationStack {
            Group {
                if place == nil {
                    PlacePickerList { picked in
                        place = picked
                        name = picked.name
                    }
                    .navigationTitle("어디에 있나요?")
                } else {
                    confirmForm
                        .navigationTitle("새 일정")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                if place != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") { save() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .onAppear(perform: setDefaults)
    }

    private var days: [Day] { trip.sortedDays }

    private var confirmForm: some View {
        Form {
            Section("장소") {
                TextField("장소 이름", text: $name)
                    .font(.pawsHeadline)
                if let place, !place.address.isEmpty {
                    Text(place.address)
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                }
                Button("다른 장소 고르기") {
                    place = nil
                }
            }
            Section("언제") {
                if days.count > 1 {
                    Picker("Day", selection: $dayIndex) {
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            Text("\(day.headline) · \(Fmt.day(day.date))").tag(index)
                        }
                    }
                    .onChange(of: dayIndex) { _, _ in moveTimeToSelectedDay() }
                }
                DatePicker("시각", selection: $time, displayedComponents: .hourAndMinute)
            }
        }
    }

    private func setDefaults() {
        let today = DayMath.normalize(.now)
        if let preferredDay, let index = days.firstIndex(where: { $0 === preferredDay }) {
            dayIndex = index
        } else if let index = days.firstIndex(where: { $0.date == today }) {
            dayIndex = index
        } else if let last = days.indices.last, let firstDate = days.first?.date, today > firstDate {
            dayIndex = last
        }
        moveTimeToSelectedDay(initial: true)
    }

    /// 오늘이면 지금 시각. 지난 날짜에 소급해서 쓸 때는 처음엔 정오, 그 뒤엔 고른 시·분을 유지한다.
    private func moveTimeToSelectedDay(initial: Bool = false) {
        guard days.indices.contains(dayIndex) else { return }
        let day = days[dayIndex]
        if day.date == DayMath.normalize(.now) {
            time = .now
            return
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        time = DayMath.time(
            on: day.date,
            hour: initial ? 12 : (parts.hour ?? 12),
            minute: initial ? 0 : (parts.minute ?? 0),
            in: .current
        )
    }

    private func save() {
        guard let place else { return }
        let day = days.indices.contains(dayIndex)
            ? days[dayIndex]
            : TripService.day(for: time, timeZone: .current, in: trip, context: context)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let stop = TripService.addStop(
            to: day,
            name: trimmed.isEmpty ? place.name : trimmed,
            address: place.address,
            coordinate: place.coordinate,
            time: time,
            timeZoneID: place.timeZoneID ?? TimeZone.current.identifier,
            context: context
        )
        try? context.save()
        dismiss()
        onCreated(stop)
    }
}

/// Day 제목과 이모지 고치기
struct DayEditSheet: View {
    @Bindable var day: Day
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("🍜", text: $day.emoji)
                            .font(.system(size: 30))
                            .multilineTextAlignment(.center)
                            .frame(width: 52)
                            .onChange(of: day.emoji) { _, value in
                                if value.count > 1, let last = value.last {
                                    day.emoji = String(last)
                                }
                            }
                            .accessibilityLabel("이모지")
                        TextField("제목 (예: 교토)", text: $day.title)
                            .font(.pawsHeadline)
                    }
                } footer: {
                    Text("Day \(day.number) · \(Fmt.fullDay(day.date))")
                }
            }
            .navigationTitle("Day 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
