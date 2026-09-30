import SwiftUI
import PhotosUI

/// 하단 플로팅 서식 툴바. 한 손 입력에 맞춰 버튼을 크게 둔다.
struct FormattingToolbar: View {
    let model: BlockEditorModel
    @Binding var photoItems: [PhotosPickerItem]
    var onLink: () -> Void
    var onLocation: () -> Void

    private var focusedKind: BlockKind? {
        model.focusedBlock?.kind
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                kindButton(.heading, icon: "textformat.size", label: "소제목")
                kindButton(.checklist, icon: "checklist", label: "체크리스트")
                kindButton(.bullet, icon: "list.bullet", label: "목록")
                kindButton(.quote, icon: "text.quote", label: "인용")

                divider

                toolButton(icon: "bold", label: "굵게") { model.toggleBold() }
                    .keyboardShortcut("b", modifiers: .command)
                toolButton(icon: "link", label: "링크") { onLink() }
                    .keyboardShortcut("k", modifiers: .command)

                divider

                PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                    toolIcon("photo")
                }
                .accessibilityLabel("사진 블록")
                toolButton(icon: "mappin.and.ellipse", label: "위치 블록") { onLocation() }

                divider

                toolButton(icon: "arrow.uturn.backward", label: "실행 취소") { model.undo() }
                    .disabled(!model.canUndo)
                    .opacity(model.canUndo ? 1 : 0.35)
                toolButton(icon: "arrow.uturn.forward", label: "다시 실행") { model.redo() }
                    .disabled(!model.canRedo)
                    .opacity(model.canRedo ? 1 : 0.35)
                toolButton(icon: "keyboard.chevron.compact.down", label: "키보드 내리기") { model.endEditing() }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 52)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }

    private func toolIcon(_ name: String, active: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(active ? Theme.teal : Color.primary)
            .frame(width: 44, height: 44)
            .background(active ? Theme.teal.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }

    private func toolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolIcon(icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func kindButton(_ kind: BlockKind, icon: String, label: String) -> some View {
        Button {
            model.toggleKind(kind)
        } label: {
            toolIcon(icon, active: focusedKind == kind)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(focusedKind == kind ? .isSelected : [])
    }
}
