import SwiftUI
import SwiftData

/// 태그 또는 즐겨찾기로 모은 일정 목록
struct StopListView: View {
    enum Filter: Hashable {
        case tag(String)
        case favorites
    }

    let filter: Filter

    @Environment(AppNavigation.self) private var navigation
    @Query(filter: #Predicate<Stop> { $0.deletedAt == nil }, sort: \Stop.timestamp, order: .reverse)
    private var stops: [Stop]

    private var filtered: [Stop] {
        stops.filter { stop in
            guard stop.isLive else { return false }
            switch filter {
            case .favorites:
                return stop.isFavorite
            case .tag(let path):
                return stop.tagNames.contains { Tag.name($0, isWithin: path) }
            }
        }
    }

    private var title: String {
        switch filter {
        case .favorites: return "즐겨찾는 장소"
        case .tag(let path): return "#\(path)"
        }
    }

    var body: some View {
        @Bindable var navigation = navigation
        let items = filtered

        List(selection: $navigation.detail) {
            ForEach(items) { stop in
                StopCard(stop: stop, showTrip: true)
                    .tag(DetailItem.stop(stop))
            }
        }
        .listStyle(.plain)
        .overlay {
            if items.isEmpty {
                switch filter {
                case .favorites:
                    ContentUnavailableView("즐겨찾는 장소가 없어요", systemImage: "star", description: Text("일정의 별 버튼을 누르면 여기에 모입니다."))
                case .tag:
                    ContentUnavailableView("이 태그의 일정이 없어요", systemImage: "number")
                }
            }
        }
        .navigationTitle(title)
    }
}

/// 전체 검색: 글, 장소, 태그를 한 번에. 태그 칩으로 걸러 본다.
struct SearchView: View {
    @Environment(AppNavigation.self) private var navigation
    @Query(filter: #Predicate<Stop> { $0.deletedAt == nil }, sort: \Stop.timestamp, order: .reverse)
    private var stops: [Stop]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var query = ""
    @State private var tagFilter: String?

    private var results: [Stop] {
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty || tagFilter != nil else { return [] }
        return stops.filter { stop in
            guard stop.isLive else { return false }
            if let tagFilter, !stop.tagNames.contains(where: { Tag.name($0, isWithin: tagFilter) }) {
                return false
            }
            let haystack = [
                stop.placeName,
                stop.address,
                stop.searchText,
                stop.tagNames.joined(separator: " "),
                stop.trip?.title ?? "",
                stop.day?.title ?? "",
            ].joined(separator: "\n").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        @Bindable var navigation = navigation
        let found = results

        List(selection: $navigation.detail) {
            let usedTags = tags.filter { ($0.stops ?? []).contains(where: \.isLive) }
            if !usedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(usedTags) { tag in
                            let active = tagFilter == tag.name
                            Button("#\(tag.name)") {
                                tagFilter = active ? nil : tag.name
                            }
                            .font(.pawsCaption)
                            .buttonStyle(.bordered)
                            .tint(active ? Theme.teal : Color.secondary)
                            .controlSize(.small)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }
            ForEach(found) { stop in
                StopCard(stop: stop, showTrip: true)
                    .tag(DetailItem.stop(stop))
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "글, 장소, 태그 검색")
        .overlay {
            if found.isEmpty {
                if query.isEmpty && tagFilter == nil {
                    ContentUnavailableView("무엇을 찾을까요?", systemImage: "magnifyingglass", description: Text("글, 장소 이름, 주소, 태그를 한 번에 찾습니다."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .navigationTitle("검색")
    }
}
