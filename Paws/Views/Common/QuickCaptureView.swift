import SwiftUI
import SwiftData
import PhotosUI

/// 현장 30초 기록: 사진 1장 + 한 줄 + 지금 위치.
/// 단축어·액션 버튼(App Intent) 또는 사이드바의 카메라 버튼으로 들어온다.
struct QuickCaptureView: View {
    var onCreated: (Stop) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Trip> { $0.deletedAt == nil }, sort: \Trip.startDate, order: .reverse)
    private var trips: [Trip]

    @State private var place: PlaceSelection?
    @State private var locating = true
    @State private var name = ""
    @State private var note = ""
    @State private var photo: ImportedPhoto?
    @State private var preview: UIImage?
    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var processing = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .listRowInsets(EdgeInsets())
                    }
                    HStack {
                        if CameraPicker.isAvailable {
                            Button {
                                showingCamera = true
                            } label: {
                                Label(photo == nil ? "사진 찍기" : "다시 찍기", systemImage: "camera")
                            }
                        }
                        Spacer()
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("보관함", systemImage: "photo")
                        }
                    }
                    if processing { ProgressView() }
                }

                Section("어디") {
                    HStack {
                        TextField(locating ? "위치 확인 중…" : "장소 이름", text: $name)
                            .font(.pawsHeadline)
                        if locating { ProgressView() }
                    }
                    if let place, !place.address.isEmpty {
                        Text(place.address)
                            .font(.pawsCaption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("한 줄") {
                    TextField("지금 이 순간을 한 줄로", text: $note, axis: .vertical)
                        .focused($noteFocused)
                        .font(.pawsBody)
                }

                Section {
                    Text("저장 위치: \(targetDescription)")
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("빠른 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(processing || (photo == nil && note.isEmpty && name.isEmpty))
                }
            }
            .task {
                if CameraPicker.isAvailable {
                    showingCamera = true
                }
                let current = await LocationService.shared.currentPlace()
                place = current
                if name.isEmpty { name = current?.name ?? "" }
                locating = false
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    Task { await use(image: image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                pickerItem = nil
                Task {
                    processing = true
                    if let loaded = await PhotoFactory.load([item]).first {
                        photo = loaded
                        preview = UIImage(data: loaded.thumbnailData)
                    }
                    processing = false
                    noteFocused = true
                }
            }
        }
    }

    private var targetTrip: Trip? {
        TripService.tripCovering(.now, in: trips)
    }

    private var targetDescription: String {
        if let trip = targetTrip {
            return "\(trip.emoji) \(trip.displayTitle) · 오늘"
        }
        return "오늘 날짜로 새 여행을 만듭니다"
    }

    private func use(image: UIImage) async {
        processing = true
        if let data = image.jpegData(compressionQuality: 0.92),
           let imported = await PhotoImporter.processInBackground(data) {
            photo = imported
            preview = UIImage(data: imported.thumbnailData)
        }
        processing = false
        noteFocused = true
    }

    private func save() {
        let today = DayMath.normalize(.now)
        let trip = targetTrip ?? TripService.createTrip(
            title: "새 여행",
            emoji: "🐾",
            start: today,
            end: today,
            cover: nil,
            context: context
        )
        let timeZoneID = place?.timeZoneID ?? TimeZone.current.identifier
        let timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let day = TripService.day(for: .now, timeZone: timeZone, in: trip, context: context)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let stop = TripService.addStop(
            to: day,
            name: trimmedName.isEmpty ? "빠른 기록" : trimmedName,
            address: place?.address ?? "",
            coordinate: place?.coordinate,
            time: .now,
            timeZoneID: timeZoneID,
            context: context
        )
        let line = note.trimmingCharacters(in: .whitespacesAndNewlines)
        stop.blocks = [Block(kind: .paragraph, text: line)]
        if let photo {
            let saved = PhotoFactory.attach(photo, to: stop, context: context)
            if saved.capturedAt == nil { saved.capturedAt = .now }
        }
        try? context.save()
        dismiss()
        onCreated(stop)
    }
}
