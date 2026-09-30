import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import SwiftData
import PhotosUI
import SwiftUI

/// 리사이즈된 사진과 EXIF에서 읽은 정보
struct ImportedPhoto: Sendable {
    let imageData: Data
    let thumbnailData: Data
    let capturedAt: Date?
    /// 촬영 시점의 GMT 오프셋(초). EXIF OffsetTimeOriginal에서 읽는다.
    let utcOffsetSeconds: Int?
    let latitude: Double?
    let longitude: Double?
    let width: Int
    let height: Int

    var timeZone: TimeZone? {
        utcOffsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) }
    }
}

/// 사진 원본을 긴 변 2048px JPEG 사본으로 줄이고 촬영 시각·위치를 읽는다.
/// 무거운 작업이므로 항상 백그라운드에서 부른다.
enum PhotoImporter {
    static let maxPixel: CGFloat = 2048
    static let thumbnailPixel: CGFloat = 480

    static func process(_ data: Data) -> ImportedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        guard
            let full = downsample(source, maxPixel: maxPixel),
            let thumb = downsample(source, maxPixel: thumbnailPixel),
            let fullData = jpeg(full, quality: 0.82),
            let thumbData = jpeg(thumb, quality: 0.72)
        else { return nil }

        let meta = metadata(properties)
        return ImportedPhoto(
            imageData: fullData,
            thumbnailData: thumbData,
            capturedAt: meta.date,
            utcOffsetSeconds: meta.offset,
            latitude: meta.latitude,
            longitude: meta.longitude,
            width: full.width,
            height: full.height
        )
    }

    /// 카메라로 찍은 UIImage
    static func process(_ image: UIImage) -> ImportedPhoto? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        return process(data)
    }

    static func processInBackground(_ data: Data) async -> ImportedPhoto? {
        await Task.detached(priority: .userInitiated) { process(data) }.value
    }

    private static func downsample(_ source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func metadata(_ properties: [CFString: Any]) -> (date: Date?, offset: Int?, latitude: Double?, longitude: Double?) {
        var date: Date?
        var offset: Int?
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let offsetText = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
            offset = offsetText.flatMap(parseOffset)
            let timeZone = offset.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = formatter.date(from: original)
        }

        var latitude: Double?
        var longitude: Double?
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            latitude = latRef == "S" ? -lat : lat
            longitude = lonRef == "W" ? -lon : lon
        }
        return (date, offset, latitude, longitude)
    }

    /// "+09:00" → 32400
    private static func parseOffset(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let sign = trimmed.first, sign == "+" || sign == "-" else { return nil }
        let parts = trimmed.dropFirst().split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        let seconds = hours * 3600 + minutes * 60
        return sign == "-" ? -seconds : seconds
    }
}

/// 가져온 사진을 일정에 붙인다.
@MainActor
enum PhotoFactory {
    @discardableResult
    static func attach(_ imported: ImportedPhoto, to stop: Stop, context: ModelContext) -> Photo {
        let photo = Photo()
        photo.imageData = imported.imageData
        photo.thumbnailData = imported.thumbnailData
        photo.capturedAt = imported.capturedAt
        photo.latitude = imported.latitude
        photo.longitude = imported.longitude
        photo.pixelWidth = imported.width
        photo.pixelHeight = imported.height
        photo.byteCount = imported.imageData.count + imported.thumbnailData.count
        photo.sortIndex = (stop.sortedPhotos.last?.sortIndex ?? -1) + 1
        context.insert(photo)
        photo.stop = stop

        if stop.coverPhotoID == nil {
            stop.coverPhotoID = photo.uuid
        }
        // 일정에 좌표가 없으면 사진의 촬영 위치를 쓴다
        if stop.coordinate == nil, let coordinate = photo.coordinate {
            stop.coordinate = coordinate
        }
        stop.updatedAt = .now
        return photo
    }

    /// PhotosPicker에서 고른 사진들을 순서대로 가져온다. 리사이즈는 백그라운드에서 한다.
    static func load(
        _ items: [PhotosPickerItem],
        progress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> [ImportedPhoto] {
        var result: [ImportedPhoto] = []
        for (index, item) in items.enumerated() {
            progress(index, items.count)
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let imported = await PhotoImporter.processInBackground(data) {
                result.append(imported)
            }
        }
        progress(items.count, items.count)
        return result
    }

    static func remove(_ photo: Photo, from stop: Stop, context: ModelContext) {
        if stop.coverPhotoID == photo.uuid {
            stop.coverPhotoID = stop.sortedPhotos.first { $0 !== photo }?.uuid
        }
        let blocks = stop.blocks
        if blocks.contains(where: { $0.photoID == photo.uuid }) {
            stop.blocks = blocks.filter { $0.photoID != photo.uuid }
        }
        context.delete(photo)
        stop.updatedAt = .now
    }
}

/// 화면에 그릴 이미지를 백그라운드에서 디코딩하고 메모리에 캐시한다.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 300
    }

    func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func image(for key: String, data: Data?) async -> UIImage? {
        if let hit = cached(key) { return hit }
        guard let data else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            UIImage(data: data)?.preparingForDisplay()
        }.value
        if let decoded {
            cache.setObject(decoded, forKey: key as NSString)
        }
        return decoded
    }
}
