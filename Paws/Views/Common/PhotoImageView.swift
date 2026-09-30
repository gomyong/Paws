import SwiftUI

/// 사진을 백그라운드에서 디코딩해 보여 준다. 목록에서는 썸네일, 본문에서는 2048px 사본을 쓴다.
struct PhotoImageView: View {
    let photo: Photo
    var full: Bool = false
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    private var cacheKey: String {
        "\(photo.uuid.uuidString)-\(full ? "full" : "thumb")"
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color(uiColor: .tertiarySystemFill))
            }
        }
        .accessibilityLabel("사진")
        .task(id: cacheKey) {
            if let hit = ImageCache.shared.cached(cacheKey) {
                image = hit
                return
            }
            let data = full ? (photo.imageData ?? photo.thumbnailData) : (photo.thumbnailData ?? photo.imageData)
            image = await ImageCache.shared.image(for: cacheKey, data: data)
        }
    }
}

/// 정사각 썸네일
struct PhotoThumbnail: View {
    let photo: Photo
    var size: CGFloat = 56

    var body: some View {
        PhotoImageView(photo: photo)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// 여행 커버 이미지 (Data에서 바로)
struct DataImageView: View {
    let data: Data?
    let key: String

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(uiColor: .tertiarySystemFill))
            }
        }
        .task(id: key) {
            image = await ImageCache.shared.image(for: key, data: data)
        }
    }
}
