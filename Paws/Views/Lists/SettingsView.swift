import SwiftUI
import SwiftData

/// 저장 공간과 동기화 상태. 사진 용량이 iCloud 무료 공간을 넘기지 않는지 미리 본다.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var photos: [Photo]
    @Query private var trips: [Trip]
    @Query private var stops: [Stop]

    private var photoBytes: Int {
        photos.reduce(0) { $0 + $1.byteCount }
    }

    private var iCloudSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud") {
                    LabeledContent("동기화") {
                        Label(iCloudSignedIn ? "켜짐" : "iCloud 로그인 필요",
                              systemImage: iCloudSignedIn ? "checkmark.icloud" : "icloud.slash")
                            .foregroundStyle(iCloudSignedIn ? Theme.teal : .secondary)
                    }
                    Text("기록은 기기에 먼저 저장되고, 네트워크가 연결되면 iCloud 개인 영역으로 자동 동기화됩니다. 동기화는 백업이 아니므로 가끔 여행을 마크다운으로 내보내 두세요.")
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                }

                Section("저장 공간") {
                    LabeledContent("여행", value: "\(trips.filter { $0.deletedAt == nil }.count)개")
                    LabeledContent("일정", value: "\(stops.filter { $0.deletedAt == nil }.count)개")
                    LabeledContent("사진", value: "\(photos.count)장")
                    LabeledContent("사진 용량", value: ByteCountFormatter.string(fromByteCount: Int64(photoBytes), countStyle: .file))
                    Text("사진은 긴 변 2048px 사본만 보관합니다 (장당 약 0.5~1MB).")
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                }

                Section("빠른 기록") {
                    Text("단축어 앱이나 액션 버튼에 ‘Paws 빠른 기록’을 연결하면 앱 첫 화면을 거치지 않고 바로 카메라가 열리고, 현재 위치로 일정이 만들어집니다.")
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("저장 공간과 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}
