import SwiftUI
import SwiftData

/// Bear의 3단 구조.
/// iPad 가로: 사이드바 / Day·일정 목록 / 에디터·지도. iPhone에서는 같은 3단이 화면 스택으로 바뀐다.
struct RootView: View {
    @State private var navigation = AppNavigation()
    @State private var quickCapture = QuickCapture.shared
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var navigation = navigation
        @Bindable var quickCapture = quickCapture

        NavigationSplitView(columnVisibility: $navigation.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            ContentColumn()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
                .tint(Theme.teal)
        } detail: {
            NavigationStack {
                DetailColumn()
            }
            .tint(Theme.teal)
        }
        // 사이드바 접기 버튼 같은 시스템 버튼은 분할 뷰 전체의 색을 따른다.
        // 차콜 사이드바에 teal을 쓰지 않도록 여기는 흰색, 나머지 열은 teal로 다시 칠한다.
        .tint(.white)
        .environment(navigation)
        #if DEBUG
        .task {
            if DemoData.isEnabled {
                DemoData.open(DemoData.seed(context: context), navigation: navigation)
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                try? context.save()
            }
        }
        .sheet(isPresented: $navigation.showingNewTrip) {
            TripFormView(trip: nil) { trip in
                navigation.sidebar = .trip(trip)
            }
        }
        .sheet(isPresented: $navigation.showingSettings) {
            SettingsView()
        }
        .sheet(item: $navigation.newStopTarget) { target in
            NewStopSheet(trip: target.trip, preferredDay: target.day) { stop in
                navigation.open(stop)
            }
        }
        .fullScreenCover(isPresented: $quickCapture.isPresented) {
            QuickCaptureView { stop in
                navigation.open(stop)
            }
        }
    }
}

/// 두 번째 열
private struct ContentColumn: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        switch navigation.sidebar {
        case .trip(let trip):
            TripTimelineView(trip: trip)
                .id(trip.persistentModelID)
        case .tag(let name):
            StopListView(filter: .tag(name))
        case .favorites:
            StopListView(filter: .favorites)
        case .search:
            SearchView()
        case .trash:
            TrashView()
        case nil:
            ContentUnavailableView {
                Label("여행을 고르세요", systemImage: "pawprint")
            } description: {
                Text("왼쪽에서 여행을 고르거나 새 여행을 만드세요.")
            } actions: {
                Button("새 여행") { navigation.showingNewTrip = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// 세 번째 열
private struct DetailColumn: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        switch navigation.detail {
        case .day(let day):
            DayMapView(day: day)
                .id(day.persistentModelID)
        case .stop(let stop):
            StopEditorView(stop: stop)
                .id(stop.persistentModelID)
        case .tripMap(let trip):
            TripMapView(trip: trip)
                .id(trip.persistentModelID)
        case .reading(let scope):
            ReadingView(scope: scope)
        case nil:
            ContentUnavailableView {
                Label("Paws", systemImage: "pawprint.fill")
            } description: {
                Text("Day를 고르면 그날의 지도가, 일정을 고르면 에디터가 열립니다.")
            }
        }
    }
}
