# Paws 🐾

여행의 날짜·장소·사진·글을 한 흐름으로 남기고, 지도 위 동선으로 다시 훑어보는 나 혼자 쓰는 iPhone/iPad 앱.
기획 문서는 [docs/PRD.md](docs/PRD.md).

- SwiftUI 유니버설 앱 (`NavigationSplitView` 3단 → iPhone에서는 화면 스택)
- SwiftData + iCloud(CloudKit 개인 DB) 동기화, 오프라인 우선
- MapKit(SwiftUI Map), CoreLocation, PhotosPicker/ImageIO, App Intents
- 외부 의존성 없음 (서드파티 SDK·분석 도구 없음)

## 실행하기

1. Xcode 16 이상에서 `Paws.xcodeproj`를 연다.
2. **Paws 타깃 → Signing & Capabilities**에서 Team을 본인 계정으로 고른다.
3. 번들 ID `com.gomyong.paws`가 이미 쓰이고 있으면 바꾸고, 그에 맞춰 iCloud 컨테이너도 바꾼다.
   - `Config/Paws.entitlements`의 `iCloud.com.gomyong.paws`
   - `Paws/App/PawsApp.swift`의 `.private("iCloud.com.gomyong.paws")`
4. iPhone·iPad 실기기를 골라 실행한다. (최소 iOS 18. 본인 기기 버전에 맞춰 `IPHONEOS_DEPLOYMENT_TARGET`을 올려도 된다.)

iCloud 컨테이너가 준비되지 않았거나 로그아웃 상태여도 앱은 로컬 저장으로 동작한다.
CloudKit 스키마는 배포 후 바꾸기 어려우므로, 실기기에서 데이터 모델을 확정한 뒤 CloudKit Console에서 Production으로 배포한다.

## 구조

```
Paws/
  App/        앱 진입점, 3단 레이아웃(RootView), 내비게이션 상태, 빠른 기록 App Intent
  Models/     Trip → Day → Stop → Photo·Tag, 본문 Block
  Services/   날짜 계산, 여행·일정 서비스, 사진 가져오기, 위치·장소 검색, 내보내기, 사진→일정 묶기
  Editor/     블록 에디터 (모델, UITextView 블록, 하단 플로팅 툴바)
  Views/      사이드바, 여행 타임라인, 일정 에디터, 지도, 읽기 모드, 검색·태그·휴지통·설정
  Theme/      Teal 포인트 컬러, 차콜 사이드바, Pretendard + SF Pro 글꼴
  Resources/  Pretendard 폰트 (SIL OFL)
Config/       Info.plist(백그라운드 알림), entitlements(iCloud)
```

Xcode 16의 폴더 동기화 그룹을 쓰므로 `Paws/` 안에 파일을 추가하면 프로젝트에 자동으로 들어간다.

## PRD 대응 현황

| 항목 | 상태 | 구현 위치 |
| --- | --- | --- |
| F1 일자별 여정 기록 | ✅ 여행 기간에 맞춰 Day 자동 생성, Day 제목·이모지, 시각순 자동 정렬 + 드래그, 소급 추가, ＋ → 장소 → 저장 | `TripService`, `TripTimelineView`, `NewStopSheet` |
| F2 일정별 사진 | ✅ 보관함 여러 장(최대 20장/회)·카메라·iPad 드래그 앤 드롭, 대표 사진, EXIF 촬영 시각·위치, 긴 변 2048px 사본, 백그라운드 리사이즈 | `PhotoImporter`, `PhotoStrip`, `StopEditorView` |
| F3 메모/블로그 | ✅ 블록 에디터(문단·소제목·인용·체크리스트·목록·사진·위치, 굵게·링크), 자동 저장, 실행 취소, 읽기 모드 | `Editor/`, `ReadingView` |
| F4 위치를 잇는 지도 | ✅ Day 지도(번호 핀 + 경로선, 핀↔카드 연동), 여행 지도(Day별 선 톤), 미니 지도, 위치 수정 | `DayMapView`, `TripMapView`, `MapPinPicker` |
| P1 사진으로 일정 자동 생성 | ✅ 촬영 시각(1시간)·거리(500m)로 묶어 일정 초안 | `PhotoStopBuilder` |
| P1 빠른 기록 | 🟡 App Intent(단축어·액션 버튼) + 앱 내 카메라 버튼. 잠금화면 위젯은 위젯 확장 타깃이 필요해 다음 단계 | `QuickRecordIntent`, `QuickCaptureView` |
| P1 전체 검색과 태그 | ✅ 글·장소·주소·태그 통합 검색, 중첩 태그 트리, 태그 필터 | `SearchView`, `SidebarView` |
| P1 iCloud 동기화 | ✅ SwiftData CloudKit (모든 속성 기본값/옵셔널, 사진은 externalStorage 에셋) | `PawsApp`, `Models/` |
| P1 내보내기 + 블로그 복사 | ✅ 마크다운 + images 폴더, 블로그용 HTML 복사, 사진 순서대로 공유 | `Exporter`, `ReadingView` |
| 30일 휴지통 | ✅ 여행·일정 소프트 삭제, 앱 실행 시 30일 지난 항목 정리 | `TrashView`, `TripService.purgeTrash` |
| iPad 에디터 \| 지도 2분할 | ✅ 일정 목록 열을 접고 에디터 옆에 Day 지도 | `StopEditorView` |
| 키보드 단축키 | ✅ ⌘N 새 일정, ⌘F 검색, ⌘B 굵게, ⌘K 링크 | |

## 설계 메모

- **날짜**: 여행·Day 날짜는 달력 날짜를 UTC 정오로 정규화해 저장한다(`DayMath`). 일정 시각은 절대 시각 + 현지 시간대 ID로 저장해서 귀국 후에도 현지 시각으로 보인다.
- **본문**: `[Block]`을 JSON으로 `Stop.bodyData`에 저장하고, 검색용 평문은 `searchText`에 따로 둔다. 마크다운·HTML은 내보낼 때 블록에서 만든다.
- **에디터**: 블록마다 `UITextView` 하나. 한글 조합(markedText) 중에는 텍스트를 덮어쓰지 않는다. 엔터는 블록 분할, 맨 앞 지우기는 서식 해제 → 앞 블록과 병합. 입력이 멈추면 0.6초 뒤 저장, 화면을 떠나거나 앱이 백그라운드로 가면 즉시 저장.
- **사진**: `@Attribute(.externalStorage)`라서 이미지 바이트는 DB 밖 파일로 저장되고 CloudKit에는 에셋으로 올라간다. 원본을 지워도 기록은 남는다.
- **블로그 발행**: 네이버 블로그·브런치는 붙여넣은 이미지를 올리지 않으므로, 서식 글을 복사할 때 사진 자리는 `[사진 N]`으로 두고 사진은 같은 순서로 따로 공유·저장한다. 실제 에디터 붙여넣기 결과는 M0에서 시험해 형식을 확정한다.

## 알려진 한계와 다음 단계

- 이 저장소는 Linux 환경에서 작성되어 **아직 Xcode로 빌드해 보지 않았다.** 첫 빌드에서 나오는 컴파일 오류는 그대로 전달해 주면 고친다.
- 잠금화면·홈 화면 위젯(WidgetKit)과 Control Center 버튼은 위젯 확장 타깃을 추가해야 한다.
- MapKit은 오프라인 지도 다운로드를 제공하지 않는다. 배경 지도는 캐시된 범위만 보이고, 핀·경로선·기록은 항상 보인다.
- Apple Maps 국내 장소 검색 품질은 실제 장소 10곳으로 먼저 확인한다(`PlaceSearch`만 바꾸면 다른 검색 서비스로 교체 가능).
- Teal 색상 값(라이트 #1AA6A0 / 다크 #2BC4BD)은 제안값이다. `Theme.swift`와 `AccentColor`에서 확정한다.
