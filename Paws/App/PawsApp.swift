import SwiftUI
import SwiftData

@main
struct PawsApp: App {
    let container: ModelContainer

    init() {
        AppFont.register()
        container = PawsApp.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.teal)
                .task {
                    TripService.purgeTrash(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }

    static let schema = Schema([Trip.self, Day.self, Stop.self, Photo.self, Tag.self])

    /// 기기에 먼저 저장하고, iCloud(CloudKit 개인 DB)가 기기 간 복사를 맡는다.
    /// iCloud를 쓸 수 없는 상태(로그아웃, 서명 미설정)여도 로컬 저장으로 동작한다.
    static func makeContainer() -> ModelContainer {
        #if DEBUG
        if DemoData.isEnabled {
            // 시뮬레이터 확인용: 매번 빈 메모리 저장소에서 시작한다
            let memory = ModelConfiguration("PawsDemo", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
        #endif
        let cloud = ModelConfiguration(
            "Paws",
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.gomyong.paws")
        )
        if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
            return container
        }
        let local = ModelConfiguration("Paws", schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [local]) {
            return container
        }
        // 마지막 수단: 메모리 저장 (디스크 문제 등)
        let memory = ModelConfiguration("PawsMemory", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [memory])
    }
}
