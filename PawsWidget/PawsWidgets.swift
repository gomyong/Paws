import WidgetKit
import SwiftUI
import AppIntents

@main
struct PawsWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickRecordWidget()
        QuickRecordControl()
    }
}

private let teal = Color(red: 0x1A / 255, green: 0xA6 / 255, blue: 0xA0 / 255)

/// 제어 센터·잠금화면·액션 버튼에 두는 빠른 기록 버튼
struct QuickRecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.gomyong.paws.quickrecord.control") {
            ControlWidgetButton(action: QuickRecordIntent()) {
                Label("빠른 기록", systemImage: "pawprint.fill")
            }
        }
        .displayName("Paws 빠른 기록")
        .description("지금 위치와 사진 한 장으로 일정을 남깁니다.")
    }
}

struct QuickRecordEntry: TimelineEntry {
    let date: Date
}

struct QuickRecordProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickRecordEntry {
        QuickRecordEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickRecordEntry) -> Void) {
        completion(QuickRecordEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickRecordEntry>) -> Void) {
        completion(Timeline(entries: [QuickRecordEntry(date: .now)], policy: .never))
    }
}

/// 홈 화면·잠금화면 위젯: 누르면 빠른 기록이 열린다
struct QuickRecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.gomyong.paws.quickrecord", provider: QuickRecordProvider()) { _ in
            QuickRecordWidgetView()
        }
        .configurationDisplayName("빠른 기록")
        .description("지금 위치와 사진 한 장으로 일정을 남깁니다.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct QuickRecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: QuickRecordIntent()) {
            content
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                teal
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "pawprint.fill")
                    .font(.title3)
            }
            .widgetAccentable()
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                VStack(alignment: .leading) {
                    Text("Paws")
                        .font(.headline)
                    Text("빠른 기록")
                        .font(.caption)
                }
            }
            .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                Text("빠른 기록")
                    .font(.headline)
                Text("지금 위치 + 사진 1장")
                    .font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
