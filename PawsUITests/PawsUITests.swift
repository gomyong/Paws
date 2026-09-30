import XCTest

/// 핵심 흐름 UI 테스트. iPhone 시뮬레이터 기준(화면 스택 전환)으로 쓴다.
/// 앱은 `--uitest`로 iCloud 없는 테스트 전용 저장소를 쓰고, `--mock-location`으로 위치를 고정한다.
final class PawsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        // 실패하면 화면 요소 트리를 로그에 남긴다 (CI 로그만 보고 원인을 찾기 위해)
        if let run = testRun, run.totalFailureCount > 0, let app {
            print("===== UI 트리: \(name) =====")
            print(String(app.debugDescription.prefix(12_000)))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "실패 화면"
            shot.lifetime = .keepAlways
            add(shot)
        }
        app = nil
    }

    // MARK: 도우미

    @discardableResult
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--mock-location=35.0116,135.7681,교토역"] + arguments
        app.launch()
        self.app = app
        return app
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func wait(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "화면에서 찾지 못함: \(element)", file: file, line: line)
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail(message, file: file, line: line)
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// 새 여행 → 새 일정(현재 위치) → 에디터까지
    private func createTripAndStop(title: String = "테스트 여행") {
        let newTrip = element("sidebar.newTrip")
        wait(newTrip)
        newTrip.tap()

        let titleField = element("trip.title")
        wait(titleField)
        titleField.tap()
        titleField.typeText(title)
        element("trip.save").tap()

        let addStop = element("timeline.addStop")
        wait(addStop)
        XCTAssertTrue(app.navigationBars[title].exists, "여행 화면 제목이 '\(title)'이 아님")
        addStop.tap()

        // ＋ → 장소 → 저장, 3탭
        let current = element("place.current")
        wait(current)
        waitUntil({ current.isEnabled }, "현재 위치가 준비되지 않음")
        current.tap()
        let save = element("stop.save")
        wait(save)
        save.tap()

        let placeName = element("editor.placeName")
        wait(placeName)
        XCTAssertEqual(placeName.value as? String, "교토역")
    }

    // MARK: 테스트

    /// F1 + F3: 여행 만들기 → 일정 추가 → 글쓰기(엔터로 블록 분할) → 목록 카드에 미리보기
    func testCreateTripAddStopAndWrite() {
        launch(["--reset-store"])
        createTripAndStop()

        let body = app.textViews.matching(identifier: "block.paragraph").firstMatch
        wait(body)
        body.tap()
        body.typeText("첫 줄 기록")
        body.typeText("\n")
        app.textViews.matching(identifier: "block.paragraph").element(boundBy: 1).typeText("두 번째 줄")
        XCTAssertEqual(app.textViews.matching(identifier: "block.paragraph").count, 2, "엔터로 블록이 나뉘지 않음")

        goBack()
        let card = element("stopCard")
        wait(card)
        waitUntil({ card.label.contains("첫 줄 기록") }, "카드 미리보기에 본문이 없음: \(card.label)")
        XCTAssertTrue(card.label.contains("교토역"))
    }

    /// 블록 서식 전환, 체크, 실행 취소
    func testChecklistAndUndo() {
        launch(["--reset-store"])
        createTripAndStop()

        let body = app.textViews.matching(identifier: "block.paragraph").firstMatch
        wait(body)
        body.tap()
        body.typeText("챙길 것")

        element("toolbar.checklist").tap()
        let checklist = app.textViews.matching(identifier: "block.checklist").firstMatch
        wait(checklist, timeout: 5)

        let unchecked = app.buttons["완료 안 됨"]
        wait(unchecked)
        unchecked.tap()
        wait(app.buttons["완료됨"], timeout: 5)

        element("toolbar.arrow.uturn.backward").tap()
        wait(app.buttons["완료 안 됨"], timeout: 5)

        // 다시 체크리스트 버튼 → 문단으로 되돌리기
        checklist.tap()
        element("toolbar.checklist").tap()
        wait(app.textViews.matching(identifier: "block.paragraph").firstMatch, timeout: 5)
    }

    /// 앱이 강제 종료돼도 작성 중인 글이 남는다
    func testTextSurvivesForceQuit() {
        launch(["--reset-store"])
        createTripAndStop(title: "종료 테스트")

        let body = app.textViews.matching(identifier: "block.paragraph").firstMatch
        wait(body)
        body.tap()
        body.typeText("꺼져도 남아야 하는 글")
        // 자동 저장 대기 (입력 멈춤 후 0.6초)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.terminate()

        launch([])
        let trip = element("sidebar.trip")
        wait(trip)
        trip.tap()
        let card = element("stopCard")
        wait(card)
        XCTAssertTrue(card.label.contains("꺼져도 남아야 하는 글"), "재실행 후 본문이 없음: \(card.label)")
        card.tap()
        let restored = app.textViews.matching(identifier: "block.paragraph").firstMatch
        wait(restored)
        XCTAssertEqual(restored.value as? String, "꺼져도 남아야 하는 글")
    }

    /// 태그 칩 입력 → 사이드바 태그 트리 → 태그 목록
    func testTagChipAndTagTree() {
        launch(["--reset-store"])
        createTripAndStop()

        let tagField = element("tag.input")
        wait(tagField)
        tagField.tap()
        tagField.typeText("음식/라멘\n")
        wait(app.staticTexts["#음식/라멘"], timeout: 5)

        goBack()
        goBack()
        let food = app.staticTexts["음식"]
        wait(food)
        let ramen = app.staticTexts["라멘"]
        wait(ramen)
        ramen.tap()
        wait(element("stopCard"))
    }

    /// P1 전체 검색
    func testSearchFindsStop() {
        launch(["--reset-store", "--demo", "--demo-open=home"])
        let search = element("sidebar.search")
        wait(search)
        search.tap()

        let field = app.searchFields.firstMatch
        wait(field)
        field.tap()
        field.typeText("라멘")
        let card = element("stopCard")
        wait(card)
        XCTAssertTrue(card.label.contains("멘야 이노이치"), "검색 결과가 다름: \(card.label)")
    }

    /// 휴지통으로 옮기고 복원
    func testTrashAndRestore() {
        launch(["--reset-store", "--demo", "--demo-open=trip"])
        let first = app.cells.containing(.any, identifier: "stopCard").firstMatch
        wait(first)
        let name = "후시미 이나리 신사"
        XCTAssertTrue(element("stopCard").label.contains(name))

        first.swipeLeft()
        app.buttons["삭제"].tap()
        waitUntil({ !self.element("stopCard").label.contains(name) }, "삭제한 일정이 목록에 남아 있음")

        goBack()
        let trash = element("sidebar.trash")
        wait(trash)
        trash.tap()
        wait(app.staticTexts[name])
        app.buttons["복원"].firstMatch.tap()
        waitUntil({ !self.app.staticTexts[name].exists }, "복원한 일정이 휴지통에 남아 있음")

        goBack()
        element("sidebar.trip").tap()
        wait(element("stopCard"))
        waitUntil({ self.element("stopCard").label.contains(name) }, "복원한 일정이 목록에 없음")
    }

    /// Day 지도: 카드 한 번 → 지도 이동, 두 번 → 에디터
    func testDayMapCardOpensEditor() {
        launch(["--reset-store", "--demo", "--demo-open=map"])
        let card = app.buttons.containing(.any, identifier: "stopCard").firstMatch
        wait(card)
        card.tap()
        card.tap()
        wait(element("editor.placeName"))
    }

    /// 읽기 모드 → 블로그용 복사
    func testReadingModeCopyForBlog() {
        launch(["--reset-store", "--demo", "--demo-open=reading"])
        let publish = element("reading.publish")
        wait(publish)
        wait(app.staticTexts["후시미 이나리 신사"])
        publish.tap()
        app.buttons["블로그용으로 복사"].tap()
        wait(element("toast"), timeout: 5)
    }

    /// 빠른 기록: 지금 위치 + 한 줄 → 오늘 날짜 여행에 일정 생성
    func testQuickCapture() {
        launch(["--reset-store"])
        let quick = element("sidebar.quickCapture")
        wait(quick)
        quick.tap()

        let name = element("quick.name")
        wait(name)
        waitUntil({ (name.value as? String) == "교토역" }, "빠른 기록에 현재 위치 이름이 채워지지 않음")
        let note = element("quick.note")
        note.tap()
        note.typeText("현장에서 한 줄")
        element("quick.save").tap()

        let placeName = element("editor.placeName")
        wait(placeName)
        let body = app.textViews.matching(identifier: "block.paragraph").firstMatch
        wait(body)
        XCTAssertEqual(body.value as? String, "현장에서 한 줄")
    }
}
