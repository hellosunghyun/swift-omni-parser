import CoreGraphics
import Foundation
@testable import OmniParser
import XCTest

final class PDFPaddingGeometryTests: XCTestCase {
  func testPaddingHonorsPixelBudgetBeforeAllocation() {
    XCTAssertNil(DocumentPDFImageExtractor.paddingSize(
      width: 97, height: 57, maximumPixels: 11_480))
    XCTAssertEqual(DocumentPDFImageExtractor.paddingSize(
      width: 97, height: 57, maximumPixels: 11_481), CGSize(width: 129, height: 89))
    XCTAssertEqual(DocumentPDFImageExtractor.paddingSize(
      width: 968, height: 968, maximumPixels: .max), CGSize(width: 1_000, height: 1_000))
    XCTAssertNil(DocumentPDFImageExtractor.paddingSize(
      width: 969, height: 968, maximumPixels: .max))
  }

  func testPaddingRejectsInvalidAndOverflowingDimensions() {
    for (width, height, limit) in [
      (0, 57, 40_000_000), (-1, 57, 40_000_000), (97, 0, 40_000_000),
      (97, -1, 40_000_000), (Int.max, 57, Int.max), (97, Int.max, Int.max),
      (97, 57, 0), (97, 57, -1)
    ] {
      XCTAssertNil(DocumentPDFImageExtractor.paddingSize(
        width: width, height: height, maximumPixels: limit))
    }
  }

  func testUnpaddingClipsObservedRecognitionToOriginalImage() {
    // 고정 진단의 OCR bounds는 여백까지 포함하므로 원래 그림과 겹친 영역만 반환한다.
    let observed = CGRect(x: 0.000000001923076863564487, y: 0.17777777444444443,
      width: 0.9076923076923078, height: 0.6666666666666667)
    XCTAssertEqual(DocumentPDFImageExtractor.unpaddedBounds(
      observed, cropWidth: 97, cropHeight: 57), CGRect(x: 0, y: 0, width: 1, height: 1))
  }

  func testUnpaddingRestoresInsetTextCoordinates() throws {
    let padded = CGRect(x: 36.0 / 132, y: 26.0 / 82,
      width: 30.0 / 132, height: 20.0 / 82)
    let restored = try XCTUnwrap(DocumentPDFImageExtractor.unpaddedBounds(
      padded, cropWidth: 100, cropHeight: 50))
    XCTAssertEqual(restored.minX, 0.2, accuracy: 0.000000000001)
    XCTAssertEqual(restored.minY, 0.2, accuracy: 0.000000000001)
    XCTAssertEqual(restored.width, 0.3, accuracy: 0.000000000001)
    XCTAssertEqual(restored.height, 0.4, accuracy: 0.000000000001)
  }

  func testUnpaddingRejectsMissingInvalidAndMarginOnlyBounds() {
    let invalid: [CGRect?] = [nil, .null, .infinite, .zero,
      CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
      CGRect(x: 0, y: 0, width: -1, height: 1),
      CGRect(x: 0, y: 0, width: 1, height: CGFloat.infinity),
      CGRect(x: 0, y: 0, width: 8.0 / 129, height: 8.0 / 89),
      CGRect(x: 120.0 / 129, y: 16.0 / 89, width: 8.0 / 129, height: 16.0 / 89)]
    for bounds in invalid {
      XCTAssertNil(DocumentPDFImageExtractor.unpaddedBounds(
        bounds, cropWidth: 97, cropHeight: 57))
    }
    XCTAssertNil(DocumentPDFImageExtractor.unpaddedBounds(
      CGRect(x: 0, y: 0, width: 1, height: 1), cropWidth: 0, cropHeight: 57))
  }
}
