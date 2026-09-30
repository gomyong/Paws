import SwiftUI
import SwiftData
import PhotosUI

/// 여행 만들기·편집. 기간에 맞춰 Day가 자동으로 생긴다.
struct TripFormView: View {
    let trip: Trip?
    var onSave: (Trip) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var emoji = "✈️"
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var coverData: Data?
    @State private var coverItem: PhotosPickerItem?
    @State private var loadingCover = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("✈️", text: $emoji)
                            .font(.system(size: 34))
                            .multilineTextAlignment(.center)
                            .frame(width: 56)
                            .onChange(of: emoji) { _, value in
                                if value.count > 1, let last = value.last {
                                    emoji = String(last)
                                }
                            }
                            .accessibilityLabel("이모지")
                        TextField("여행 제목", text: $title)
                            .font(.pawsSubtitle)
                    }
                }

                Section("기간") {
                    DatePicker("시작일", selection: $start, displayedComponents: .date)
                    DatePicker("종료일", selection: $end, in: start..., displayedComponents: .date)
                    Text("\(dayCount)일 · Day가 자동으로 만들어집니다")
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                }

                Section("커버 사진") {
                    if let coverData {
                        DataImageView(data: coverData, key: "cover-edit-\(coverData.count)")
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                            .listRowInsets(EdgeInsets())
                    }
                    PhotosPicker(selection: $coverItem, matching: .images) {
                        Label(coverData == nil ? "사진 고르기" : "다른 사진으로", systemImage: "photo")
                    }
                    if loadingCover {
                        ProgressView()
                    }
                    if coverData != nil {
                        Button("커버 사진 빼기", role: .destructive) {
                            coverData = nil
                        }
                    }
                }
            }
            .navigationTitle(trip == nil ? "새 여행" : "여행 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(loadingCover)
                }
            }
            .onChange(of: coverItem) { _, item in
                guard let item else { return }
                loadingCover = true
                Task {
                    let photos = await PhotoFactory.load([item])
                    coverData = photos.first?.imageData
                    loadingCover = false
                }
            }
            .onAppear(perform: load)
        }
    }

    private var dayCount: Int {
        DayMath.days(from: DayMath.normalize(start), to: DayMath.normalize(max(start, end))).count
    }

    private func load() {
        guard let trip else { return }
        title = trip.title
        emoji = trip.emoji
        start = DayMath.localDate(from: trip.startDate)
        end = DayMath.localDate(from: trip.endDate)
        coverData = trip.coverImageData
    }

    private func save() {
        let startKey = DayMath.normalize(start)
        let endKey = DayMath.normalize(max(start, end))
        let cleanEmoji = emoji.isEmpty ? "✈️" : emoji
        let saved: Trip
        if let trip {
            trip.title = title.trimmingCharacters(in: .whitespaces)
            trip.emoji = cleanEmoji
            trip.startDate = startKey
            trip.endDate = endKey
            trip.coverImageData = coverData
            TripService.syncDays(for: trip, context: context)
            saved = trip
        } else {
            saved = TripService.createTrip(
                title: title.trimmingCharacters(in: .whitespaces),
                emoji: cleanEmoji,
                start: startKey,
                end: endKey,
                cover: coverData,
                context: context
            )
        }
        try? context.save()
        onSave(saved)
        dismiss()
    }
}
