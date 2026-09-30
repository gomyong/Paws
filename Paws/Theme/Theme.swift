import SwiftUI
import UIKit
import CoreText

/// 차분한 톤 + Teal 포인트 하나.
/// 색상 값은 PRD의 제안값이며 실기기에서 보고 확정한다.
enum Theme {
    /// 포인트 컬러. 라이트 #1AA6A0, 다크 #2BC4BD (제안값)
    static let tealUI = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x2B / 255, green: 0xC4 / 255, blue: 0xBD / 255, alpha: 1)
            : UIColor(red: 0x1A / 255, green: 0xA6 / 255, blue: 0xA0 / 255, alpha: 1)
    }
    static let teal = Color(uiColor: tealUI)

    /// Bear 스타일 차콜 사이드바 (근사 #2C3137)
    static let sidebar = Color(red: 0x2C / 255, green: 0x31 / 255, blue: 0x37 / 255)

    /// 여행 지도에서 Day별로 선 톤을 구분한다. 같은 Teal 계열 안에서 밝기·색조만 바꾼다.
    static func dayColor(_ index: Int) -> Color {
        let tones: [(Double, Double, Double)] = [
            (0.49, 0.85, 0.65),
            (0.52, 0.70, 0.50),
            (0.46, 0.80, 0.80),
            (0.55, 0.60, 0.70),
            (0.44, 0.65, 0.55),
            (0.50, 0.45, 0.85),
        ]
        let tone = tones[index % tones.count]
        return Color(hue: tone.0, saturation: tone.1, brightness: tone.2)
    }

    static let cardCorner: CGFloat = 10
}

/// 한글은 Pretendard, 영문·숫자는 SF Pro.
/// 시스템 폰트를 기본으로 두고 Pretendard를 cascade(대체 글꼴)로 붙이면
/// SF에 없는 한글 글리프만 Pretendard로 그려진다.
enum AppFont {
    static func register() {
        for name in ["Pretendard-Regular", "Pretendard-SemiBold", "Pretendard-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "otf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func ui(size: CGFloat, weight: UIFont.Weight = .regular, style: UIFont.TextStyle = .body) -> UIFont {
        let hangul: String
        if weight.rawValue >= UIFont.Weight.bold.rawValue {
            hangul = "Pretendard-Bold"
        } else if weight.rawValue >= UIFont.Weight.semibold.rawValue {
            hangul = "Pretendard-SemiBold"
        } else {
            hangul = "Pretendard-Regular"
        }
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let cascade = UIFontDescriptor(fontAttributes: [.name: hangul])
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [cascade]])
        let font = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
}

extension Font {
    /// 본문 17pt 기준 앱 글꼴. Dynamic Type 크기에 맞춰 커진다.
    static func paws(_ size: CGFloat, weight: UIFont.Weight = .regular, relativeTo style: UIFont.TextStyle = .body) -> Font {
        Font(AppFont.ui(size: size, weight: weight, style: style) as CTFont)
    }

    static var pawsBody: Font { Font.paws(17) }
    static var pawsCaption: Font { Font.paws(13, relativeTo: .caption1) }
    static var pawsHeadline: Font { Font.paws(17, weight: .semibold, relativeTo: .headline) }
    static var pawsTitle: Font { Font.paws(28, weight: .bold, relativeTo: .largeTitle) }
    static var pawsSubtitle: Font { Font.paws(22, weight: .bold, relativeTo: .title2) }
}
