import Foundation

/// 본문 블록 종류. 문법을 직접 치는 방식 대신 블록을 쌓는 구조다.
enum BlockKind: String, Codable, CaseIterable {
    case paragraph
    case heading
    case quote
    case checklist
    case bullet
    case photo
    case location

    /// 글을 입력하는 블록인지 (사진·위치 블록이 아닌지)
    var isText: Bool {
        self != .photo && self != .location
    }

    var label: String {
        switch self {
        case .paragraph: return "문단"
        case .heading: return "소제목"
        case .quote: return "인용"
        case .checklist: return "체크리스트"
        case .bullet: return "목록"
        case .photo: return "사진"
        case .location: return "위치"
        }
    }
}

/// 글 안의 서식 조각. 굵게와 링크만 지원한다.
struct InlineRun: Codable, Hashable {
    var text: String
    var bold: Bool = false
    var link: String? = nil
}

/// 위치 블록에 들어가는 장소
struct BlockPlace: Codable, Hashable {
    var name: String
    var address: String = ""
    var latitude: Double
    var longitude: Double
}

struct Block: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: BlockKind
    var runs: [InlineRun] = []
    var checked: Bool = false
    /// 사진 블록이 가리키는 Photo.uuid
    var photoID: UUID? = nil
    var place: BlockPlace? = nil

    init(kind: BlockKind, runs: [InlineRun] = []) {
        self.kind = kind
        self.runs = runs
    }

    init(kind: BlockKind, text: String) {
        self.kind = kind
        self.runs = text.isEmpty ? [] : [InlineRun(text: text)]
    }

    static func photo(_ id: UUID) -> Block {
        var block = Block(kind: .photo)
        block.photoID = id
        return block
    }

    static func location(_ place: BlockPlace) -> Block {
        var block = Block(kind: .location)
        block.place = place
        return block
    }

    var plainText: String {
        switch kind {
        case .location: return place?.name ?? ""
        case .photo: return ""
        default: return runs.map(\.text).joined()
        }
    }
}

extension Array where Element == InlineRun {
    /// 같은 서식의 인접 조각을 합치고 빈 조각을 버린다.
    func normalized() -> [InlineRun] {
        var result: [InlineRun] = []
        for run in self where !run.text.isEmpty {
            if var last = result.last, last.bold == run.bold, last.link == run.link {
                last.text += run.text
                result[result.count - 1] = last
            } else {
                result.append(run)
            }
        }
        return result
    }
}
