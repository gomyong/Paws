import SwiftUI
import UIKit

/// 블록 하나의 글 입력 칸. 높이는 내용에 맞춰 늘어난다.
struct BlockTextView: UIViewRepresentable {
    let block: Block
    let model: BlockEditorModel
    var placeholder: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PawsTextView {
        let textView = PawsTextView()
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.allowsEditingTextAttributes = false
        textView.dataDetectorTypes = []
        textView.linkTextAttributes = [
            .foregroundColor: Theme.tealUI,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = context.coordinator

        let coordinator = context.coordinator
        textView.onBackspaceAtStart = { [weak coordinator] in
            coordinator?.backspaceAtStart()
        }
        textView.onAttachedToWindow = { [weak coordinator] in
            coordinator?.parent.model.applyPendingFocus()
        }

        coordinator.apply(block, to: textView)
        textView.placeholder = placeholder
        model.register(textView, for: block.id)
        return textView
    }

    func updateUIView(_ textView: PawsTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        textView.placeholder = placeholder
        model.register(textView, for: block.id)

        // 한글 조합 중에는 절대 텍스트를 덮어쓰지 않는다
        guard textView.markedTextRange == nil else { return }
        if block.runs != coordinator.lastRuns || block.kind != coordinator.lastKind || block.checked != coordinator.lastChecked {
            let selection = textView.selectedRange
            coordinator.apply(block, to: textView)
            let length = textView.attributedText.length
            let location = min(selection.location, length)
            textView.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PawsTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var lastRuns: [InlineRun] = []
        var lastKind: BlockKind = .paragraph
        var lastChecked = false

        init(parent: BlockTextView) {
            self.parent = parent
        }

        func apply(_ block: Block, to textView: PawsTextView) {
            textView.attributedText = RunCodec.attributed(block.runs, kind: block.kind, checked: block.checked)
            textView.typingAttributes = RunCodec.baseAttributes(for: block.kind, checked: block.checked)
            textView.accessibilityLabel = block.kind == .paragraph ? "본문" : block.kind.label
            lastRuns = block.runs
            lastKind = block.kind
            lastChecked = block.checked
            textView.updatePlaceholder()
        }

        func backspaceAtStart() {
            parent.model.backspaceAtStart(parent.block.id)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.model.focusedID = parent.block.id
        }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? PawsTextView)?.updatePlaceholder()
            guard textView.markedTextRange == nil else { return }
            let runs = RunCodec.runs(from: textView.attributedText, kind: lastKind)
            lastRuns = runs
            parent.model.textChanged(parent.block.id, runs: runs)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" && textView.markedTextRange == nil {
                parent.model.split(parent.block.id, text: textView.attributedText, range: range)
                return false
            }
            return true
        }
    }
}

/// 맨 앞에서의 지우기와 화면 부착 시점을 알려 주는 UITextView
final class PawsTextView: UITextView {
    var onBackspaceAtStart: (() -> Void)?
    var onAttachedToWindow: (() -> Void)?

    var placeholder: String? {
        didSet {
            placeholderLabel.text = placeholder
            updatePlaceholder()
        }
    }

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.textColor = .placeholderText
        label.font = RunCodec.font(for: .paragraph, bold: false)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textContainer.lineFragmentPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: textContainerInset.top + 4),
        ])
        return label
    }()

    func updatePlaceholder() {
        guard placeholder != nil else { return }
        placeholderLabel.isHidden = !(attributedText?.length == 0) || markedTextRange != nil
    }

    override func deleteBackward() {
        if markedTextRange == nil, selectedRange.location == 0, selectedRange.length == 0 {
            onBackspaceAtStart?()
            return
        }
        super.deleteBackward()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onAttachedToWindow?()
        }
    }
}
