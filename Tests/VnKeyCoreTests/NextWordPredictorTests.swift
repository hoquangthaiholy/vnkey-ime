import XCTest
@testable import VnKeyCore

final class NextWordPredictorTests: XCTestCase {

    private func uniqueWord(_ label: String) -> String {
        // Namespaced per-test so runs never collide with seed data or each other
        // in the shared UserDefaults-backed table.
        "vnkeytest_\(label)_\(UUID().uuidString.prefix(8))".lowercased()
    }

    func testSeedBigramIsAvailableBeforeAnyLearning() {
        // "cảm" -> "ơn" is a built-in seed pair, so it should already be a top
        // prediction even for a freshly-created predictor (no learning yet).
        XCTAssertTrue(NextWordPredictor.shared.predictNextWords(after: "cảm").contains("ơn"))
        // Case-insensitive lookup.
        XCTAssertTrue(NextWordPredictor.shared.predictNextWords(after: "Cảm").contains("ơn"))
    }

    func testUnknownPreviousWordHasNoPrediction() {
        let previous = uniqueWord("neverseen")
        XCTAssertEqual(NextWordPredictor.shared.predictNextWords(after: previous), [])
    }

    func testLearnsFromRepeatedTransitions() {
        let previous = uniqueWord("prev")
        let frequent = uniqueWord("frequent")
        let rare = uniqueWord("rare")

        NextWordPredictor.shared.recordTransition(from: previous, to: frequent)
        NextWordPredictor.shared.recordTransition(from: previous, to: frequent)
        NextWordPredictor.shared.recordTransition(from: previous, to: frequent)
        NextWordPredictor.shared.recordTransition(from: previous, to: rare)

        let predictions = NextWordPredictor.shared.predictNextWords(after: previous)
        XCTAssertEqual(predictions.first, frequent) // more frequent transition ranks first
        XCTAssertTrue(predictions.contains(rare))
    }

    func testRecordTransitionIsCaseInsensitiveAndTrimsNothingButLowercases() {
        let previous = uniqueWord("Prev")
        let next = uniqueWord("Next")

        NextWordPredictor.shared.recordTransition(from: previous, to: next)

        // Looking up with different casing than what was recorded still matches.
        XCTAssertTrue(NextWordPredictor.shared.predictNextWords(after: previous.uppercased())
            .contains(next.lowercased()))
    }

    func testEmptyPreviousOrNextIsIgnored() {
        let previous = uniqueWord("prev2")
        NextWordPredictor.shared.recordTransition(from: "", to: previous)
        NextWordPredictor.shared.recordTransition(from: previous, to: "")
        XCTAssertEqual(NextWordPredictor.shared.predictNextWords(after: previous), [])
        XCTAssertEqual(NextWordPredictor.shared.predictNextWords(after: ""), [])
    }

    func testPerKeyNextWordCountIsBounded() {
        let previous = uniqueWord("wide")
        // Record more distinct next-words than the internal per-key cap (8) allows.
        for i in 0..<20 {
            let next = uniqueWord("next\(i)")
            NextWordPredictor.shared.recordTransition(from: previous, to: next)
        }
        let predictions = NextWordPredictor.shared.predictNextWords(after: previous, limit: 100)
        XCTAssertLessThanOrEqual(predictions.count, 8)
    }
}
