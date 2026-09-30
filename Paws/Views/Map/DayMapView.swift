import SwiftUI
import MapKit

/// Day 지도: 그날의 일정 핀을 시간순 번호로 표시하고 선으로 잇는다.
/// 핀을 누르면 아래 카드가 그 일정으로 오고, 카드를 누르면 지도가 그 위치로 이동한다.
struct DayMapView: View {
    let day: Day
    /// 에디터 옆에 붙는 작은 모드 (툴바 없음)
    var embedded = false
    /// 에디터 옆에서 지금 쓰고 있는 일정
    var highlighted: Stop? = nil

    @Environment(AppNavigation.self) private var navigation
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: PersistentIdentifierHashable?
    @State private var editingDay = false

    var body: some View {
        let pins = StopPin.pins(for: day)
        let stops = day.liveStops

        Map(position: $position) {
            if pins.count > 1 {
                MapPolyline(coordinates: pins.map(\.coordinate))
                    .stroke(Theme.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(pins) { pin in
                Annotation(pin.stop.displayName, coordinate: pin.coordinate, anchor: .center) {
                    NumberPin(number: pin.number, selected: selected == pin.id)
                        .onTapGesture { select(pin.stop, pins: pins) }
                        .accessibilityLabel("\(pin.number)번 \(pin.stop.displayName)")
                        .accessibilityAddTraits(.isButton)
                }
            }
            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .overlay {
            if stops.isEmpty {
                ContentUnavailableView {
                    Label("아직 일정이 없어요", systemImage: "mappin.slash")
                } description: {
                    Text("＋ 버튼으로 이 날의 첫 일정을 남겨 보세요.")
                }
                .background(.regularMaterial)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !stops.isEmpty {
                cardCarousel(stops: stops, pins: pins)
            }
        }
        .onAppear {
            position = MapMath.position(for: pins.map(\.coordinate))
            if let highlighted {
                selected = PersistentIdentifierHashable(highlighted)
            }
        }
        .onChange(of: highlighted.map { PersistentIdentifierHashable($0) }) { _, newValue in
            selected = newValue
            if let stop = highlighted, let coordinate = stop.coordinate {
                withAnimation { position = MapMath.focus(coordinate) }
            }
        }
        .navigationTitle(embedded ? "" : day.headline)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        navigation.newStopTarget = day.trip.map { NewStopTarget(trip: $0, day: day) }
                    } label: {
                        Label("이 날에 일정 추가", systemImage: "plus")
                    }
                    Menu {
                        Button {
                            navigation.detail = .reading(.day(day))
                        } label: {
                            Label("이 날 읽기 모드", systemImage: "book")
                        }
                        Button {
                            editingDay = true
                        } label: {
                            Label("Day 제목·이모지", systemImage: "pencil")
                        }
                        Button {
                            withAnimation { position = MapMath.position(for: pins.map(\.coordinate)) }
                        } label: {
                            Label("전체 동선 보기", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                    } label: {
                        Label("Day 메뉴", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $editingDay) {
            DayEditSheet(day: day)
        }
    }

    private func select(_ stop: Stop, pins: [StopPin]) {
        selected = PersistentIdentifierHashable(stop)
        if let coordinate = stop.coordinate {
            withAnimation(.easeInOut) { position = MapMath.focus(coordinate) }
        }
    }

    private func cardCarousel(stops: [Stop], pins: [StopPin]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(stops.enumerated()), id: \.element.persistentModelID) { index, stop in
                        let key = PersistentIdentifierHashable(stop)
                        Button {
                            if selected == key {
                                navigation.open(stop)
                            } else {
                                select(stop, pins: pins)
                            }
                        } label: {
                            StopCard(stop: stop, number: index + 1)
                                .padding(12)
                                .frame(width: embedded ? 240 : 290, alignment: .leading)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(selected == key ? Theme.teal : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .id(key)
                        .accessibilityHint(selected == key ? "두 번 탭하면 일정을 엽니다" : "지도에서 위치를 봅니다")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: selected) { _, key in
                guard let key else { return }
                withAnimation { proxy.scrollTo(key, anchor: .center) }
            }
        }
        .frame(height: embedded ? 120 : 132)
    }
}
