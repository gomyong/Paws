import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 저장 공간과 동기화 상태. 사진 용량이 iCloud 무료 공간을 넘기지 않는지 미리 본다.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var photos: [Photo]
    @Query private var trips: [Trip]
    @Query private var stops: [Stop]
    @State private var backup: TripExportDocument?
    @State private var showingBackup = false
    @State private var backupResult: String?

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

                Section {
                    Button {
                        backup = TripExportDocument(wrapper: Exporter.backup(trips.filter { $0.deletedAt == nil }))
                        showingBackup = true
                    } label: {
                        Label("모든 여행 내보내기 (마크다운 + 사진)", systemImage: "externaldrive")
                    }
                    .disabled(trips.allSatisfy { $0.deletedAt != nil })
                    if let backupResult {
                        Text(backupResult)
                            .font(.pawsCaption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("백업")
                } footer: {
                    Text("여행마다 폴더를 만들어 글은 마크다운, 사진은 원본 사본으로 저장합니다. 파일 앱의 iCloud Drive나 외장 저장소에 두세요.")
                }

                Section("빠른 기록") {
                    Text("제어 센터·잠금화면 버튼, 홈 화면 위젯, 액션 버튼, 단축어에 ‘Paws 빠른 기록’을 두면 바로 카메라가 열리고 현재 위치로 일정이 만들어집니다.")
                        .font(.pawsCaption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .fileExporter(
                isPresented: $showingBackup,
                document: backup,
                contentType: .folder,
                defaultFilename: "Paws 백업 \(Fmt.iso(DayMath.normalize(.now)))"
            ) { result in
                switch result {
                case .success: backupResult = "내보냈어요."
                case .failure(let error): backupResult = "내보내지 못했어요: \(error.localizedDescription)"
                }
                backup = nil
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
