import SwiftUI
import SwiftData
import PhotosUI
import MapKit
import UniformTypeIdentifiers

/// 세 번째 열: 일정 에디터. 상단에 접이식 미니 지도, 그 아래 장소·시각·태그·사진, 그리고 블록 본문.
struct StopEditorView: View {
    @Bindable var stop: Stop

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var editor: BlockEditorModel
    @State private var mapExpanded = true
    @State private var stripItems: [PhotosPickerItem] = []
    @State private var bodyItems: [PhotosPickerItem] = []
    @State private var importProgress: (done: Int, total: Int)?
    @State private var showingCamera = false
    @State private var showingLocationBlock = false
    @State private var showingRelocate = false
    @State private var showingLink = false
    @State private var linkText = ""
    @State private var dropTargeted = false

    init(stop: Stop) {
        self.stop = stop
        _editor = State(initialValue: BlockEditorModel(blocks: stop.blocks))
    }

    var body: some View {
        Group {
            if navigation.mapBesideEditor, sizeClass == .regular, let day = stop.day {
                // iPad: 에디터 | 지도 2분할
                HStack(spacing: 0) {
                    editorScroll
                        .frame(minWidth: 380)
                    Divider()
                    DayMapView(day: day, embedded: true, highlighted: stop)
                        .frame(maxWidth: .infinity)
                }
            } else {
                editorScroll
            }
        }
        .navigationTitle(stop.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            let target = stop
            let modelContext = context
            editor.onCommit = { blocks in
                target.blocks = blocks
                // 앱이 강제 종료돼도 작성 중인 글이 남도록 자동 저장 때마다 디스크에 쓴다
                try? modelContext.save()
            }
        }
        .onDisappear {
            editor.flush()
            try? context.save()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                editor.flush()
                try? context.save()
            }
        }
        .onChange(of: stripItems) { _, items in
            guard !items.isEmpty else { return }
            stripItems = []
            Task { await importPhotos(items, intoBody: false) }
        }
        .onChange(of: bodyItems) { _, items in
            guard !items.isEmpty else { return }
            bodyItems = []
            Task { await importPhotos(items, intoBody: true) }
        }
        .overlay {
            if let importProgress {
                ImportProgressOverlay(done: importProgress.done, total: importProgress.total)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                Task { await importCameraImage(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingRelocate) {
            MapPinPicker(initial: stop.coordinate, title: "위치 수정", initialName: stop.placeName) { place in
                stop.coordinate = place.coordinate
                stop.placeName = place.name
                if !place.address.isEmpty { stop.address = place.address }
                stop.updatedAt = .now
            }
        }
        .sheet(isPresented: $showingLocationBlock) {
            NavigationStack {
                PlacePickerList { place in
                    if let coordinate = place.coordinate ?? stop.coordinate {
                        editor.insertLocation(BlockPlace(
                            name: place.name,
                            address: place.address,
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        ))
                    }
                    showingLocationBlock = false
                }
                .navigationTitle("위치 블록")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { showingLocationBlock = false }
                    }
                }
            }
        }
        .alert("링크", isPresented: $showingLink) {
            TextField("https://", text: $linkText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("추가") { editor.applyLink(linkText) }
            Button("링크 빼기", role: .destructive) { editor.removeLink() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("선택한 글자에 링크를 겁니다. 선택이 없으면 주소를 그대로 넣습니다.")
        }
    }

    // MARK: 본문

    private var editorScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                miniMap
                header
                TagEditor(stop: stop)
                PhotoStrip(
                    stop: stop,
                    items: $stripItems,
                    onCamera: { showingCamera = true },
                    onSetCover: { stop.coverPhotoID = $0.uuid },
                    onInsertIntoBody: { editor.insertPhotos([$0.uuid]) },
                    onDelete: delete
                )
                Divider()
                BlockEditorView(model: editor, stop: stop) { photo in
                    stop.coverPhotoID = photo.uuid
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            FormattingToolbar(
                model: editor,
                photoItems: $bodyItems,
                onLink: {
                    if editor.beginLink() {
                        linkText = ""
                        showingLink = true
                    }
                },
                onLocation: { showingLocationBlock = true }
            )
        }
        .onDrop(of: [.image], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.teal, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var miniMap: some View {
        if let coordinate = stop.coordinate {
            VStack(spacing: 6) {
                if mapExpanded {
                    Map(initialPosition: MapMath.focus(coordinate), interactionModes: [.zoom, .pan]) {
                        Marker(stop.displayName, coordinate: coordinate)
                            .tint(Theme.teal)
                    }
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                    .id("\(coordinate.latitude),\(coordinate.longitude)")
                }
                HStack {
                    Button {
                        withAnimation(.snappy) { mapExpanded.toggle() }
                    } label: {
                        Label(mapExpanded ? "지도 접기" : "지도 펼치기", systemImage: mapExpanded ? "chevron.up" : "map")
                    }
                    Spacer()
                    Button {
                        showingRelocate = true
                    } label: {
                        Label("위치 수정", systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.pawsCaption)
            }
        } else {
            Button {
                showingRelocate = true
            } label: {
                Label("위치 추가", systemImage: "mappin.and.ellipse")
                    .font(.pawsCaption)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("장소 이름", text: $stop.placeName, axis: .vertical)
                .font(.pawsTitle)
                .accessibilityIdentifier("editor.placeName")
            HStack(spacing: 8) {
                DatePicker("시각", selection: timeBinding, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.timeZone, stop.timeZone)
                if let badge = Fmt.timeZoneBadge(stop.timeZoneID, at: stop.timestamp) {
                    Text("현지 \(badge)")
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    stop.isFavorite.toggle()
                } label: {
                    Image(systemName: stop.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 20))
                        .foregroundStyle(stop.isFavorite ? Theme.teal : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(stop.isFavorite ? "즐겨찾기 해제" : "즐겨찾기")
            }
            if !stop.address.isEmpty {
                Text(stop.address)
                    .font(.pawsCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 시각을 바꾸면 알맞은 Day로 옮기고 시각순 자리를 다시 잡는다.
    private var timeBinding: Binding<Date> {
        Binding {
            stop.timestamp
        } set: { newValue in
            stop.timestamp = newValue
            stop.updatedAt = .now
            TripService.timeChanged(stop, context: context)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if sizeClass == .regular {
                Button {
                    navigation.mapBesideEditor.toggle()
                } label: {
                    Label("에디터 | 지도", systemImage: navigation.mapBesideEditor ? "rectangle" : "rectangle.split.2x1")
                }
                .help("에디터와 지도를 나란히")
            }
            Menu {
                if let day = stop.day {
                    Button {
                        editor.flush()
                        navigation.detail = .reading(.day(day))
                    } label: {
                        Label("이 날 읽기 모드", systemImage: "book")
                    }
                    Button {
                        navigation.detail = .day(day)
                    } label: {
                        Label("이 날 지도", systemImage: "map")
                    }
                }
                Button(role: .destructive) {
                    editor.flush()
                    TripService.moveToTrash(stop)
                    navigation.detail = nil
                } label: {
                    Label("휴지통으로", systemImage: "trash")
                }
            } label: {
                Label("일정 메뉴", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("editor.menu")
        }
    }

    // MARK: 사진

    private func importPhotos(_ items: [PhotosPickerItem], intoBody: Bool) async {
        importProgress = (0, items.count)
        let imported = await PhotoFactory.load(items) { done, total in
            importProgress = (done, total)
        }
        let photos = imported.map { PhotoFactory.attach($0, to: stop, context: context) }
        importProgress = nil
        if intoBody {
            editor.insertPhotos(photos.map(\.uuid))
        }
        try? context.save()
    }

    private func importCameraImage(_ image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        importProgress = (0, 1)
        let imported = await PhotoImporter.processInBackground(data)
        importProgress = nil
        guard let imported else { return }
        let photo = PhotoFactory.attach(imported, to: stop, context: context)
        photo.capturedAt = .now
        if stop.coordinate == nil, let location = await LocationService.shared.currentLocation() {
            photo.latitude = location.coordinate.latitude
            photo.longitude = location.coordinate.longitude
            stop.coordinate = location.coordinate
        }
        try? context.save()
    }

    private func delete(_ photo: Photo) {
        editor.removePhotoBlocks(photo.uuid)
        editor.flush()
        PhotoFactory.remove(photo, from: stop, context: context)
        try? context.save()
    }

    /// iPad: 사진 앱에서 드래그 앤 드롭
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let images = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !images.isEmpty else { return false }
        Task {
            importProgress = (0, images.count)
            var ids: [UUID] = []
            for (index, provider) in images.enumerated() {
                if let data = await loadImageData(provider),
                   let imported = await PhotoImporter.processInBackground(data) {
                    ids.append(PhotoFactory.attach(imported, to: stop, context: context).uuid)
                }
                importProgress = (index + 1, images.count)
            }
            importProgress = nil
            editor.insertPhotos(ids)
            try? context.save()
        }
        return true
    }

    private func loadImageData(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
