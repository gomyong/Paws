import SwiftUI
import SwiftData

/// 일정 화면의 태그 칩 입력. "음식/라멘"처럼 중첩 이름을 쓸 수 있다.
struct TagEditor: View {
    let stop: Stop

    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var input = ""
    @FocusState private var focused: Bool

    private var stopTags: [Tag] {
        (stop.tags ?? []).sorted { $0.name < $1.name }
    }

    private var suggestions: [Tag] {
        let typed = Tag.clean(input).lowercased()
        let current = Set(stopTags.map(\.name))
        return allTags
            .filter { !current.contains($0.name) }
            .filter { typed.isEmpty || $0.name.lowercased().contains(typed) }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(stopTags) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag.name)")
                            .font(.pawsCaption.weight(.medium))
                        Button {
                            TripService.removeTag(tag, from: stop)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tag.name) 태그 빼기")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.teal)
                    .background(Theme.teal.opacity(0.12), in: Capsule())
                }
                TextField("#태그", text: $input)
                    .font(.pawsCaption)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .frame(width: 130)
                    .padding(.vertical, 5)
                    .onSubmit { commit(input) }
                    .onChange(of: input) { _, value in
                        // 쉼표나 띄어쓰기로 칩 확정
                        if let last = value.last, last == "," || last == " " {
                            commit(String(value.dropLast()))
                        }
                    }
            }
            if focused && !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions) { tag in
                            Button("#\(tag.name)") {
                                commit(tag.name)
                            }
                            .font(.pawsCaption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func commit(_ raw: String) {
        let cleaned = Tag.clean(raw)
        input = ""
        guard !cleaned.isEmpty else { return }
        TripService.addTag(cleaned, to: stop, context: context)
    }
}
