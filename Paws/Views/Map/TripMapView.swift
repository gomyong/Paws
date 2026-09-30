import SwiftUI
import MapKit

/// 여행 지도: 전체 동선. Day별로 선 톤을 구분한다.
struct TripMapView: View {
    let trip: Trip

    @Environment(AppNavigation.self) private var navigation
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: PersistentIdentifierHashable?
    @State private var dayFilter: Int?

    var body: some View {
        let days = trip.sortedDays
        let allPins = days.enumerated().flatMap { index, day in StopPin.pins(for: day, dayIndex: index) }
        let visiblePins = allPins.filter { dayFilter == nil || $0.dayIndex == dayFilter }
        let selectedPin = allPins.first { $0.id == selected }

        Map(position: $position) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let coords = StopPin.pins(for: day).map(\.coordinate)
                if coords.count > 1 && (dayFilter == nil || dayFilter == index) {
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.dayColor(index), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(visiblePins) { pin in
                Annotation(pin.stop.displayName, coordinate: pin.coordinate, anchor: .center) {
                    NumberPin(number: pin.number, color: Theme.dayColor(pin.dayIndex), selected: selected == pin.id)
                        .onTapGesture {
                            selected = pin.id
                        }
                        .accessibilityLabel("Day \(pin.dayIndex + 1) \(pin.number)번 \(pin.stop.displayName)")
                        .accessibilityAddTraits(.isButton)
                }
            }
            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) {
            dayChips(days)
        }
        .safeAreaInset(edge: .bottom) {
            if let pin = selectedPin {
                Button {
                    navigation.open(pin.stop)
                } label: {
                    HStack {
                        StopCard(stop: pin.stop, number: pin.number)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
        .onAppear {
            position = MapMath.position(for: allPins.map(\.coordinate))
        }
        .onChange(of: dayFilter) { _, filter in
            let coords = trip.sortedDays.enumerated()
                .filter { filter == nil || $0.offset == filter }
                .flatMap { StopPin.pins(for: $0.element) }
                .map(\.coordinate)
            withAnimation { position = MapMath.position(for: coords) }
        }
        .navigationTitle("\(trip.emoji) \(trip.displayTitle)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayChips(_ days: [Day]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("전체", color: Theme.teal, active: dayFilter == nil) { dayFilter = nil }
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    chip("Day \(index + 1)", color: Theme.dayColor(index), active: dayFilter == index) {
                        dayFilter = dayFilter == index ? nil : index
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.pawsCaption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? AnyShapeStyle(color.opacity(0.25)) : AnyShapeStyle(.regularMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
