import CoreGraphics
import CoreText
import Foundation
import ImageIO
import OmniParser
import XCTest

/// 외부 자산 없이 같은 그림의 표시 위치만 바꿔 PDF OCR 중복을 검사한다.
final class PDFImageOverlapRegressionTests: XCTestCase {
  private static let marker = "OVERLAP MARKER"
  private let first = CGRect(x: 60, y: 500, width: 420, height: 70)

  func testIdenticalImagePlacementsKeepOneVisibleOCR() async throws {
    let result = try await parse(pages: [[first, first]], name: "identical")
    assertMarkerCount(1, in: result)
    assertImagesPreserved(2, in: result)
    let recognized = markerBlocks(in: result)
    XCTAssertTrue(recognized.first?.location.part == result.images.first?.location.part)
  }

  func testSeparatedSameTextPlacementsRemainDistinct() async throws {
    let second = first.offsetBy(dx: 0, dy: -200)
    let result = try await parse(pages: [[first, second]], name: "separated")
    assertMarkerCount(2, in: result)
    assertImagesPreserved(2, in: result)
    let bounds = markerBlocks(in: result).compactMap(\.location.bounds)
    XCTAssertEqual(bounds.count, 2)
    if bounds.count == 2 { XCTAssertFalse(bounds[0].intersects(bounds[1])) }
  }

  func testSameTextOnDifferentPagesRemainsDistinct() async throws {
    let result = try await parse(pages: [[first], [first]], name: "different-pages")
    assertMarkerCount(2, in: result)
    assertImagesPreserved(2, in: result)
    XCTAssertEqual(markerBlocks(in: result).filter { $0.location.page == 1 }.count, 1)
    XCTAssertEqual(markerBlocks(in: result).filter { $0.location.page == 2 }.count, 1)
  }

  func testPartlyOverlappingImagesKeepBothVisibleLines() async throws {
    // 그림의 흰 여백은 겹치지만 두 줄의 실제 글자는 가리지 않는 위치다.
    let second = first.offsetBy(dx: 40, dy: -45)
    XCTAssertTrue(first.intersects(second))
    let result = try await parse(pages: [[first, second]], name: "partial-overlap")
    assertMarkerCount(2, in: result)
    assertImagesPreserved(2, in: result)
    let bounds = markerBlocks(in: result).compactMap(\.location.bounds)
    XCTAssertEqual(bounds.count, 2)
    if bounds.count == 2 { XCTAssertNotEqual(bounds[0], bounds[1]) }
  }

  func testNativeBodyAndDuplicatePictureAreBothPreserved() async throws {
    let result = try await parse(
      pages: [[first, first]], name: "native-and-identical", nativeBody: true)
    assertMarkerCount(1, in: result)
    assertImagesPreserved(2, in: result)
    XCTAssertEqual(result.blocks.filter {
      $0.kind == .paragraph && normalized($0.text) == "nativebody"
    }.count, 1)
  }

  func testNativeLayerAtPicturePositionIsNotDuplicated() async throws {
    let result = try await parse(pages: [[first]], name: "same-native-layer",
      nativeSamePosition: true)
    assertMarkerCount(0, in: result, fullTextExpected: 1)
    assertImagesPreserved(1, in: result)
    XCTAssertEqual(result.blocks.filter {
      $0.kind == .paragraph && normalized($0.text) == normalized(Self.marker)
    }.count, 1)
  }

  private func parse(
    pages: [[CGRect]], name: String, nativeBody: Bool = false,
    nativeSamePosition: Bool = false
  ) async throws -> DocumentParseResult {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
    var box = CGRect(x: 0, y: 0, width: 600, height: 800)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    let image = try markerImage()
    for placements in pages {
      context.beginPDFPage(nil)
      if nativeBody { draw("NATIVE BODY", in: context, at: CGPoint(x: 60, y: 700), size: 24) }
      if nativeSamePosition, let placement = placements.first {
        draw(Self.marker, in: context,
          at: CGPoint(x: placement.minX + 15, y: placement.minY + 25), size: 21)
      }
      // 같은 CGImage를 재사용해 원본 차이 없이 표시 위치만 바꾼다.
      for placement in placements { context.draw(image, in: placement) }
      context.endPDFPage()
    }
    context.closePDF()
    let data = bytes as Data
    let result = try await DocumentParser.parse(.data(data, fileName: "\(name).pdf"),
      options: .init(extractImages: true, performOCR: true))
    return result
  }

  private func markerImage() throws -> CGImage {
    let context = try XCTUnwrap(CGContext(data: nil, width: 840, height: 140,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 840, height: 140))
    draw(Self.marker, in: context, at: CGPoint(x: 30, y: 50), size: 42)
    return try XCTUnwrap(context.makeImage())
  }

  private func draw(_ value: String, in context: CGContext, at point: CGPoint, size: CGFloat) {
    let text = NSAttributedString(string: value, attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String):
        CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil),
      NSAttributedString.Key(kCTForegroundColorAttributeName as String):
        CGColor(gray: 0, alpha: 1)
    ])
    context.textMatrix = .identity
    context.textPosition = point
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
  }

  private func normalized(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  private func markerBlocks(in result: DocumentParseResult) -> [DocumentBlock] {
    result.blocks.filter { $0.kind == .imageOCR && normalized($0.text) == normalized(Self.marker) }
  }

  private func assertMarkerCount(
    _ expected: Int, in result: DocumentParseResult,
    fullTextExpected: Int? = nil, file: StaticString = #filePath, line: UInt = #line
  ) {
    let count = markerBlocks(in: result).count
    let textCount = normalized(result.fullText)
      .components(separatedBy: normalized(Self.marker)).count - 1
    XCTAssertEqual(count, expected, file: file, line: line)
    XCTAssertEqual(textCount, fullTextExpected ?? expected, file: file, line: line)
    XCTAssertFalse(result.warnings.contains {
      $0.code == .imageOCRFailed || $0.code == .extractionFailed
    }, file: file, line: line)
    TestFixtures.assertTextConsistency(result, file: file, line: line)
  }

  private func assertImagesPreserved(
    _ expected: Int, in result: DocumentParseResult,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(result.images.count, expected, file: file, line: line)
    XCTAssertEqual(Set(result.images.map(\.id)).count, expected, file: file, line: line)
    let imageBlocks = result.blocks.filter { $0.kind == .image }
    XCTAssertEqual(imageBlocks.count, expected, file: file, line: line)
    XCTAssertTrue(result.images.allSatisfy { !$0.pngData.isEmpty && $0.location.part != nil },
      file: file, line: line)
  }
}
