import CoreGraphics
import Foundation
@testable import OmniParser
import PDFKit
import XCTest

/// 같은 PDF의 네이티브 문구와 근접한 별도 그림 숫자를 모두 보존한다.
final class PDFAdjacentTextPublicTests: XCTestCase {
  func testOwnedPDFKeepsAdjacentRasterNumberAndNativeText() async throws {
    let bytes = try Data(contentsOf: TestFixtures.url(
      "PDFAdjacentText/adjacent-native-number.pdf"))
    let document = try XCTUnwrap(PDFDocument(data: bytes))
    let page = try XCTUnwrap(document.page(at: 0))
    let reference = try XCTUnwrap(page.pageRef)
    let space = DocumentPDFPageSpace(page: reference)
    let lines = page.selection(for: reference.getBoxRect(.mediaBox))?.selectionsByLine() ?? []
    let line = try XCTUnwrap(lines.first { Self.normalized($0.string ?? "") == "item12" })
    let nativeBounds = space.normalized(line.bounds(for: page))
    let result = try await DocumentParser.parse(
      .data(bytes, fileName: "adjacent-native-number.pdf"),
      options: .init(extractImages: true, performOCR: true))
    let recognized = result.blocks.filter {
      $0.kind == .imageOCR && $0.location.part != nil && Self.normalized($0.text) == "12"
    }
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.images.first?.pngData.isEmpty == false)
    XCTAssertEqual(result.blocks.filter { $0.kind == .image }.count, 1)
    let native = result.blocks.filter {
      $0.kind == .paragraph && Self.normalized($0.text) == "item12"
    }
    XCTAssertEqual(native.count, 1)
    XCTAssertEqual(native.first?.location.bounds, nativeBounds)
    XCTAssertTrue(result.warnings.isEmpty)
    XCTAssertEqual(recognized.count, 1)
    XCTAssertNotNil(recognized.first?.ocrConfidence)
    XCTAssertEqual(recognized.first?.location.part, result.images.first?.location.part)
    let bounds = try XCTUnwrap(recognized.first?.location.bounds)
    XCTAssertFalse(nativeBounds.intersects(bounds))
    XCTAssertTrue(nativeBounds.insetBy(dx: -0.005, dy: -0.005).intersects(bounds))
    XCTAssertGreaterThan(bounds.minX - nativeBounds.maxX, 0)
    XCTAssertEqual(Self.normalized(result.fullText), "item1212")
    TestFixtures.assertTextConsistency(result)
  }

  private static func normalized(_ text: String) -> String {
    text.lowercased().filter { !$0.isWhitespace }
  }
}
