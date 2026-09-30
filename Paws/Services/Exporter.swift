import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 여행기를 어디까지 묶을지
enum ReadingScope: Hashable {
    case trip(Trip)
    case day(Day)

    var days: [Day] {
        switch self {
        case .trip(let trip): return trip.sortedDays
        case .day(let day): return [day]
        }
    }

    var trip: Trip? {
        switch self {
        case .trip(let trip): return trip
        case .day(let day): return day.trip
        }
    }

    var title: String {
        switch self {
        case .trip(let trip): return "\(trip.emoji) \(trip.displayTitle)".trimmingCharacters(in: .whitespaces)
        case .day(let day): return day.headline
        }
    }
}

/// 블록 목록 → 마크다운 / 블로그 붙여넣기용 HTML / 평문.
/// 본문은 블록으로 저장하고, 내보낼 때만 변환한다.
@MainActor
enum Exporter {
    // MARK: 공통

    static func mapsURL(latitude: Double, longitude: Double, name: String) -> String {
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(query)"
    }

    static func imageFileName(_ photo: Photo) -> String {
        "photo-\(photo.uuid.uuidString.prefix(8).lowercased()).jpg"
    }

    /// 본문에 들어가지 않은 사진 (대표 사진 제외). 여행기 끝에 모아서 보여 준다.
    static func loosePhotos(of stop: Stop) -> [Photo] {
        let used = Set(stop.blocks.compactMap(\.photoID))
        let cover = coverOutsideBody(of: stop)
        return stop.sortedPhotos.filter { !used.contains($0.uuid) && $0 !== cover }
    }

    /// 본문에 이미 들어간 사진이 아니면 대표 사진을 일정 머리에 보여 준다.
    static func coverOutsideBody(of stop: Stop) -> Photo? {
        guard let cover = stop.coverPhoto else { return nil }
        let used = Set(stop.blocks.compactMap(\.photoID))
        return used.contains(cover.uuid) ? nil : cover
    }

    // MARK: 마크다운

    static func markdown(_ scope: ReadingScope) -> String {
        var lines: [String] = []
        if case .trip(let trip) = scope {
            lines.append("# \(scope.title)")
            lines.append("")
            lines.append("_\(Fmt.range(trip.startDate, trip.endDate))_")
            lines.append("")
            if trip.coverImageData != nil {
                lines.append("![](images/cover.jpg)")
                lines.append("")
            }
        }
        for day in scope.days {
            let stops = day.liveStops
            if stops.isEmpty && day.title.isEmpty { continue }
            let heading = scope.days.count > 1 || scope.trip == nil ? "##" : "#"
            lines.append("\(heading) \(day.headline)")
            lines.append("")
            lines.append("_\(Fmt.fullDay(day.date))_")
            lines.append("")
            for stop in stops {
                lines.append(contentsOf: markdown(stop))
            }
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(_ stop: Stop) -> [String] {
        var lines: [String] = []
        lines.append("### \(stop.displayName)")
        lines.append("")
        var meta = [Fmt.time(stop.timestamp, timeZoneID: stop.timeZoneID)]
        if !stop.address.isEmpty { meta.append(stop.address) }
        if let c = stop.coordinate {
            meta.append("[지도](\(mapsURL(latitude: c.latitude, longitude: c.longitude, name: stop.displayName)))")
        }
        lines.append("_\(meta.joined(separator: " · "))_")
        if !stop.tagNames.isEmpty {
            lines.append("")
            lines.append(stop.tagNames.map { "#\($0)" }.joined(separator: " "))
        }
        lines.append("")
        if let cover = coverOutsideBody(of: stop) {
            lines.append("![](images/\(imageFileName(cover)))")
            lines.append("")
        }
        var previous: BlockKind?
        for block in stop.blocks {
            let line = markdown(block, stop: stop)
            if line.isEmpty { continue }
            // 목록·체크리스트는 연속되면 빈 줄 없이 붙인다
            let isList = block.kind == .bullet || block.kind == .checklist
            if !(isList && previous == block.kind), let last = lines.last, !last.isEmpty {
                lines.append("")
            }
            lines.append(line)
            previous = block.kind
        }
        let loose = loosePhotos(of: stop)
        if !loose.isEmpty {
            lines.append("")
            for photo in loose {
                lines.append("![](images/\(imageFileName(photo)))")
            }
        }
        lines.append("")
        return lines
    }

    static func markdown(_ block: Block, stop: Stop) -> String {
        let text = inlineMarkdown(block.runs)
        switch block.kind {
        case .paragraph: return text
        case .heading: return text.isEmpty ? "" : "#### \(text)"
        case .quote: return text.isEmpty ? "" : "> \(text)"
        case .bullet: return text.isEmpty ? "" : "- \(text)"
        case .checklist: return text.isEmpty ? "" : "- [\(block.checked ? "x" : " ")] \(text)"
        case .photo:
            guard let photo = stop.photo(withID: block.photoID) else { return "" }
            return "![](images/\(imageFileName(photo)))"
        case .location:
            guard let place = block.place else { return "" }
            return "📍 [\(place.name)](\(mapsURL(latitude: place.latitude, longitude: place.longitude, name: place.name)))"
        }
    }

    static func inlineMarkdown(_ runs: [InlineRun]) -> String {
        runs.map { run in
            var text = run.text
            if run.bold, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                text = "**\(text)**"
            }
            if let link = run.link {
                text = "[\(text)](\(link))"
            }
            return text
        }.joined()
    }

    /// 여행 하나 → "여행이름/여행이름.md + images/"
    static func folder(for trip: Trip) -> FileWrapper {
        var images: [String: FileWrapper] = [:]
        if let cover = trip.coverImageData {
            images["cover.jpg"] = FileWrapper(regularFileWithContents: cover)
        }
        for stop in trip.liveStops {
            for photo in stop.sortedPhotos {
                if let data = photo.imageData {
                    images[imageFileName(photo)] = FileWrapper(regularFileWithContents: data)
                }
            }
        }
        let markdownFile = FileWrapper(regularFileWithContents: Data(markdown(.trip(trip)).utf8))
        let imagesFolder = FileWrapper(directoryWithFileWrappers: images)
        imagesFolder.preferredFilename = "images"
        return FileWrapper(directoryWithFileWrappers: [
            "\(safeFileName(trip.displayTitle)).md": markdownFile,
            "images": imagesFolder,
        ])
    }

    /// 모든 여행 백업: 여행마다 "날짜 제목" 폴더
    static func backup(_ trips: [Trip]) -> FileWrapper {
        var folders: [String: FileWrapper] = [:]
        for trip in trips {
            var name = "\(Fmt.iso(trip.startDate)) \(safeFileName(trip.displayTitle))"
            var suffix = 2
            while folders[name] != nil {
                name = "\(Fmt.iso(trip.startDate)) \(safeFileName(trip.displayTitle)) \(suffix)"
                suffix += 1
            }
            let folder = self.folder(for: trip)
            folder.preferredFilename = name
            folders[name] = folder
        }
        return FileWrapper(directoryWithFileWrappers: folders)
    }

    static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Paws" : cleaned
    }

    // MARK: 블로그용 HTML

    /// 네이버 블로그·브런치에 붙여넣기 좋은 단순한 HTML.
    /// 외부 에디터는 붙여넣은 이미지를 올리지 않으므로 사진 자리는 [사진 N]으로 남기고,
    /// 사진은 같은 순서로 따로 저장·공유한다.
    static func blogHTML(_ scope: ReadingScope) -> (html: String, plain: String, photos: [Photo]) {
        var html: [String] = []
        var plain: [String] = []
        var photos: [Photo] = []

        func photoMarker(_ photo: Photo) {
            photos.append(photo)
            html.append("<p style=\"color:#888\">[사진 \(photos.count)]</p>")
            plain.append("[사진 \(photos.count)]")
        }

        if case .trip(let trip) = scope {
            html.append("<h2>\(escape(scope.title))</h2>")
            html.append("<p><i>\(escape(Fmt.range(trip.startDate, trip.endDate)))</i></p>")
            plain.append(scope.title)
            plain.append(Fmt.range(trip.startDate, trip.endDate))
            plain.append("")
        }
        for day in scope.days {
            let stops = day.liveStops
            if stops.isEmpty { continue }
            html.append("<h2>\(escape(day.headline))</h2>")
            html.append("<p><i>\(escape(Fmt.fullDay(day.date)))</i></p>")
            plain.append(day.headline)
            plain.append(Fmt.fullDay(day.date))
            plain.append("")
            for stop in stops {
                html.append("<h3>\(escape(stop.displayName))</h3>")
                var meta = Fmt.time(stop.timestamp, timeZoneID: stop.timeZoneID)
                if !stop.address.isEmpty { meta += " · \(stop.address)" }
                html.append("<p><small>\(escape(meta))</small></p>")
                plain.append(stop.displayName)
                plain.append(meta)
                if let cover = coverOutsideBody(of: stop) { photoMarker(cover) }

                var openList: String?
                func closeList() {
                    if let tag = openList { html.append("</\(tag)>"); openList = nil }
                }
                for block in stop.blocks {
                    let inline = inlineHTML(block.runs)
                    switch block.kind {
                    case .bullet, .checklist:
                        if block.plainText.isEmpty { continue }
                        if openList == nil { html.append("<ul>"); openList = "ul" }
                        let box = block.kind == .checklist ? (block.checked ? "☑︎ " : "☐ ") : ""
                        html.append("<li>\(box)\(inline)</li>")
                        plain.append("\(block.kind == .bullet ? "• " : box)\(block.plainText)")
                        continue
                    default:
                        closeList()
                    }
                    switch block.kind {
                    case .paragraph:
                        if block.plainText.isEmpty { continue }
                        html.append("<p>\(inline)</p>")
                        plain.append(block.plainText)
                    case .heading:
                        if block.plainText.isEmpty { continue }
                        html.append("<h4>\(inline)</h4>")
                        plain.append(block.plainText)
                    case .quote:
                        if block.plainText.isEmpty { continue }
                        html.append("<blockquote>\(inline)</blockquote>")
                        plain.append("“\(block.plainText)”")
                    case .photo:
                        if let photo = stop.photo(withID: block.photoID) { photoMarker(photo) }
                    case .location:
                        if let place = block.place {
                            let url = mapsURL(latitude: place.latitude, longitude: place.longitude, name: place.name)
                            html.append("<p>📍 <a href=\"\(escape(url))\">\(escape(place.name))</a></p>")
                            plain.append("📍 \(place.name)")
                        }
                    case .bullet, .checklist:
                        break
                    }
                }
                closeList()
                for photo in loosePhotos(of: stop) { photoMarker(photo) }
                if !stop.tagNames.isEmpty {
                    let tags = stop.tagNames.map { "#\($0)" }.joined(separator: " ")
                    html.append("<p style=\"color:#1AA6A0\">\(escape(tags))</p>")
                    plain.append(tags)
                }
                plain.append("")
            }
        }
        let document = "<meta charset=\"utf-8\">" + html.joined(separator: "\n")
        return (document, plain.joined(separator: "\n"), photos)
    }

    static func inlineHTML(_ runs: [InlineRun]) -> String {
        runs.map { run in
            var text = escape(run.text).replacingOccurrences(of: "\n", with: "<br>")
            if run.bold { text = "<b>\(text)</b>" }
            if let link = run.link { text = "<a href=\"\(escape(link))\">\(text)</a>" }
            return text
        }.joined()
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// 블로그 발행용: 사진을 순서대로 임시 파일로 저장해서 공유 시트로 넘긴다.
    static func temporaryPhotoFiles(_ photos: [Photo]) -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PawsShare", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (index, photo) in photos.enumerated() {
            guard let data = photo.imageData else { continue }
            let url = folder.appendingPathComponent(String(format: "%02d.jpg", index + 1))
            if (try? data.write(to: url)) != nil {
                urls.append(url)
            }
        }
        return urls
    }
}

/// 마크다운 + 이미지 폴더 내보내기용 문서
/// FileWrapper는 만든 뒤 바꾸지 않으므로 넘겨도 안전하다.
struct TripExportDocument: FileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.folder] }

    let wrapper: FileWrapper

    init(wrapper: FileWrapper) {
        self.wrapper = wrapper
    }

    init(configuration: ReadConfiguration) throws {
        self.wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }
}
