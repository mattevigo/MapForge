import XCTest
@testable import MapForge

@MainActor
final class FogAutosaveTests: XCTestCase {

    func testABurstOfEditsWritesOnce() {
        // Drawing a Wall produces a burst of edits — one per vertex, and more while a
        // span is being dragged. Writing the whole document on each would put a file
        // write in the middle of a gesture.
        var writes = 0
        let autosave = FogAutosave(delay: 0.05) { _ in writes += 1 }
        for i in 1...20 {
            autosave.schedule(FogDocument(walls: [Wall(from: .zero, to: CGPoint(x: i, y: 0))]))
        }
        XCTAssertEqual(writes, 0, "wrote during the burst")

        expectEventually { writes == 1 }
        XCTAssertEqual(writes, 1)
    }

    func testTheLastEditIsTheOneSaved() {
        // A debounce that saved the first edit of a burst would persist a half-drawn Wall.
        var saved: FogDocument?
        let autosave = FogAutosave(delay: 0.05) { saved = $0 }
        let first = FogDocument(walls: [Wall(from: .zero, to: CGPoint(x: 1, y: 0))])
        let last = FogDocument(walls: [Wall(from: .zero, to: CGPoint(x: 99, y: 0))])
        autosave.schedule(first)
        autosave.schedule(last)

        expectEventually { saved != nil }
        XCTAssertEqual(saved, last)
    }

    func testPendingWorkIsFlushedOnDemand() {
        // Quitting or switching Maps must not drop an edit still sitting in the debounce.
        var saved: FogDocument?
        let autosave = FogAutosave(delay: 60) { saved = $0 }
        let document = FogDocument(walls: [Wall(from: .zero, to: CGPoint(x: 1, y: 0))])
        autosave.schedule(document)
        autosave.flush()
        XCTAssertEqual(saved, document, "an edit was dropped")
    }

    func testFlushWithNothingPendingWritesNothing() {
        var writes = 0
        let autosave = FogAutosave(delay: 60) { _ in writes += 1 }
        autosave.flush()
        XCTAssertEqual(writes, 0)
    }

    // MARK: Helpers

    /// Spins the main run loop until `condition` holds. The debounce schedules onto the
    /// main queue, so a blocking wait would deadlock it.
    private func expectEventually(_ condition: @escaping () -> Bool,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "condition never held", file: file, line: line)
    }
}
