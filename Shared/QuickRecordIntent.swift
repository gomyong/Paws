import AppIntents

/// 잠금화면·제어 센터·홈 화면 위젯·액션 버튼·단축어에서 "지금 위치 + 사진 1장" 기록을 연다.
/// 앱과 위젯 확장 양쪽에 들어간다. 실제 동작(handler)은 앱 프로세스에서만 설정된다.
struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "빠른 기록"
    static var description = IntentDescription("현재 위치로 새 일정을 만들고 카메라를 엽니다.")
    static var openAppWhenRun: Bool = true

    /// 앱이 시작할 때 설정한다. 위젯 확장에서는 nil.
    @MainActor static var handler: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}
