import XCTest
@testable import Shotty

final class ScreenshotSearchTests: XCTestCase {
    func testExactTagMatchRanksAheadOfOCRMatch() {
        let tagged = ScreenshotRecord(
            localIdentifier: "1",
            fileName: "receipt.png",
            extractedText: "coffee order",
            capturedAt: .now,
            userTags: ["receipt"],
            suggestedTags: [],
            pixelWidth: 100,
            pixelHeight: 200
        )
        let ocrOnly = ScreenshotRecord(
            localIdentifier: "2",
            fileName: "note.png",
            extractedText: "receipt details in the footer",
            capturedAt: .now.addingTimeInterval(-60),
            userTags: [],
            suggestedTags: [],
            pixelWidth: 100,
            pixelHeight: 200
        )

        let results = ScreenshotSearch.rank([tagged, ocrOnly], query: "receipt")

        XCTAssertEqual(results.first?.recordID, tagged.localIdentifier)
        XCTAssertEqual(results.first?.reason, "Tag match")
    }

    func testEmptyQueryReturnsAllRecordsInInputOrder() {
        let first = ScreenshotRecord(
            localIdentifier: "1",
            fileName: "first.png",
            extractedText: "",
            capturedAt: .now,
            userTags: [],
            suggestedTags: [],
            pixelWidth: 100,
            pixelHeight: 200
        )
        let second = ScreenshotRecord(
            localIdentifier: "2",
            fileName: "second.png",
            extractedText: "",
            capturedAt: .now.addingTimeInterval(-60),
            userTags: [],
            suggestedTags: [],
            pixelWidth: 100,
            pixelHeight: 200
        )

        let results = ScreenshotSearch.rank([first, second], query: "")

        XCTAssertEqual(results.map(\.recordID), [first.localIdentifier, second.localIdentifier])
    }
}
