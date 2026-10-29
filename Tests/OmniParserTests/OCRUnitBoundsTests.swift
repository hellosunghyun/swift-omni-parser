import CoreGraphics
import Foundation
@testable import OmniParser
import XCTest

final class OCRUnitBoundsTests: XCTestCase {
  func testClipsObservedNegativePageOCRBounds() throws {
    // 실제 공개 결과의 좌상단 좌표를 Vision 좌하단 좌표로 되돌린 재현값이다.
    let observed = CGRect(x: -0.0002094086828842294, y: 0.045013578229232465,
      width: 0.1879188174293155, height: 0.019347843442644397)
    let raw = CGRect(x: observed.minX, y: 1 - observed.maxY,
      width: observed.width, height: observed.height)
    let result = try XCTUnwrap(DocumentOCR.normalizedBounds(raw))
    XCTAssertEqual(result.minX, 0)
    XCTAssertEqual(result.minY, 0.045013578229232465, accuracy: 0.000000000001)
    XCTAssertEqual(result.width, 0.18770940874643127, accuracy: 0.000000000001)
    XCTAssertEqual(result.height, 0.019347843442644397, accuracy: 0.000000000001)
  }

  func testClipsOvershootBeforeChangingCoordinateOrigin() throws {
    let upper = try XCTUnwrap(DocumentOCR.normalizedBounds(
      CGRect(x: 0.75, y: 0.8, width: 0.5, height: 0.4)))
    XCTAssertEqual(upper.minX, 0.75)
    XCTAssertEqual(upper.minY, 0)
    XCTAssertEqual(upper.width, 0.25)
    XCTAssertEqual(upper.height, 0.2, accuracy: 0.000000000001)
    let lower = try XCTUnwrap(DocumentOCR.normalizedBounds(
      CGRect(x: -0.2, y: -0.1, width: 0.4, height: 0.3)))
    XCTAssertEqual(lower.minX, 0)
    XCTAssertEqual(lower.minY, 0.8, accuracy: 0.000000000001)
    XCTAssertEqual(lower.width, 0.2, accuracy: 0.000000000001)
    XCTAssertEqual(lower.height, 0.2, accuracy: 0.000000000001)
  }

  func testReturnsUnknownForEmptyAndOutsideBounds() {
    for bounds in [CGRect.zero,
      CGRect(x: 1, y: 0, width: 0.2, height: 0.2),
      CGRect(x: 0, y: 1.1, width: 0.2, height: 0.2),
      CGRect(x: -0.5, y: 0, width: 0.2, height: 0.2),
      CGRect(x: 0, y: 0, width: -0.2, height: 0.2),
      CGRect(x: 0.5, y: 0.5, width: -0.2, height: 0.2),
      CGRect(x: 0.5, y: 0.5, width: 0.2, height: -0.2),
      CGRect(x: 0, y: 0, width: 0.2, height: 0)] {
      XCTAssertNil(DocumentOCR.normalizedBounds(bounds))
    }
  }

  func testReturnsUnknownForNullAndNonFiniteBounds() {
    let invalid: [CGRect] = [.null, .infinite,
      CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
      CGRect(x: 0, y: CGFloat.infinity, width: 1, height: 1),
      CGRect(x: 0, y: 0, width: CGFloat.nan, height: 1),
      CGRect(x: 0, y: 0, width: 1, height: CGFloat.infinity),
      CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
        width: CGFloat.greatestFiniteMagnitude, height: 1)]
    for (index, bounds) in invalid.enumerated() {
      XCTAssertNil(DocumentOCR.normalizedBounds(bounds), "무효 입력 \(index): \(bounds)")
    }
  }

  func testPreservesValidCoordinateConversionExactly() throws {
    for bounds in [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
      CGRect(x: 0, y: 0, width: 1, height: 1),
      CGRect(x: 0.125, y: 0.25, width: 0.5, height: 0.125)] {
      let expected = CGRect(x: bounds.minX, y: 1 - bounds.maxY,
        width: bounds.width, height: bounds.height)
      XCTAssertEqual(try XCTUnwrap(DocumentOCR.normalizedBounds(bounds)), expected)
    }
  }
}
