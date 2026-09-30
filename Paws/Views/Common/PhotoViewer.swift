import SwiftUI
import SwiftData

/// 사진을 누르면 전체 화면 뷰어를 여는 동작.
/// 환경값에 클로저를 그대로 넣으면 SwiftUI가 값을 비교하지 못해 매번 화면을 다시 그리므로,
/// SwiftUI의 OpenURLAction처럼 비교 가능한 타입으로 감싼다.
struct OpenPhotoAction: Equatable {
    private let handler: ((Photo) -> Void)?

    init(_ handler: ((Photo) -> Void)? = nil) {
        self.handler = handler
    }

    func callAsFunction(_ photo: Photo) {
        handler?(photo)
    }

    /// 동작 내용(뷰어 띄우기)은 바뀌지 않으므로 설정 여부만 비교한다
    static func == (lhs: OpenPhotoAction, rhs: OpenPhotoAction) -> Bool {
        (lhs.handler == nil) == (rhs.handler == nil)
    }
}

extension EnvironmentValues {
    /// 뷰어를 띄울 수 있는 화면(에디터, 읽기 모드)이 설정한다. 설정되지 않은 곳에서는 아무 일도 하지 않는다.
    @Entry var openPhoto = OpenPhotoAction()
}

/// 전체 화면 사진 뷰어: 좌우로 넘기고, 두 손가락이나 두 번 탭으로 확대한다.
struct PhotoViewer: View {
    let photos: [Photo]
    @State private var selection: PersistentIdentifier
    @Environment(\.dismiss) private var dismiss

    init(photos: [Photo], start: Photo) {
        self.photos = photos.isEmpty ? [start] : photos
        _selection = State(initialValue: start.persistentModelID)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    ZoomablePhoto(photo: photo)
                        .tag(photo.persistentModelID)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(16)
            }
            .accessibilityLabel("닫기")
            .accessibilityIdentifier("photoViewer.close")
        }
        .statusBarHidden()
    }
}

private struct ZoomablePhoto: View {
    let photo: Photo
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        PhotoImageView(photo: photo, full: true, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale * pinch)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(max(scale * value.magnification, 1), 4)
                        if scale == 1 { offset = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // 확대했을 때만 끌어서 옮긴다 (아니면 페이지 넘김)
                        if scale > 1 { offset = value.translation }
                    },
                including: scale > 1 ? .all : .subviews
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    scale = scale > 1 ? 1 : 2.5
                    offset = .zero
                }
            }
    }
}
