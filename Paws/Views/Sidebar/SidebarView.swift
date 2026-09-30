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
            let pinned = trips.filter(\.isPinned)
            if !pinned.isEmpty {
                Section("고정") {
                    ForEach(pinned) { trip in
                        tripRow(trip)
                    }
                }
            }

            Section("여행") {
                ForEach(trips.filter { !$0.isPinned }) { trip in
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

            Section {
                Label("즐겨찾는 장소", systemImage: "star")
                    .tag(SidebarItem.favorites)
                Label("검색", systemImage: "magnifyingglass")
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
                    .tag(SidebarItem.trash)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .navigationTitle("Paws")
        .toolbarBackground(Theme.sidebar, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
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
                    Label("더 보기", systemImage: "plus")
                } primaryAction: {
                    navigation.showingNewTrip = true
                }
            }
        }
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
                    .background(Theme.teal.opacity(0.25), in: Capsule())
                    .foregroundStyle(Theme.teal)
            }
        }
        .tag(SidebarItem.trip(trip))
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
            .tint(Theme.teal)
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
