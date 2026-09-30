import SwiftUI
import PhotosUI

/// 일정에 붙은 사진 줄. 보관함에서 여러 장, 또는 카메라로 바로.
struct PhotoStrip: View {
    @Environment(\.openPhoto) private var openPhoto
    let stop: Stop
    @Binding var items: [PhotosPickerItem]
    var onCamera: () -> Void
    var onSetCover: (Photo) -> Void
    var onInsertIntoBody: (Photo) -> Void
    var onDelete: (Photo) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) {
                    addTile(icon: "photo.badge.plus", title: "보관함")
                }
                .accessibilityLabel("보관함에서 사진 추가")
                if CameraPicker.isAvailable {
                    Button(action: onCamera) {
                        addTile(icon: "camera", title: "카메라")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("카메라로 촬영")
                }
                ForEach(stop.sortedPhotos) { photo in
                    PhotoThumbnail(photo: photo, size: 76)
                        .onTapGesture { openPhoto(photo) }
                        .overlay(alignment: .topLeading) {
                            if stop.coverPhotoID == photo.uuid {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Theme.teal, in: Circle())
                                    .padding(4)
                                    .accessibilityLabel("대표 사진")
                            }
                        }
                        .contextMenu {
                            Button {
                                onSetCover(photo)
                            } label: {
                                Label("대표 사진으로", systemImage: "star")
                            }
                            Button {
                                onInsertIntoBody(photo)
                            } label: {
                                Label("본문에 넣기", systemImage: "text.below.photo")
                            }
                            Button(role: .destructive) {
                                onDelete(photo)
                            } label: {
                                Label("사진 삭제", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func addTile(icon: String, title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(Theme.teal)
        .frame(width: 76, height: 76)
        .background(Theme.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.teal.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}
