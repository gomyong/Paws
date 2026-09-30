#if DEBUG
import SwiftUI
import SwiftData
import CoreLocation

/// 시뮬레이터 확인용 데모 데이터. `--demo` 실행 인자가 있을 때만 쓴다 (디버그 빌드 전용).
/// `--demo-open=home|trip|stop|map|reading`으로 처음 열 화면을 고른다.
@MainActor
enum DemoData {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo")
    }

    static var openTarget: String {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--demo-open=") }?
            .replacingOccurrences(of: "--demo-open=", with: "") ?? "trip"
    }

    static func seed(context: ModelContext) -> Trip {
        let calendar = DayMath.utcCalendar
        let start = DayMath.normalize(.now.addingTimeInterval(-86_400))
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? start
        let trip = TripService.createTrip(title: "교토 가을 여행", emoji: "🍁", start: start, end: end,
                                          cover: image(hue: 0.05, label: "Kyoto"), context: context)
        trip.isPinned = true
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let days = trip.sortedDays
        days[0].title = "교토"
        days[0].emoji = "⛩️"
        days[1].title = "아라시야마"
        days[1].emoji = "🎋"

        let plan: [(Int, String, Double, Double, Int, [String], String)] = [
            (0, "후시미 이나리 신사", 34.9671, 135.7727, 9, ["관광/신사"], "천 개의 도리이를 따라 한 시간쯤 올라갔다."),
            (0, "니시키 시장", 35.0050, 135.7649, 12, ["음식/시장"], "두부 도넛과 **다시마키** 계란."),
            (0, "멘야 이노이치", 35.0037, 135.7650, 18, ["음식/라멘"], "맑은 국물 라멘. 줄은 20분."),
            (1, "아라시야마 대나무숲", 35.0170, 135.6713, 8, ["관광"], "아침 일찍 가서 사람이 거의 없었다."),
            (1, "텐류지", 35.0158, 135.6737, 10, ["관광/절"], "정원이 제일 좋았다."),
        ]
        for (dayIndex, name, lat, lon, hour, tags, text) in plan {
            let day = days[dayIndex]
            let time = DayMath.time(on: day.date, hour: hour, minute: 0, in: tokyo)
            let stop = TripService.addStop(to: day, name: name, address: "교토부 교토시",
                                           coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                           time: time, timeZoneID: tokyo.identifier, context: context)
            for tag in tags { TripService.addTag(tag, to: stop, context: context) }
            if let data = image(hue: Double(hour) / 24, label: name), let imported = PhotoImporter.process(data) {
                let photo = PhotoFactory.attach(imported, to: stop, context: context)
                var blocks: [Block] = [
                    Block(kind: .paragraph, runs: runs(text)),
                    Block(kind: .heading, text: "메모"),
                    Block(kind: .bullet, text: "입장료 무료"),
                    Block(kind: .checklist, text: "사진 정리하기"),
                    .photo(photo.uuid),
                    Block(kind: .quote, text: "다음엔 가을 단풍 절정에 오자."),
                ]
                blocks[3].checked = true
                stop.blocks = blocks
            }
            stop.isFavorite = dayIndex == 0 && hour == 18
        }
        try? context.save()
        return trip
    }

    /// "**굵게**" 표기를 InlineRun으로 (데모 입력용)
    private static func runs(_ text: String) -> [InlineRun] {
        text.components(separatedBy: "**").enumerated().map { index, piece in
            InlineRun(text: piece, bold: index % 2 == 1)
        }.normalized()
    }

    private static func image(hue: Double, label: String) -> Data? {
        let size = CGSize(width: 1200, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(hue: hue, saturation: 0.45, brightness: 0.85, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(hue: hue, saturation: 0.6, brightness: 0.6, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 700, y: 120, width: 360, height: 360))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            (label as NSString).draw(at: CGPoint(x: 60, y: 620), withAttributes: attributes)
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    /// 실행 인자에 맞춰 첫 화면을 연다.
    static func open(_ trip: Trip, navigation: AppNavigation) {
        switch openTarget {
        case "home":
            return
        case "stop":
            navigation.sidebar = .trip(trip)
            if let stop = trip.liveStops.dropFirst().first { navigation.detail = .stop(stop) }
        case "map":
            navigation.sidebar = .trip(trip)
            if let day = trip.sortedDays.first { navigation.detail = .day(day) }
        case "reading":
            navigation.sidebar = .trip(trip)
            navigation.detail = .reading(.trip(trip))
        default:
            navigation.sidebar = .trip(trip)
        }
    }
}
#endif
