import SwiftUI
import Observation

/// 첫 번째 열: 여행·태그 사이드바
enum SidebarItem: Hashable {
    case trip(Trip)
    case tag(String)
    case favorites
    case search
    case trash
}

/// 세 번째 열: 보고 있는 대상에 따라 바뀐다.
/// Day를 고르면 Day 지도, 일정을 고르면 에디터.
enum DetailItem: Hashable {
    case day(Day)
    case stop(Stop)
    case tripMap(Trip)
    case reading(ReadingScope)
}

@MainActor
@Observable
final class AppNavigation {
    /// 사이드바가 바뀌면 세 번째 열은 비운다.
    var sidebar: SidebarItem? {
        didSet {
            if oldValue != sidebar {
                detail = nil
                mapBesideEditor = false
            }
        }
    }
    var detail: DetailItem?
    var columnVisibility: NavigationSplitViewVisibility = .all
    /// iPad: 에디터 | 지도 2분할 (일정 목록 열을 접는다)
    var mapBesideEditor = false {
        didSet {
            if oldValue != mapBesideEditor {
                columnVisibility = mapBesideEditor ? .detailOnly : .all
            }
        }
    }
    var showingNewTrip = false
    var showingSettings = false

    /// 새 일정 시트를 띄울 대상 (여행, 미리 고른 Day)
    var newStopTarget: NewStopTarget?

    var selectedTrip: Trip? {
        if case .trip(let trip) = sidebar { return trip }
        return nil
    }

    func open(_ stop: Stop) {
        if let trip = stop.trip, selectedTrip !== trip, sidebar != .search, !isTagOrFavorites {
            sidebar = .trip(trip)
        }
        detail = .stop(stop)
    }

    private var isTagOrFavorites: Bool {
        switch sidebar {
        case .tag, .favorites: return true
        default: return false
        }
    }
}

struct NewStopTarget: Identifiable {
    let id = UUID()
    let trip: Trip
    var day: Day?
}

/// 잠금화면·액션 버튼·단축어에서 들어오는 "빠른 기록" 요청
@MainActor
@Observable
final class QuickCapture {
    static let shared = QuickCapture()
    var isPresented = false
}
