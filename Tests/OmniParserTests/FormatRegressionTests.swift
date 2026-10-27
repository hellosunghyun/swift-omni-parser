import Foundation
import OmniParser
import XCTest

final class FormatRegressionTests: XCTestCase {
  func testVerticalKoreanTextInHWPImageIsPreserved() async throws {
    for name in ["RealWorld/hwp/real-hwp-01-noori.hwp",
                 "RealWorld/hwpx/real-hwpx-02-noori.hwpx"] {
      let result = try await DocumentParser.parse(TestFixtures.input(name),
        options: .init(performOCR: true))
      // 표 셀의 로켓 그림에 실제 인쇄된 세로 글자다. native 본문과 구분해 확인한다.
      XCTAssertTrue(result.blocks.contains {
        $0.kind == .imageOCR && $0.location.row == 2 && $0.location.column == 2
          && $0.text.filter { !$0.isWhitespace }.contains("대한민국")
      })
      TestFixtures.assertTextConsistency(result)
    }
  }

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

  func testJSONPreservesBooleansBesideNumbers() async throws {
    let source = #"{"enabled":true,"disabled":false,"numbers":[0,1,1.5],"value":null}"#
    let result = try await DocumentParser.parse(.data(Data(source.utf8), fileName: "values.json"))
    XCTAssertEqual(result.blocks.map(\.text), [
      "disabled: false", "enabled: true", "numbers[0]: 0", "numbers[1]: 1",
      "numbers[2]: 1.5", "value: null"
    ])
    XCTAssertTrue(result.warnings.isEmpty)
    TestFixtures.assertTextConsistency(result)
  }

  func testInlineSVGKeepsHTMLAndMarkdownBodies() async throws {
    let html = #"<html><body><p>Kept body</p><svg width="10"><text>Vector label</text></svg>"#
      + "<p>After icon</p></body></html>"
    let parsed = try await DocumentParser.parse(.data(Data(html.utf8), fileName: "inline.html"))
    XCTAssertEqual(parsed.format, .html)
    XCTAssertTrue(parsed.fullText.contains("Kept body"))
    XCTAssertTrue(parsed.fullText.contains("After icon"))
    XCTAssertTrue(parsed.warnings.contains {
      $0.code == .unsupportedElement && $0.location?.part == "html/svg[1]"
    })
    TestFixtures.assertTextConsistency(parsed)
    let markdown = "# SVG example\n```html\n<svg width='10'></svg>\n```\nKept example"
    let example = try await DocumentParser.parse(
      .data(Data(markdown.utf8), fileName: "example.md"))
    XCTAssertEqual(example.format, .markdown)
    XCTAssertTrue(example.fullText.contains("Kept example"))
    TestFixtures.assertTextConsistency(example)
  }

  func testStandaloneSVGRemainsUnsupported() async {
    for prefix in ["", "<?xml version='1.0'?>\n<!-- standalone -->\n",
                   "<!DOCTYPE svg PUBLIC '-//W3C//DTD SVG 1.1//EN' 'example.invalid/svg.dtd'>"] {
      do {
        let text = prefix + "<svg xmlns='http://www.w3.org/2000/svg' width='10'/>"
        _ = try await DocumentParser.parse(.data(Data(text.utf8), fileName: "vector.svg"))
        XCTFail("독립 SVG 문서를 지원 형식으로 판별했습니다.")
      } catch { XCTAssertEqual(error as? DocumentParsingError, .unsupportedFormat) }
    }
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
