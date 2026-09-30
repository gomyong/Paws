import AppIntents

/// 단축어 앱·액션 버튼에 노출되는 앱 단축어
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
