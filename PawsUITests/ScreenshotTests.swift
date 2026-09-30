import XCTest
import UIKit

/// 데모 데이터로 주요 화면을 찍어 로그와 첨부로 남긴다.
/// iPhone은 세로, iPad는 가로(3단 레이아웃)로 찍는다.
/// 로그에는 JPEG를 base64로 나눠 찍는다 (CI 로그만 읽을 수 있는 환경에서 화면 확인용).
final class ScreenshotTests: XCTestCase {
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    override func setUp() {
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    func testCaptureScreens() {
        let scenes = isPad
            ? ["trip", "stop", "split", "map", "reading"]
            : ["home", "trip", "stop", "map", "reading"]
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait

        for scene in scenes {
            let app = XCUIApplication()
            app.launchArguments = [
                "--uitest", "--reset-store", "--demo", "--demo-open=\(scene)",
                "--mock-location=35.0116,135.7681,교토역",
            ]
            app.launch()
            _ = app.staticTexts["교토 가을 여행"].firstMatch.waitForExistence(timeout: 10)
            // 지도 타일과 사진이 그려질 시간
            RunLoop.current.run(until: Date().addingTimeInterval(5))
            capture(app, name: "\(isPad ? "iPad" : "iPhone")-\(scene)")
            app.terminate()
        }
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let image = screenshot.image
        let longSide: CGFloat = isPad ? 1600 : 900
        let scale = longSide / max(image.size.width, image.size.height)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.72) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        let encoded = data.base64EncodedString()
        print("SCREENSHOT-BEGIN \(name)")
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let end = encoded.index(index, offsetBy: 8000, limitedBy: encoded.endIndex) ?? encoded.endIndex
            print(encoded[index..<end])
            index = end
        }
        print("SCREENSHOT-END \(name)")
    }
}
