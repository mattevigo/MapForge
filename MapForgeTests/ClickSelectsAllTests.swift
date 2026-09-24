import XCTest
@testable import MapForge

/// Which clicks select a field's whole value. The monitor sees every click in the app.
final class ClickSelectsAllTests: XCTestCase {

    func testTheClickThatEntersAFieldSelectsItsValue() {
        XCTAssertTrue(ClickSelectsAll.selectsAll(enteredField: true, isSendingField: false,
                                                 selectionLength: 0))
    }

    func testASecondClickInTheSameFieldPlacesTheCaret() {
        XCTAssertFalse(ClickSelectsAll.selectsAll(enteredField: false, isSendingField: false,
                                                  selectionLength: 0))
    }

    func testAHalfWrittenCommentIsNotSelected() {
        XCTAssertFalse(ClickSelectsAll.selectsAll(enteredField: true, isSendingField: true,
                                                  selectionLength: 0))
    }

    func testADragAcrossPartOfTheTextKeepsItsOwnSelection() {
        XCTAssertFalse(ClickSelectsAll.selectsAll(enteredField: true, isSendingField: false,
                                                  selectionLength: 3))
    }
}
