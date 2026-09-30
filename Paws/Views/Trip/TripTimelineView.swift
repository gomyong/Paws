import SwiftUI
import SwiftData
import PhotosUI
import MapKit
import UniformTypeIdentifiers

/// 두 번째 열: 여행 헤더 + Day별 일정 목록
struct TripTimelineView: View {
    @Bindable var trip: Trip

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var editingTrip = false
    @State private var editingDay: Day?
    @State private var exportDocument: TripExportDocument?
    @State private var showingExporter = false
    @State private var showingPhotoImport = false
    @State private var importItems: [PhotosPickerItem] = []
    @State private var importProgress: (done: Int, total: Int)?
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var navigation = navigation

        List(selection: $navigation.detail) {
            Section {
                TripHeader(trip: trip)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                if trip.liveStops.contains(where: { $0.coordinate != nil }) {
                    TripMiniMap(trip: trip)
                        .frame(height: sizeClass == .compact ? 150 : 120)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                        .listRowSeparator(.hidden)
                        .tag(DetailItem.tripMap(trip))
                        .accessibilityLabel("여행 전체 지도")
                }
            }

            ForEach(trip.sortedDays) { day in
                Section {
                    DayRow(day: day)
                        .accessibilityIdentifier("dayRow")
                        .tag(DetailItem.day(day))
                        .contextMenu { dayMenu(day) }
                    ForEach(Array(day.liveStops.enumerated()), id: \.element.persistentModelID) { index, stop in
                        StopCard(stop: stop, number: index + 1)
                            .accessibilityIdentifier("stopCard")
                            .tag(DetailItem.stop(stop))
                            .contextMenu { stopMenu(stop) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    trash(stop)
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    stop.isFavorite.toggle()
                                } label: {
                                    Label("즐겨찾기", systemImage: "star")
                                }
                                .tint(Theme.teal)
                            }
                    }
                    .onMove { source, destination in
                        TripService.move(in: day, from: source, to: destination)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(trip.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    navigation.newStopTarget = NewStopTarget(trip: trip, day: selectedDay)
                } label: {
                    Label("새 일정", systemImage: "plus")
                }
                .accessibilityIdentifier("timeline.addStop")
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem(placement: .secondaryAction) {
                tripMenu
            }
        }
        .overlay {
            if let importProgress {
                ImportProgressOverlay(done: importProgress.done, total: importProgress.total)
            }
        }
        .sheet(isPresented: $editingTrip) {
            TripFormView(trip: trip) { _ in }
        }
        .sheet(item: $editingDay) { day in
            DayEditSheet(day: day)
        }
        .photosPicker(isPresented: $showingPhotoImport, selection: $importItems, maxSelectionCount: 100, matching: .images)
        .onChange(of: importItems) { _, items in
            guard !items.isEmpty else { return }
            importItems = []
            Task { await buildStops(from: items) }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .folder,
            defaultFilename: Exporter.safeFileName(trip.displayTitle)
        ) { _ in
            exportDocument = nil
        }
        .confirmationDialog("이 여행을 휴지통으로 옮길까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("휴지통으로", role: .destructive) {
                TripService.moveToTrash(trip)
                navigation.sidebar = nil
            }
        } message: {
            Text("30일 동안 휴지통에 보관한 뒤 지웁니다.")
        }
    }

    /// 지금 보고 있는 Day (새 일정의 기본 날짜)
    private var selectedDay: Day? {
        switch navigation.detail {
        case .day(let day): return day
        case .stop(let stop): return stop.day
        default: return nil
        }
    }

    private var tripMenu: some View {
        Menu {
            Button {
                navigation.detail = .reading(.trip(trip))
            } label: {
                Label("읽기 모드", systemImage: "book")
            }
            Button {
                navigation.detail = .tripMap(trip)
            } label: {
                Label("여행 지도", systemImage: "map")
            }
            Button {
                showingPhotoImport = true
            } label: {
                Label("사진으로 일정 만들기", systemImage: "photo.stack")
            }
            Divider()
            Button {
                editingTrip = true
            } label: {
                Label("여행 편집", systemImage: "pencil")
            }
            Button {
                trip.isPinned.toggle()
            } label: {
                Label(trip.isPinned ? "고정 해제" : "고정", systemImage: "pin")
            }
            Button {
                exportDocument = TripExportDocument(wrapper: Exporter.folder(for: trip))
                showingExporter = true
            } label: {
                Label("마크다운으로 내보내기", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("휴지통으로", systemImage: "trash")
            }
        } label: {
            Label("여행 메뉴", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("timeline.menu")
    }

    @ViewBuilder
    private func dayMenu(_ day: Day) -> some View {
        Button {
            navigation.newStopTarget = NewStopTarget(trip: trip, day: day)
        } label: {
            Label("이 날에 일정 추가", systemImage: "plus")
        }
        Button {
            editingDay = day
        } label: {
            Label("Day 제목·이모지", systemImage: "pencil")
        }
        Button {
            navigation.detail = .reading(.day(day))
        } label: {
            Label("이 날 읽기 모드", systemImage: "book")
        }
        Button {
            TripService.sortByTime(day)
        } label: {
            Label("시각순으로 다시 정렬", systemImage: "arrow.up.arrow.down")
        }
    }

    @ViewBuilder
    private func stopMenu(_ stop: Stop) -> some View {
        Button {
            stop.isFavorite.toggle()
        } label: {
            Label(stop.isFavorite ? "즐겨찾기 해제" : "즐겨찾기", systemImage: "star")
        }
        Button(role: .destructive) {
            trash(stop)
        } label: {
            Label("휴지통으로", systemImage: "trash")
        }
    }

    private func trash(_ stop: Stop) {
        if navigation.detail == .stop(stop) {
            navigation.detail = nil
        }
        TripService.moveToTrash(stop)
    }

    private func buildStops(from items: [PhotosPickerItem]) async {
        importProgress = (0, items.count)
        let photos = await PhotoFactory.load(items) { done, total in
            importProgress = (done, total)
        }
        let stops = await PhotoStopBuilder.makeStops(from: photos, in: trip, fallbackDay: selectedDay ?? trip.sortedDays.first, context: context)
        importProgress = nil
        if let first = stops.first {
            navigation.detail = .stop(first)
        }
    }
}

/// 여행 헤더: 이모지 + 큰 제목 + 기간
struct TripHeader: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.emoji)
                    .font(.system(size: 40))
                Text(trip.displayTitle)
                    .font(.pawsTitle)
                Text(Fmt.range(trip.startDate, trip.endDate))
                    .font(.pawsCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

/// 사진 가져오기 진행 표시. 리사이즈는 백그라운드에서 하므로 화면은 멈추지 않는다.
struct ImportProgressOverlay: View {
    let done: Int
    let total: Int

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .frame(width: 180)
            Text("사진 \(done)/\(total)장 정리 중")
                .font(.pawsCaption)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
