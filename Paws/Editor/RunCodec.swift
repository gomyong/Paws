import UIKit

extension NSAttributedString.Key {
    /// 굵게 표시. 폰트 특성 대신 별도 속성으로 들고 다녀야 한글 cascade 폰트에서도 확실하다.
    static let pawsBold = NSAttributedString.Key("pawsBold")
}

/// InlineRun 목록 ↔ UITextView용 NSAttributedString 변환
enum RunCodec {
    static let bodySize: CGFloat = 17
    static let headingSize: CGFloat = 22

    static func font(for kind: BlockKind, bold: Bool) -> UIFont {
        switch kind {
        case .heading:
            return AppFont.ui(size: headingSize, weight: .bold, style: .title2)
        default:
            return AppFont.ui(size: bodySize, weight: bold ? .bold : .regular, style: .body)
        }
    }

    static func paragraphStyle(for kind: BlockKind) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        // 본문 줄 간격 1.6
        style.lineHeightMultiple = kind == .heading ? 1.25 : 1.6
        return style
    }

    static func color(for kind: BlockKind, checked: Bool) -> UIColor {
        if kind == .quote || (kind == .checklist && checked) { return .secondaryLabel }
        return .label
    }

    static func baseAttributes(for kind: BlockKind, checked: Bool = false) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: kind, bold: false),
            .paragraphStyle: paragraphStyle(for: kind),
            .foregroundColor: color(for: kind, checked: checked),
        ]
        if kind == .checklist && checked {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    static func attributed(_ runs: [InlineRun], kind: BlockKind, checked: Bool = false) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for run in runs {
            var attributes = baseAttributes(for: kind, checked: checked)
            if run.bold && kind != .heading {
                attributes[.font] = font(for: kind, bold: true)
                attributes[.pawsBold] = true
            }
            if let link = run.link, let url = URL(string: link) {
                attributes[.link] = url
            }
            output.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return output
    }

    static func runs(from text: NSAttributedString, kind: BlockKind) -> [InlineRun] {
        var result: [InlineRun] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let piece = string.substring(with: range)
            let bold = kind != .heading && (attributes[.pawsBold] as? Bool) == true
            var link: String?
            if let url = attributes[.link] as? URL {
                link = url.absoluteString
            } else if let raw = attributes[.link] as? String {
                link = raw
            }
            result.append(InlineRun(text: piece, bold: bold, link: link))
        }
        return result.normalized()
    }
}
