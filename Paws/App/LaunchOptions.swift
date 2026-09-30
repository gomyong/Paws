#if DEBUG
import Foundation
import UIKit
import CoreLocation

/// 디버그 빌드 전용 실행 인자. UI 테스트와 CI 시뮬레이터 실행에서 쓴다.
/// - `--uitest`: iCloud 없이 테스트 전용 저장소(디스크)를 쓰고 애니메이션을 끈다
/// - `--reset-store`: 테스트 저장소를 비우고 시작한다
/// - `--mock-location=위도,경도,이름`: 현재 위치를 고정한다 (권한 요청 없음)
enum LaunchOptions {
    static let arguments = ProcessInfo.processInfo.arguments

    static var isUITest: Bool { arguments.contains("--uitest") }
    static var resetStore: Bool { arguments.contains("--reset-store") }

    static var testStoreURL: URL {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("UITest", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Paws.store")
    }

    static func prepareTestStore() {
        if resetStore {
            try? FileManager.default.removeItem(at: testStoreURL.deletingLastPathComponent())
        }
        _ = testStoreURL
    }

    static var mockPlace: PlaceSelection? {
        guard let raw = arguments.first(where: { $0.hasPrefix("--mock-location=") }) else { return nil }
        let parts = raw.replacingOccurrences(of: "--mock-location=", with: "").split(separator: ",", maxSplits: 2).map(String.init)
        guard parts.count >= 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return PlaceSelection(
            name: parts.count > 2 ? parts[2] : "테스트 장소",
            address: "테스트 주소",
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            timeZoneID: TimeZone.current.identifier
        )
    }

    @MainActor
    static func applyUIDefaults() {
        if isUITest {
            UIView.setAnimationsEnabled(false)
        }
    }
}
#endif
