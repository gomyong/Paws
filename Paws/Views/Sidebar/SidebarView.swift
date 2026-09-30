import SwiftUI
import SwiftData

/// 첫 번째 열: 어두운 차콜 사이드바. 고정 여행, 여행 목록, 태그 트리, 휴지통.
struct SidebarView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Trip> { $0.deletedAt == nil }, sort: \Trip.startDate, order: .reverse)
    private var trips: [Trip]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var editingTrip: Trip?

    var body: some View {
        @Bindable var navigation = navigation

        List(selection: $navigation.sidebar) {
            Section {
                PawsWordmark()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 0))
            }

            let pinned = trips.filter(\.isPinned)
            if !pinned.isEmpty {
                Section("고정") {
                    ForEach(pinned) { trip in
                        tripRow(trip)
                    }
                }
            }

            let unpinned = trips.filter { !$0.isPinned }
            if !unpinned.isEmpty || trips.isEmpty {
                Section("여행") {
                    ForEach(unpinned) { trip in
                        tripRow(trip)
                    }
                    if trips.isEmpty {
                        Button {
                            navigation.showingNewTrip = true
                        } label: {
                            Label("첫 여행 만들기", systemImage: "plus.circle")
                        }
                    }
                }
            }

            Section {
                Label("즐겨찾는 장소", systemImage: "star")
                    .tag(SidebarItem.favorites)
                Label("검색", systemImage: "magnifyingglass")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sidebar.search")
                    .tag(SidebarItem.search)
            }

            let tree = TagNode.tree(from: tags)
            if !tree.isEmpty {
                Section("태그") {
                    ForEach(tree) { node in
                        Label(node.leaf, systemImage: node.depth == 0 ? "number" : "chevron.right")
                            .padding(.leading, CGFloat(node.depth) * 14)
                            .tag(SidebarItem.tag(node.path))
                    }
                }
            }

            Section {
                Label("휴지통", systemImage: "trash")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sidebar.trash")
                    .tag(SidebarItem.trash)
            }
        }
        .listStyle(.sidebar)
        // 차콜 사이드바에는 포인트 컬러를 쓰지 않고 흰색으로 통일한다
        .foregroundStyle(.white)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        // 뒤로 가기 버튼 이름으로는 "Paws"를 쓰고, 화면 제목은 위의 흰색 워드마크로 대신한다
        .navigationTitle("Paws")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.sidebar, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    navigation.sidebar = .search
                } label: {
                    Label("검색", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)

                Button {
                    QuickCapture.shared.isPresented = true
                } label: {
                    Label("빠른 기록", systemImage: "camera")
                }
                .accessibilityIdentifier("sidebar.quickCapture")

                Menu {
                    Button {
                        navigation.showingNewTrip = true
                    } label: {
                        Label("새 여행", systemImage: "suitcase")
                    }
                    Button {
                        navigation.showingSettings = true
                    } label: {
                        Label("저장 공간과 설정", systemImage: "gearshape")
                    }
                } label: {
                    Label("새 여행", systemImage: "plus")
                } primaryAction: {
                    navigation.showingNewTrip = true
                }
                .accessibilityIdentifier("sidebar.newTrip")
            }
        }
        .tint(.white)
        .environment(\.colorScheme, .dark)
        .sheet(item: $editingTrip) { trip in
            TripFormView(trip: trip) { _ in }
        }
    }

    private func tripRow(_ trip: Trip) -> some View {
        HStack(spacing: 10) {
            Text(trip.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.displayTitle)
                    .font(.pawsHeadline)
                    .lineLimit(1)
                Text(Fmt.range(trip.startDate, trip.endDate))
                    .font(.pawsCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if trip.contains(date: .now) {
                Text("여행 중")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.18), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .tag(SidebarItem.trip(trip))
        .accessibilityIdentifier("sidebar.trip")
        .contextMenu {
            Button {
                trip.isPinned.toggle()
            } label: {
                Label(trip.isPinned ? "고정 해제" : "고정", systemImage: trip.isPinned ? "pin.slash" : "pin")
            }
            Button {
                editingTrip = trip
            } label: {
                Label("여행 편집", systemImage: "pencil")
            }
            Button(role: .destructive) {
                delete(trip)
            } label: {
                Label("휴지통으로", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(trip)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                trip.isPinned.toggle()
            } label: {
                Label(trip.isPinned ? "고정 해제" : "고정", systemImage: "pin")
            }
            .tint(.gray)
        }
    }

    private func delete(_ trip: Trip) {
        if navigation.selectedTrip === trip {
            navigation.sidebar = nil
        }
        TripService.moveToTrash(trip)
    }
}

/// 사이드바 태그 트리의 한 줄. "음식/라멘"은 "음식" 아래 "라멘"으로 보인다.
struct TagNode: Identifiable, Hashable {
    let path: String
    var id: String { path }

    var depth: Int { path.split(separator: "/").count - 1 }
    var leaf: String { path.split(separator: "/").last.map(String.init) ?? path }

    /// 살아 있는 일정이 붙은 태그만, 상위 경로를 채워서 정렬한다.
    static func tree(from tags: [Tag]) -> [TagNode] {
        var paths = Set<String>()
        for tag in tags where (tag.stops ?? []).contains(where: \.isLive) {
            let parts = tag.name.split(separator: "/").map(String.init)
            for length in 1...max(1, parts.count) where length <= parts.count {
                paths.insert(parts[0..<length].joined(separator: "/"))
            }
        }
        return paths.sorted { lhs, rhs in
            lhs.split(separator: "/").map(String.init).lexicographicallyPrecedes(rhs.split(separator: "/").map(String.init))
        }
        .map(TagNode.init(path:))
    }
}

/// 사이드바 맨 위 로고: 흰색 "Paws" + 발자국(🐾) 마크
struct PawsWordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Paws")
                .font(.paws(34, weight: .bold, relativeTo: .largeTitle))
            Image("PawsMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Paws")
        .accessibilityAddTraits(.isHeader)
    }
}
