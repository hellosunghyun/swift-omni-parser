import Foundation
import OmniParser
import XCTest

final class FormatRegressionTests: XCTestCase {
  struct Entry: Decodable {
    let name: String
    let sha256: String
    let anchors: [String]
    let originID: String?
    let format: String?
    let minimumTextLength: Int?
    let minimumTableCells: Int?
    let minimumImages: Int?
  }

  func testExistingCorpusAndFixtureHashes() async throws {
    let entries: [Entry] = try TestFixtures.json("Manifest.json")
    XCTAssertEqual(entries.count, 65)
    XCTAssertEqual(Set(entries.map(\.sha256)).count, 65)
    for entry in entries {
      let bytes = try Data(contentsOf: TestFixtures.url(entry.name))
      XCTAssertTrue(TestFixtures.hash(bytes) == entry.sha256, entry.name)
      let result = try await DocumentParser.parse(TestFixtures.input(entry.name),
        options: .init(extractImages: true, performOCR: true))
      XCTAssertEqual(result.format.rawValue,
                     entry.format ?? (entry.name as NSString).pathExtension)
      XCTAssertGreaterThanOrEqual(result.fullText.count, entry.minimumTextLength ?? 1, entry.name)
      XCTAssertGreaterThanOrEqual(result.blocks.filter { $0.kind == .tableCell }.count,
                                 entry.minimumTableCells ?? 0, entry.name)
      XCTAssertGreaterThanOrEqual(result.images.count, entry.minimumImages ?? 0, entry.name)
      let normalized = result.fullText.split(whereSeparator: \.isWhitespace)
        .joined(separator: " ").lowercased()
      for anchor in entry.anchors {
        XCTAssertTrue(normalized.contains(anchor.split(whereSeparator: \.isWhitespace)
          .joined(separator: " ").lowercased()), "기대 문구 누락: \(entry.name)")
      }
      TestFixtures.assertTextConsistency(result)
      if let id = entry.originID {
        try DocumentGoldenAssertions.verify(result, id: id, sha256: entry.sha256)
      }
    }
  }

  func testGeneratedStructuresAndLocations() async throws {
    struct Provenance: Decodable { let name: String; let sha256: String }
    let records: [Provenance] = try TestFixtures.json("Generated/Provenance.json")
    for entry in records {
      XCTAssertTrue(TestFixtures.hash(try Data(contentsOf: TestFixtures.url(entry.name)))
        == entry.sha256)
      let result = try await DocumentParser.parse(TestFixtures.input(entry.name),
        options: .init(extractImages: true))
      XCTAssertTrue(result.blocks.allSatisfy { block in
        [block.location.row, block.location.column, block.location.page,
         block.location.rowSpan, block.location.columnSpan].compactMap { $0 }
          .allSatisfy { $0 > 0 }
      })
      TestFixtures.assertTextConsistency(result)
      if entry.name.hasSuffix("EmptyCells.ppt") {
        XCTAssertEqual(result.blocks.filter { $0.kind == .tableCell }.count, 4)
      }
      if entry.name.hasSuffix("TablePicture.ppt") { XCTAssertEqual(result.images.count, 1) }
      if entry.name.hasSuffix("Formatting.xlsx") {
        let cell = try XCTUnwrap(result.blocks.first { $0.text == "한글 셀" })
        XCTAssertEqual(cell.location.row, 2)
        XCTAssertEqual(cell.location.columnSpan, 2)
      }
    }
  }
}
