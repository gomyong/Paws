import SwiftUI
import PhotosUI
import MapKit

/// 블록을 위에서 아래로 쌓아 보여 주는 에디터 본문
struct BlockEditorView: View {
    let model: BlockEditorModel
    let stop: Stop
    var onSetCover: (Photo) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.blocks) { block in
                BlockRow(
                    block: block,
                    model: model,
                    stop: stop,
                    placeholder: model.blocks.count == 1 && block.kind == .paragraph ? "한 줄로 시작해 보세요" : nil,
                    onSetCover: onSetCover
                )
            }
            // 본문 아래 빈 곳을 누르면 이어 쓰기
            Color.clear
                .frame(height: 200)
                .contentShape(Rectangle())
                .onTapGesture { model.focusEnd() }
                .accessibilityHidden(true)
        }
    }
}

private struct BlockRow: View {
    let block: Block
    let model: BlockEditorModel
    let stop: Stop
    let placeholder: String?
    let onSetCover: (Photo) -> Void

    var body: some View {
        switch block.kind {
        case .paragraph:
            BlockTextView(block: block, model: model, placeholder: placeholder)
        case .heading:
            BlockTextView(block: block, model: model)
                .padding(.top, 10)
        case .quote:
            BlockTextView(block: block, model: model)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.teal)
                        .frame(width: 3)
                }
        case .checklist:
            HStack(alignment: .top, spacing: 10) {
                Button {
                    model.toggleChecked(block.id)
                } label: {
                    Image(systemName: block.checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(block.checked ? Theme.teal : Color.secondary)
                        .frame(width: 28, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(block.checked ? "완료됨" : "완료 안 됨")
                BlockTextView(block: block, model: model)
            }
        case .bullet:
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.primary)
                    .frame(width: 6, height: 6)
                    .frame(width: 18, height: 42)
                    .accessibilityHidden(true)
                BlockTextView(block: block, model: model)
            }
        case .photo:
            MediaBlockFrame(block: block, model: model, extraActions: photoActions) {
                if let photo = stop.photo(withID: block.photoID) {
                    PhotoImageView(photo: photo, full: true)
                        .aspectRatio(photo.aspectRatio, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                } else {
                    Label("사진을 찾을 수 없어요", systemImage: "photo.badge.exclamationmark")
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
                }
            }
        case .location:
            MediaBlockFrame(block: block, model: model) {
                if let place = block.place {
                    LocationCard(place: place)
                }
            }
        }
    }

    @ViewBuilder
    private func photoActions() -> some View {
        if let photo = stop.photo(withID: block.photoID) {
            Button {
                onSetCover(photo)
            } label: {
                Label("대표 사진으로", systemImage: "star")
            }
        }
    }
}

/// 사진·위치 블록 공통: 길게 눌러 옮기기·빼기
private struct MediaBlockFrame<Content: View, Extra: View>: View {
    let block: Block
    let model: BlockEditorModel
    var extraActions: () -> Extra
    @ViewBuilder var content: () -> Content

    init(block: Block, model: BlockEditorModel, extraActions: @escaping () -> Extra, @ViewBuilder content: @escaping () -> Content) {
        self.block = block
        self.model = model
        self.extraActions = extraActions
        self.content = content
    }

    var body: some View {
        content()
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .contextMenu {
                extraActions()
                Button {
                    model.moveBlock(block.id, by: -1)
                } label: {
                    Label("위로", systemImage: "arrow.up")
                }
                Button {
                    model.moveBlock(block.id, by: 1)
                } label: {
                    Label("아래로", systemImage: "arrow.down")
                }
                Button(role: .destructive) {
                    model.removeBlock(block.id)
                } label: {
                    Label("본문에서 빼기", systemImage: "minus.circle")
                }
            }
    }
}

extension MediaBlockFrame where Extra == EmptyView {
    init(block: Block, model: BlockEditorModel, @ViewBuilder content: @escaping () -> Content) {
        self.init(block: block, model: model, extraActions: { EmptyView() }, content: content)
    }
}

/// 본문 속 위치 블록
struct LocationCard: View {
    let place: BlockPlace

    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        VStack(alignment: .leading, spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)), interactionModes: []) {
                Marker(place.name, coordinate: coordinate)
                    .tint(Theme.teal)
            }
            .frame(height: 120)
            .allowsHitTesting(false)
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(Theme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.pawsHeadline)
                    if !place.address.isEmpty {
                        Text(place.address)
                            .font(.pawsCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("위치: \(place.name)")
    }
}
