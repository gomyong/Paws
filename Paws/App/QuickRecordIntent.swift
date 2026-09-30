import AppIntents

/// 잠금화면·액션 버튼·단축어에서 "지금 위치 + 사진 1장" 기록을 연다.
struct QuickRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "빠른 기록"
    static var description = IntentDescription("현재 위치로 새 일정을 만들고 카메라를 엽니다.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCapture.shared.isPresented = true
        return .result()
    }
}

struct PawsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickRecordIntent(),
            phrases: [
                "\(.applicationName) 빠른 기록",
                "\(.applicationName)로 기록",
            ],
            shortTitle: "빠른 기록",
            systemImageName: "camera.fill"
        )
    }
}
