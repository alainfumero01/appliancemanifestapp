import XCTest
@testable import ApplianceManifest

final class ApplianceManifestTests: XCTestCase {
    func testModelNumberNormalizationRemovesSeparatorsAndUppercases() {
        XCTAssertEqual(ModelNumberNormalizer.normalize("wrx-123 / a"), "WRX123A")
    }

    @MainActor
    func testSpreadsheetExportIncludesExpectedColumns() throws {
        let manifest = Manifest(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            title: "Friday Load",
            loadReference: "LOAD-17",
            ownerID: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            status: .draft,
            items: [
                ManifestItem(
                    id: UUID(),
                    manifestID: UUID(),
                    modelNumber: "ABC123",
                    productName: "Washer",
                    msrp: 599.99,
                    quantity: 2,
                    photoPath: "stickers/path.jpg",
                    lookupStatus: .confirmed,
                    createdAt: Date(timeIntervalSince1970: 0)
                )
            ]
        )

        let exported = try SpreadsheetExportService().export(manifest: manifest)
        let contents = try String(contentsOf: exported.fileURL)
        XCTAssertTrue(contents.contains("\"Manifest Name\""))
        XCTAssertTrue(contents.contains("\"ABC123\""))
        XCTAssertTrue(contents.contains("\"1199.98\""))
    }
}
