import SwiftUI
import MapKit

/// 장소 고르기: 현재 위치 / 검색 / 지도에서 핀 찍기 / 이름만
struct PlacePickerList: View {
    var onPick: (PlaceSelection) -> Void

    @State private var query = ""
    @State private var results: [PlaceSelection] = []
    @State private var searching = false
    @State private var currentPlace: PlaceSelection?
    @State private var locating = true
    @State private var showingMap = false

    var body: some View {
        List {
            Section {
                Button {
                    if let currentPlace { onPick(currentPlace) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(Theme.teal)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentPlace?.name ?? "현재 위치")
                                .foregroundStyle(.primary)
                            Text(currentSubtitle)
                                .font(.pawsCaption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if locating { ProgressView() }
                    }
                }
                .disabled(currentPlace == nil)

                Button {
                    showingMap = true
                } label: {
                    Label("지도에서 핀 찍기", systemImage: "mappin.and.ellipse")
                }

                let typed = query.trimmingCharacters(in: .whitespaces)
                if !typed.isEmpty {
                    Button {
                        onPick(PlaceSelection(name: typed, coordinate: currentPlace?.coordinate, timeZoneID: currentPlace?.timeZoneID))
                    } label: {
                        Label("‘\(typed)’ 이름으로 기록", systemImage: "character.cursor.ibeam")
                    }
                }
            }

            if !results.isEmpty || searching {
                Section("검색 결과") {
                    if searching && results.isEmpty {
                        ProgressView()
                    }
                    ForEach(results) { place in
                        Button {
                            onPick(place)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .foregroundStyle(.primary)
                                if !place.address.isEmpty {
                                    Text(place.address)
                                        .font(.pawsCaption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "장소 검색")
        .task {
            currentPlace = await LocationService.shared.currentPlace()
            locating = false
        }
        .task(id: query) {
            let text = query
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            let region = currentPlace?.coordinate.map {
                MKCoordinateRegion(center: $0, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
            }
            let found = await PlaceSearch.search(text, near: region)
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
        .sheet(isPresented: $showingMap) {
            MapPinPicker(initial: currentPlace?.coordinate) { place in
                onPick(place)
            }
        }
    }

    private var currentSubtitle: String {
        if locating { return "위치를 확인하는 중…" }
        if currentPlace == nil {
            return LocationService.shared.isDenied ? "설정에서 위치 권한을 허용해 주세요" : "위치를 찾지 못했어요"
        }
        return currentPlace?.address.isEmpty == false ? currentPlace!.address : "현재 위치"
    }
}

/// 지도를 움직여 가운데 핀으로 위치를 고른다. 일정 위치를 고칠 때도 쓴다.
struct MapPinPicker: View {
    var initial: CLLocationCoordinate2D?
    var title = "위치 고르기"
    var initialName = ""
    var onPick: (PlaceSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var resolving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    UserAnnotation()
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    center = context.region.center
                }
                Image(systemName: "mappin")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.teal)
                    .shadow(radius: 2)
                    .offset(y: -17)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    TextField("장소 이름 (비우면 주소로 채웁니다)", text: $name)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await confirm() }
                    } label: {
                        HStack {
                            if resolving { ProgressView().tint(.white) }
                            Text("이 위치로")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(resolving || (center ?? initial) == nil)
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .onAppear {
                name = initialName
                if let initial {
                    position = .region(MKCoordinateRegion(center: initial, latitudinalMeters: 800, longitudinalMeters: 800))
                    center = initial
                }
            }
        }
    }

    private func confirm() async {
        guard let coordinate = center ?? initial else { return }
        resolving = true
        let typed = name.trimmingCharacters(in: .whitespaces)
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let described = await LocationService.shared.describe(location)
        resolving = false
        var place = described ?? PlaceSelection(name: "지정한 위치", coordinate: coordinate)
        place.latitude = coordinate.latitude
        place.longitude = coordinate.longitude
        if !typed.isEmpty { place.name = typed }
        onPick(place)
        dismiss()
    }
}
