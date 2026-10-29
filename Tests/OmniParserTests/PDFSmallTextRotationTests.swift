import CoreGraphics
import CoreText
import Foundation
import OmniParser
import PDFKit
import XCTest

final class PDFSmallTextRotationTests: XCTestCase {
  func testSmallEnglishAndKoreanTextPreservesRotatedPageCoordinates() async throws {
    let cases: [(DocumentOCRLanguage, [String])] = [
      (.english, ["INVOICE", "TOTAL125.00"]),
      (.koreanAndEnglish, ["영수증", "TOTAL125.00"])
    ]
    for (language, lines) in cases {
      let image = try bitmap(lines)
      for rotation in [0, 90] {
        let result = try await DocumentParser.parse(
          .data(try pdf(image, rotation: rotation), fileName: "small-text.pdf"),
          options: .init(extractImages: true, performOCR: true, ocrLanguage: language))
        XCTAssertEqual(normalized(result.fullText), normalized(lines.joined()),
                       "언어 \(language.rawValue), 회전 \(rotation)의 문구가 다릅니다.")
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertTrue(result.images.first?.pngData.isEmpty == false)
        let placement = try XCTUnwrap(result.images.first?.location.bounds)
        XCTAssertEqual(placement.minX, 0.1, accuracy: 0.000001)
        XCTAssertEqual(placement.minY, 51.0 / 180, accuracy: 0.000001)
        XCTAssertEqual(placement.width, 0.8, accuracy: 0.000001)
        XCTAssertEqual(placement.height, 64.0 / 180, accuracy: 0.000001)
        let recognized = result.blocks.filter { $0.kind == .imageOCR }
        XCTAssertFalse(recognized.isEmpty)
        for block in recognized {
          let confidence = try XCTUnwrap(block.ocrConfidence)
          XCTAssertTrue(confidence.isFinite && (0...1).contains(confidence))
          XCTAssertEqual(block.location.page, 1)
          let bounds = try XCTUnwrap(block.location.bounds)
          XCTAssertTrue([bounds.minX, bounds.minY, bounds.width, bounds.height]
            .allSatisfy(\.isFinite))
          XCTAssertGreaterThan(bounds.width, 0)
          XCTAssertGreaterThan(bounds.height, 0)
          XCTAssertGreaterThanOrEqual(bounds.minX, 0)
          XCTAssertGreaterThanOrEqual(bounds.minY, 0)
          XCTAssertLessThanOrEqual(bounds.maxX, 1.000001)
          XCTAssertLessThanOrEqual(bounds.maxY, 1.000001)
        }
        XCTAssertEqual(result.blocks.map(\.readingOrder), Array(result.blocks.indices))
        TestFixtures.assertTextConsistency(result)
      }
    }
  }

  private func bitmap(_ lines: [String]) throws -> CGImage {
    let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 64,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 64))
    let font = CTFontCreateWithName("AppleSDGothicNeo-Regular" as CFString, 22, nil)
    for (index, text) in lines.enumerated() {
      let line = NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
          CGColor(gray: 0, alpha: 1)
      ])
      context.textPosition = CGPoint(x: 0, y: 44 - index * 28)
      CTLineDraw(CTLineCreateWithAttributedString(line), context)
    }
    return try XCTUnwrap(context.makeImage())
  }

  private func pdf(_ image: CGImage, rotation: Int) throws -> Data {
    let data = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: data))
    var box = rotation == 0 ? CGRect(x: 0, y: 0, width: 300, height: 180)
      : CGRect(x: 0, y: 0, width: 180, height: 300)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    if rotation == 90 {
      // PDF의 시계 방향 회전을 상쇄해 최종 표시와 글자는 정방향으로 유지한다.
      context.translateBy(x: 180, y: 0)
      context.rotate(by: .pi / 2)
    }
    context.draw(image, in: CGRect(x: 30, y: 65, width: 240, height: 64))
    context.endPDFPage()
    context.closePDF()
    let document = try XCTUnwrap(PDFDocument(data: data as Data))
    let page = try XCTUnwrap(document.page(at: 0))
    page.rotation = rotation
    return try XCTUnwrap(document.dataRepresentation())
  }

  private func normalized(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace }
  }
}
