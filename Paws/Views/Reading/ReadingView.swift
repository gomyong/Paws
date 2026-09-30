import SwiftUI
import MapKit
import UIKit
import UniformTypeIdentifiers

/// 읽기 모드: Day 또는 여행 전체를 일정 순서대로 글 + 사진 + 미니 지도로 이어서 보여 준다.
/// "여행 후 정리 없이 바로 읽히는 여행기". 여기서 블로그 발행용으로 복사한다.
struct ReadingView: View {
    let scope: ReadingScope

    @Environment(AppNavigation.self) private var navigation
    @State private var toast: String?
    @State private var shareURLs: [URL] = []
    @State private var showingShare = false
    @State private var exportDocument: TripExportDocument?
    @State private var showingExporter = false
    @State private var viewerPhoto: Photo?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if case .trip(let trip) = scope {
                    TripHeader(trip: trip)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                }
                ForEach(scope.days) { day in
                    let stops = day.liveStops
                    if !stops.isEmpty {
                        ReadingDaySection(day: day, stops: stops) { stop in
                            navigation.open(stop)
                        }
                    }
                }
                if scope.days.allSatisfy({ $0.liveStops.isEmpty }) {
                    ContentUnavailableView("아직 기록이 없어요", systemImage: "book.closed", description: Text("일정을 남기면 여기서 한 편의 여행기로 읽힙니다."))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyForBlog()
                    } label: {
                        Label("블로그용으로 복사", systemImage: "doc.on.doc")
                    }
                    Button {
                        sharePhotos()
                    } label: {
                        Label("사진 순서대로 공유·저장", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        UIPasteboard.general.string = Exporter.markdown(scope)
                        show("마크다운을 복사했어요")
                    } label: {
                        Label("마크다운 복사", systemImage: "number")
                    }
                    if let trip = scope.trip {
                        Button {
                            exportDocument = TripExportDocument(wrapper: Exporter.folder(for: trip))
                            showingExporter = true
                        } label: {
                            Label("마크다운 + 이미지 폴더 내보내기", systemImage: "folder")
                        }
                    }
                } label: {
                    Label("발행", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("reading.publish")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.pawsCaption.weight(.semibold))
                    .accessibilityIdentifier("toast")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.openPhoto, { photo in
            viewerPhoto = photo
        })
        .fullScreenCover(item: $viewerPhoto) { photo in
            PhotoViewer(photos: photo.stop?.sortedPhotos ?? [photo], start: photo)
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(items: shareURLs)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .folder,
            defaultFilename: Exporter.safeFileName(scope.trip?.displayTitle ?? "Paws")
        ) { _ in
            exportDocument = nil
        }
    }

    /// 제목·본문 서식이 살아 있는 HTML과 평문을 함께 복사한다. 사진 자리는 [사진 N]으로 남는다.
    private func copyForBlog() {
        let result = Exporter.blogHTML(scope)
        UIPasteboard.general.items = [[
            UTType.html.identifier: result.html,
            UTType.utf8PlainText.identifier: result.plain,
        ]]
        show(result.photos.isEmpty ? "블로그용으로 복사했어요" : "복사했어요 · 사진 \(result.photos.count)장은 ‘사진 공유’로 저장하세요")
    }

    private func sharePhotos() {
        let photos = Exporter.blogHTML(scope).photos
        shareURLs = Exporter.temporaryPhotoFiles(photos)
        if shareURLs.isEmpty {
            show("공유할 사진이 없어요")
        } else {
            showingShare = true
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toast = nil }
        }
    }
}

/// Day 한 덩어리: 헤더 + 미니 지도 + 일정들
private struct ReadingDaySection: View {
    let day: Day
    let stops: [Stop]
    var onOpen: (Stop) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.headline)
                    .font(.paws(24, weight: .bold, relativeTo: .title2))
                Text(Fmt.fullDay(day.date))
                    .font(.pawsCaption)
                    .foregroundStyle(.secondary)
            }
            let pins = StopPin.pins(for: day)
            if !pins.isEmpty {
                Map(initialPosition: MapMath.position(for: pins.map(\.coordinate)), interactionModes: []) {
                    if pins.count > 1 {
                        MapPolyline(coordinates: pins.map(\.coordinate))
                            .stroke(Theme.teal, lineWidth: 3)
                    }
                    ForEach(pins) { pin in
                        Annotation("", coordinate: pin.coordinate, anchor: .center) {
                            NumberPin(number: pin.number)
                        }
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
                .allowsHitTesting(false)
                .accessibilityLabel("\(day.headline) 동선 지도")
            }
            ForEach(Array(stops.enumerated()), id: \.element.persistentModelID) { index, stop in
                ReadingStopView(stop: stop, number: index + 1, onOpen: onOpen)
            }
        }
    }
}

/// 일정 하나를 읽기 전용으로
private struct ReadingStopView: View {
    @Environment(\.openPhoto) private var openPhoto
    let stop: Stop
    let number: Int
    var onOpen: (Stop) -> Void

    var body: some View {
        let blocks = stop.blocks
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onOpen(stop)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    NumberPin(number: number)
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.displayName)
                            .font(.pawsSubtitle)
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text(Fmt.time(stop.timestamp, timeZoneID: stop.timeZoneID))
                            if !stop.address.isEmpty {
                                Text("· \(stop.address)")
                                    .lineLimit(1)
                            }
                        }
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("일정을 편집합니다")

            if let cover = Exporter.coverOutsideBody(of: stop) {
                ReadingPhoto(photo: cover)
            }

            ForEach(blocks) { block in
                ReadingBlockView(block: block, stop: stop)
            }

            let loose = Exporter.loosePhotos(of: stop)
            if !loose.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                    ForEach(loose) { photo in
                        PhotoImageView(photo: photo)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture { openPhoto?(photo) }
                    }
                }
            }

            if !stop.tagNames.isEmpty {
                Text(stop.tagNames.map { "#\($0)" }.joined(separator: " "))
                    .font(.pawsCaption)
                    .foregroundStyle(Theme.teal)
            }
        }
    }
}

private struct ReadingPhoto: View {
    @Environment(\.openPhoto) private var openPhoto
    let photo: Photo

    var body: some View {
        PhotoImageView(photo: photo, full: true, contentMode: .fit)
            .aspectRatio(photo.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
            .onTapGesture { openPhoto?(photo) }
    }
}

/// 블록 → 읽기용 Text
struct ReadingBlockView: View {
    let block: Block
    let stop: Stop

    var body: some View {
        switch block.kind {
        case .paragraph:
            if !block.plainText.isEmpty {
                Text(Self.attributed(block.runs))
                    .font(.pawsBody)
                    .lineSpacing(9)
                    .textSelection(.enabled)
            }
        case .heading:
            if !block.plainText.isEmpty {
                Text(block.plainText)
                    .font(.pawsSubtitle)
                    .padding(.top, 6)
            }
        case .quote:
            if !block.plainText.isEmpty {
                Text(Self.attributed(block.runs))
                    .font(.pawsBody)
                    .lineSpacing(9)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Theme.teal).frame(width: 3)
                    }
            }
        case .bullet:
            if !block.plainText.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•")
                    Text(Self.attributed(block.runs))
                        .lineSpacing(9)
                }
                .font(.pawsBody)
            }
        case .checklist:
            if !block.plainText.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: block.checked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(block.checked ? Theme.teal : Color.secondary)
                    Text(Self.attributed(block.runs))
                        .strikethrough(block.checked)
                        .foregroundStyle(block.checked ? .secondary : .primary)
                        .lineSpacing(9)
                }
                .font(.pawsBody)
            }
        case .photo:
            if let photo = stop.photo(withID: block.photoID) {
                ReadingPhoto(photo: photo)
            }
        case .location:
            if let place = block.place {
                LocationCard(place: place)
            }
        }
    }

    static func attributed(_ runs: [InlineRun]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if run.bold {
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            if let link = run.link, let url = URL(string: link) {
                // 링크 색은 앱 포인트 컬러(tint)를 따른다
                piece.link = url
            }
            result += piece
        }
        return result
    }
}

/// 공유 시트 (사진 파일을 순서대로 저장·공유)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
