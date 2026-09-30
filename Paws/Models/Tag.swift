import Foundation
import SwiftData

/// 경로형 태그. "음식/라멘"처럼 /로 중첩한다.
@Model
final class Tag {
    var name: String = ""
    var stops: [Stop]? = []

    init(name: String) {
        self.name = name
    }
}

extension Tag {
    /// 사용자가 입력한 태그 문자열을 정리한다. "#음식 / 라멘 " → "음식/라멘"
    static func clean(_ raw: String) -> String {
        raw.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    /// 태그 경로가 prefix 경로와 같거나 그 하위인지
    static func name(_ name: String, isWithin prefix: String) -> Bool {
        name == prefix || name.hasPrefix(prefix + "/")
    }
}
