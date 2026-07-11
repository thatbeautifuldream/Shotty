import XCTest
@testable import Shotty

final class ScreenshotClassifierTests: XCTestCase {
    func testReceiptSignalsProduceReceiptAndAmountTags() {
        let classifier = ScreenshotClassifier()

        let suggestion = classifier.suggestTags(
            for: "Receipt\nSubtotal $18.00\nTax $2.00\nTotal $20.00\nPaid by Visa",
            fileName: "IMG_1001.PNG"
        )

        XCTAssertTrue(suggestion.tags.contains("receipt"))
        XCTAssertTrue(suggestion.tags.contains("amount"))
    }

    func testNoSignalsFallsBackToUntagged() {
        let classifier = ScreenshotClassifier()

        let suggestion = classifier.suggestTags(for: "", fileName: "Screenshot")

        XCTAssertEqual(suggestion.tags, ["untagged"])
    }
}
