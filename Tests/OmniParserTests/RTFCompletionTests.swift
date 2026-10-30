import Foundation
import OmniParser
import XCTest

final class RTFCompletionTests: XCTestCase {
  func testHeadersFootersRetainTextAndSourceScopes() async throws {
    let source = "{\\rtf1\\ansi{\\header Header marker\\par}"
      + "{\\footer Footer marker\\par}Body marker\\par}"
    let result = try await parse(source)
    for (value, scope) in [("Header marker", "header"), ("Footer marker", "footer"),
                           ("Body marker", "")] {
      let block = try XCTUnwrap(result.blocks.first { $0.text == value })
      XCTAssertEqual(result.blocks.filter { $0.text == value }.count, 1)
      XCTAssertTrue(block.location.part?.hasPrefix("rtf/\(scope)") == true || scope.isEmpty)
      if !scope.isEmpty {
        XCTAssertTrue(result.warnings.contains {
          $0.code == .uncertainReadingOrder && $0.location?.part == block.location.part
        })
      }
    }
    XCTAssertFalse(result.fullText.contains("OMNIRTF"))
    TestFixtures.assertTextConsistency(result)
  }

  func testHeaderPictureAndBodyPictureKeepSeparatePositions() async throws {
    let hex = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
      .map { String(format: "%02x", $0) }.joined()
    let source = "{\\rtf1{\\header Header{\\pict\\pngblip \(hex)}}"
      + "Body{\\pict\\pngblip \(hex)}End}"
    let result = try await parse(source, options: .init(extractImages: true))
    XCTAssertEqual(result.images.count, 2)
    XCTAssertTrue(result.images[0].location.part?.hasPrefix("rtf/header/byte[") == true)
    XCTAssertTrue(result.images[1].location.part?.hasPrefix("rtf/byte[") == true)
    XCTAssertFalse(result.warnings.contains { $0.code == .unsupportedElement })
    XCTAssertTrue(result.fullText.contains("Body"))
    XCTAssertTrue(result.fullText.contains("End"))
    TestFixtures.assertTextConsistency(result)
  }

  func testHeaderAndBodyTablesHaveDistinctPaths() async throws {
    let row = "\\trowd\\cellx4000\\intbl VALUE\\cell\\row\\pard "
    let source = "{\\rtf1{\\header \(row.replacingOccurrences(of: "VALUE", with: "Header cell"))}"
      + row.replacingOccurrences(of: "VALUE", with: "Body cell") + "}"
    let result = try await parse(source)
    let header = try XCTUnwrap(result.blocks.first { $0.text == "Header cell" })
    let body = try XCTUnwrap(result.blocks.first { $0.text == "Body cell" })
    XCTAssertEqual(header.kind, .tableCell)
    XCTAssertEqual(body.kind, .tableCell)
    XCTAssertNotEqual(header.location.part, body.location.part)
    XCTAssertTrue(header.location.part?.hasPrefix("rtf/header/") == true)
    XCTAssertTrue(body.location.part?.hasPrefix("rtf/table[") == true)
    TestFixtures.assertTextConsistency(result)
  }

  func testNestedTablesPreserveParentCellHierarchy() async throws {
    let source = """
    {\\rtf1\\ansi
    \\trowd\\cellx6000\\pard\\intbl\\itap1 Outer before\\par
    \\trowd\\itap2\\cellx3000\\pard\\intbl\\itap2 Inner cell\\nestcell
    {\\*\\nesttableprops\\trowd\\itap2\\cellx3000\\nestrow}
    \\pard\\intbl\\itap1 Outer after\\cell\\row\\pard End}
    """
    let result = try await parse(source)
    let inner = try XCTUnwrap(result.blocks.first { $0.text.contains("Inner cell") })
    XCTAssertEqual(inner.kind, .tableCell)
    XCTAssertTrue(inner.location.part?.contains("/cell[1,1]/table[") == true)
    XCTAssertTrue(result.fullText.contains("Outer before"))
    XCTAssertTrue(result.fullText.contains("Outer after"))
    XCTAssertTrue(result.fullText.contains("End"))
    TestFixtures.assertTextConsistency(result)
  }

  private func parse(
    _ source: String, options: DocumentParserOptions = .init()
  ) async throws -> DocumentParseResult {
    try await DocumentParser.parse(.data(Data(source.utf8), fileName: "generated.rtf"),
                                   options: options)
  }
}
