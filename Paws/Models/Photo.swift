import Foundation
import SwiftData
import CoreLocation

/// 사진. 긴 변 2048px 사본을 앱이 직접 보관한다.
/// externalStorage라서 이미지 바이트는 DB 밖 별도 파일로 저장되고, iCloud에는 에셋으로 올라간다.
@Model
final class Photo {
    /// 본문 사진 블록이 가리키는 식별자
    var uuid: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var capturedAt: Date?
    var latitude: Double?
    var longitude: Double?
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var byteCount: Int = 0
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var stop: Stop?

    init() {
        self.uuid = UUID()
        self.createdAt = .now
    }
}

extension Photo {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var aspectRatio: CGFloat {
        guard pixelWidth > 0, pixelHeight > 0 else { return 4.0 / 3.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }
}
