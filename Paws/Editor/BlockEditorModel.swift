import UIKit
import Observation

/// 블록 에디터 상태. 블록 목록, 포커스, 실행 취소, 자동 저장을 맡는다.
/// 한 블록 안의 글자 입력은 UITextView가 맡고, 블록 사이의 이동·분할·병합은 여기서 한다.
@MainActor
@Observable
final class BlockEditorModel {
    private(set) var blocks: [Block]
    /// 마지막으로 입력 중이던 블록. 툴바 버튼이 이 블록에 적용된다.
    var focusedID: UUID?
    private(set) var undoStack: [[Block]] = []
    private(set) var redoStack: [[Block]] = []

    /// 저장 콜백. 입력이 멈추고 0.6초 뒤, 또는 flush() 때 부른다.
    @ObservationIgnored var onCommit: (([Block]) -> Void)?

    @ObservationIgnored private var textViews: [UUID: WeakTextView] = [:]
    @ObservationIgnored private var pendingFocus: (id: UUID, caret: Int)?
    @ObservationIgnored private var lastTypingCheckpoint = Date.distantPast
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var linkRange: (id: UUID, range: NSRange)?

    init(blocks: [Block]) {
        self.blocks = blocks
        ensureWritableTail()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var focusedBlock: Block? {
        focusedID.flatMap { id in blocks.first { $0.id == id } }
    }

    func index(of id: UUID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    // MARK: 텍스트 뷰 등록과 포커스

    func register(_ textView: UITextView, for id: UUID) {
        textViews[id] = WeakTextView(view: textView)
    }

    func textView(for id: UUID) -> UITextView? {
        textViews[id]?.view
    }

    func requestFocus(_ id: UUID, caret: Int) {
        pendingFocus = (id, caret)
        Task { @MainActor [weak self] in
            self?.applyPendingFocus()
        }
    }

    /// 새 블록의 텍스트 뷰가 화면에 붙었을 때도 부른다.
    func applyPendingFocus() {
        guard let pending = pendingFocus,
              let textView = textViews[pending.id]?.view,
              textView.window != nil
        else { return }
        pendingFocus = nil
        textView.becomeFirstResponder()
        let length = textView.attributedText.length
        textView.selectedRange = NSRange(location: min(pending.caret, length), length: 0)
        focusedID = pending.id
    }

    func endEditing() {
        for box in textViews.values {
            box.view?.resignFirstResponder()
        }
    }

    // MARK: 입력

    func textChanged(_ id: UUID, runs: [InlineRun]) {
        guard let i = index(of: id), blocks[i].runs != runs else { return }
        // 입력이 1.5초 이상 멈췄다가 다시 시작되면 실행 취소 지점을 하나 남긴다
        if Date().timeIntervalSince(lastTypingCheckpoint) > 1.5 {
            checkpoint()
        }
        lastTypingCheckpoint = Date()
        blocks[i].runs = runs
        scheduleSave()
    }

    /// 엔터: 커서 위치에서 블록을 둘로 나눈다.
    func split(_ id: UUID, text: NSAttributedString, range: NSRange) {
        guard let i = index(of: id) else { return }
        let kind = blocks[i].kind
        checkpoint()

        // 빈 목록·체크리스트·인용에서 엔터를 치면 문단으로 돌아간다
        if text.length == 0 && (kind == .bullet || kind == .checklist || kind == .quote) {
            blocks[i].kind = .paragraph
            blocks[i].checked = false
            scheduleSave()
            return
        }

        let splitAt = min(range.location, text.length)
        let rightStart = min(range.location + range.length, text.length)
        let left = text.attributedSubstring(from: NSRange(location: 0, length: splitAt))
        let right = text.attributedSubstring(from: NSRange(location: rightStart, length: text.length - rightStart))

        blocks[i].runs = RunCodec.runs(from: left, kind: kind)
        let nextKind: BlockKind = (kind == .bullet || kind == .checklist) ? kind : .paragraph
        let next = Block(kind: nextKind, runs: RunCodec.runs(from: right, kind: kind))
        blocks.insert(next, at: i + 1)
        requestFocus(next.id, caret: 0)
        scheduleSave()
    }

    /// 블록 맨 앞에서 지우기: 서식 블록이면 문단으로, 문단이면 앞 블록과 합친다.
    func backspaceAtStart(_ id: UUID) {
        guard let i = index(of: id) else { return }
        let block = blocks[i]
        if block.kind != .paragraph {
            checkpoint()
            blocks[i].kind = .paragraph
            blocks[i].checked = false
            scheduleSave()
            return
        }
        guard i > 0 else { return }
        let previous = blocks[i - 1]
        if previous.kind.isText {
            checkpoint()
            let caret = (previous.plainText as NSString).length
            let runs = previous.kind == .heading ? block.runs.map { InlineRun(text: $0.text, link: $0.link) } : block.runs
            blocks[i - 1].runs = (previous.runs + runs).normalized()
            blocks.remove(at: i)
            requestFocus(previous.id, caret: caret)
            scheduleSave()
        } else if block.plainText.isEmpty {
            // 사진·위치 블록 바로 뒤의 빈 문단은 지운다. 사진 자체는 지우지 않는다.
            checkpoint()
            blocks.remove(at: i)
            if let target = blocks[..<i].lastIndex(where: { $0.kind.isText }) {
                requestFocus(blocks[target].id, caret: (blocks[target].plainText as NSString).length)
            }
            ensureWritableTail()
            scheduleSave()
        }
    }

    func toggleChecked(_ id: UUID) {
        guard let i = index(of: id) else { return }
        checkpoint()
        blocks[i].checked.toggle()
        scheduleSave()
    }

    // MARK: 툴바

    /// 소제목·인용·체크리스트·목록 전환. 이미 같은 종류면 문단으로 되돌린다.
    func toggleKind(_ kind: BlockKind) {
        guard kind.isText else { return }
        guard let id = focusedID, let i = index(of: id), blocks[i].kind.isText else {
            append(Block(kind: kind))
            return
        }
        checkpoint()
        let newKind: BlockKind = blocks[i].kind == kind ? .paragraph : kind
        blocks[i].kind = newKind
        if newKind != .checklist { blocks[i].checked = false }
        if newKind == .heading {
            blocks[i].runs = blocks[i].runs.map { InlineRun(text: $0.text, link: $0.link) }.normalized()
        }
        scheduleSave()
    }

    /// 선택 영역을 굵게. 선택이 없으면 이어서 칠 글자를 굵게.
    func toggleBold() {
        guard let id = focusedID, let i = index(of: id), let textView = textView(for: id) else { return }
        let kind = blocks[i].kind
        guard kind.isText, kind != .heading else { return }
        let range = textView.selectedRange

        if range.length == 0 {
            var typing = textView.typingAttributes
            let isBold = (typing[.pawsBold] as? Bool) == true
            typing[.pawsBold] = isBold ? nil : true
            typing[.font] = RunCodec.font(for: kind, bold: !isBold)
            textView.typingAttributes = typing
            return
        }

        var allBold = true
        textView.attributedText.enumerateAttribute(.pawsBold, in: range) { value, _, stop in
            if (value as? Bool) != true {
                allBold = false
                stop.pointee = true
            }
        }
        let text = NSMutableAttributedString(attributedString: textView.attributedText)
        if allBold {
            text.removeAttribute(.pawsBold, range: range)
            text.addAttribute(.font, value: RunCodec.font(for: kind, bold: false), range: range)
        } else {
            text.addAttribute(.pawsBold, value: true, range: range)
            text.addAttribute(.font, value: RunCodec.font(for: kind, bold: true), range: range)
        }
        textView.attributedText = text
        textView.selectedRange = range
        textChanged(id, runs: RunCodec.runs(from: text, kind: kind))
    }

    /// 링크 입력창을 띄우기 전에 선택 영역을 기억해 둔다. 기억할 대상이 없으면 false.
    func beginLink() -> Bool {
        guard let id = focusedID, let textView = textView(for: id), focusedBlock?.kind.isText == true else {
            return false
        }
        linkRange = (id, textView.selectedRange)
        return true
    }

    /// 선택한 글자에 링크를 건다. 선택이 없으면 주소 자체를 링크로 넣는다.
    func applyLink(_ raw: String) {
        guard let target = linkRange, let i = index(of: target.id) else { return }
        linkRange = nil
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        if !address.contains("://") { address = "https://" + address }
        guard URL(string: address) != nil else { return }

        checkpoint()
        let kind = blocks[i].kind
        let text = NSMutableAttributedString(attributedString: RunCodec.attributed(blocks[i].runs, kind: kind, checked: blocks[i].checked))
        let range = NSRange(location: min(target.range.location, text.length),
                            length: min(target.range.length, max(0, text.length - target.range.location)))
        if range.length > 0 {
            text.addAttribute(.link, value: URL(string: address)!, range: range)
        } else {
            var attributes = RunCodec.baseAttributes(for: kind)
            attributes[.link] = URL(string: address)!
            text.insert(NSAttributedString(string: address, attributes: attributes), at: range.location)
        }
        blocks[i].runs = RunCodec.runs(from: text, kind: kind)
        scheduleSave()
    }

    func removeLink() {
        guard let id = focusedID, let i = index(of: id), let textView = textView(for: id) else { return }
        let range = textView.selectedRange
        guard range.length > 0 else { return }
        checkpoint()
        let text = NSMutableAttributedString(attributedString: textView.attributedText)
        text.removeAttribute(.link, range: range)
        blocks[i].runs = RunCodec.runs(from: text, kind: blocks[i].kind)
        scheduleSave()
    }

    /// 사진 블록 넣기 (포커스된 블록 뒤, 없으면 끝)
    func insertPhotos(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        insert(ids.map(Block.photo))
    }

    func insertLocation(_ place: BlockPlace) {
        insert([Block.location(place)])
    }

    func removeBlock(_ id: UUID) {
        guard let i = index(of: id) else { return }
        checkpoint()
        blocks.remove(at: i)
        ensureWritableTail()
        scheduleSave()
    }

    func removePhotoBlocks(_ photoID: UUID) {
        guard blocks.contains(where: { $0.photoID == photoID }) else { return }
        checkpoint()
        blocks.removeAll { $0.photoID == photoID }
        ensureWritableTail()
        scheduleSave()
    }

    func moveBlock(_ id: UUID, by offset: Int) {
        guard let i = index(of: id) else { return }
        let target = i + offset
        guard blocks.indices.contains(target) else { return }
        checkpoint()
        blocks.swapAt(i, target)
        ensureWritableTail()
        scheduleSave()
    }

    /// 본문 아래 빈 곳을 누르면 마지막 글 블록으로 들어간다.
    func focusEnd() {
        ensureWritableTail()
        guard let last = blocks.last else { return }
        requestFocus(last.id, caret: (last.plainText as NSString).length)
    }

    private func append(_ block: Block) {
        checkpoint()
        if let last = blocks.last, last.kind == .paragraph, last.plainText.isEmpty {
            // 끝의 빈 문단을 새 종류로 바꿔 쓴다
            var replaced = block
            replaced.id = last.id
            blocks[blocks.count - 1] = replaced
            requestFocus(replaced.id, caret: 0)
        } else {
            blocks.append(block)
            requestFocus(block.id, caret: 0)
        }
        scheduleSave()
    }

    private func insert(_ newBlocks: [Block]) {
        checkpoint()
        var position = blocks.count
        if let id = focusedID, let i = index(of: id) {
            position = i + 1
            // 포커스된 블록이 빈 문단이면 그 자리를 대신 쓴다
            if blocks[i].kind == .paragraph && blocks[i].plainText.isEmpty && blocks.count > 1 {
                blocks.remove(at: i)
                position = i
            }
        }
        blocks.insert(contentsOf: newBlocks, at: position)
        ensureWritableTail()
        scheduleSave()
    }

    /// 마지막 블록이 사진·위치이면 이어 쓸 수 있게 빈 문단을 붙인다.
    private func ensureWritableTail() {
        if blocks.last?.kind.isText != true {
            blocks.append(Block(kind: .paragraph))
        }
    }

    // MARK: 실행 취소

    private func checkpoint() {
        undoStack.append(blocks)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(blocks)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(blocks)
        restore(next)
    }

    private func restore(_ snapshot: [Block]) {
        blocks = snapshot
        ensureWritableTail()
        // 텍스트 뷰 자체의 실행 취소 기록은 이제 맞지 않으므로 비운다
        for box in textViews.values {
            box.view?.undoManager?.removeAllActions()
        }
        lastTypingCheckpoint = .distantPast
        scheduleSave()
    }

    // MARK: 저장

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// 바로 저장한다. 화면을 떠날 때, 앱이 백그라운드로 갈 때 부른다.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard dirty else { return }
        dirty = false
        onCommit?(blocks)
    }
}

struct WeakTextView {
    weak var view: UITextView?
}
