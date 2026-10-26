import CoreGraphics
import CoreText
import Foundation
import ImageIO
import OmniParser
import UniformTypeIdentifiers
import XCTest

final class ImageAndPDFRegressionTests: XCTestCase {
  func testDirectImageInputAndTIFFFrameOrientation() async throws {
    let image = try markerImage()
    let direct = try await DocumentParser.parse(.image(image, orientation: .up),
      options: .init(extractImages: true))
    XCTAssertEqual(direct.format, .image)
    XCTAssertEqual(direct.images.count, 1)
    let bytes = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
      bytes, UTType.tiff.identifier as CFString, 2, nil))
    CGImageDestinationAddImage(destination, image,
      [kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue] as CFDictionary)
    CGImageDestinationAddImage(destination, image,
      [kCGImagePropertyOrientation: CGImagePropertyOrientation.right.rawValue] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let result = try await DocumentParser.parse(.data(bytes as Data, fileName: "frames.tiff"),
      options: .init(extractImages: true))
    XCTAssertEqual(result.images.map(\.location.page), [1, 2])
    XCTAssertEqual(result.images.map(\.orientation), [.up, .right])
    TestFixtures.assertTextConsistency(result)
  }

  func testNativeScannedAndMixedPDF() async throws {
    for pages in [[false], [true], [false, true]] {
      let result = try await DocumentParser.parse(.data(try pdf(pages), fileName: "pages.pdf"),
        options: .init(extractImages: true, performOCR: true))
      if pages.contains(false) { XCTAssertTrue(result.fullText.contains("NATIVE PAGE MARKER")) }
      if pages.contains(true) {
        XCTAssertTrue(result.blocks.contains {
          $0.kind == .imageOCR && $0.text.contains("IMAGE OCR MARKER")
        })
      }
      if pages.count == 2 {
        XCTAssertTrue(result.blocks.contains { $0.kind == .imageOCR && $0.location.page == 2 })
      }
      TestFixtures.assertTextConsistency(result)
    }
  }

  private func markerImage() throws -> CGImage {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(
      TestFixtures.url("LegacyImage.png") as CFURL, nil))
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }

  /// 같은 자체 그림으로 일반·스캔·혼합 문서를 생성해 외부 PDF 자산에 의존하지 않는다.
  private func pdf(_ scannedPages: [Bool]) throws -> Data {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
    var box = CGRect(x: 0, y: 0, width: 600, height: 300)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    for scanned in scannedPages {
      context.beginPDFPage(nil)
      if scanned {
        context.draw(try markerImage(), in: CGRect(x: 0, y: 50, width: 600, height: 120))
      } else {
        let text = NSAttributedString(string: "NATIVE PAGE MARKER", attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String):
            CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        ])
        context.textPosition = CGPoint(x: 20, y: 200)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
      }
      context.endPDFPage()
    }
    context.closePDF()
    return bytes as Data
  }
}
