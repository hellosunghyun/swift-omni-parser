import CoreHwp
import Foundation
@testable import OmniParser
import XCTest

/// 키 구현 대신 실제 appendImage의 새 앵커 복제와 오래된 앵커 억제를 확인한다.
final class HWPLogicalAnchorRegressionTests: XCTestCase {
  // 각 필드의 nil과 빈 문자열·0·1을 서로 다른 논리 위치로 구별한다.
  private let newAnchors = [
    DocumentLocation(part: ""), DocumentLocation(part: "section[0]"),
    DocumentLocation(page: 0), DocumentLocation(page: 1),
    DocumentLocation(row: 0), DocumentLocation(row: 1),
    DocumentLocation(column: 0), DocumentLocation(column: 1),
    DocumentLocation(paragraph: 0), DocumentLocation(paragraph: 1),
    DocumentLocation(rowSpan: 0), DocumentLocation(rowSpan: 1),
    DocumentLocation(columnSpan: 0), DocumentLocation(columnSpan: 1)
  ]

  func testLogicalAnchorPreservesEveryFieldAndIgnoresOnlyBounds() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let bytes = HWPRepeatedAnchorFixtures.make(
      png: png, before: "Before", between: "Between", after: "After")
    let file = try HwpFile(fromData: bytes)
    let item = try XCTUnwrap(file.binaryDataArray.first)
    var context = DocumentHWPParseContext(
      options: .init(performOCR: true, maximumEmbeddedImages: 1))
    let firstAnchor = DocumentLocation()
    try await context.appendImage(item, location: firstAnchor, description: nil)
    let firstBlocks = context.blocks
    guard !firstBlocks.isEmpty else {
      XCTFail("최초 그림에서 실제 OCR 블록을 얻지 못했습니다.")
      return
    }
    XCTAssertTrue(firstBlocks.allSatisfy { $0.kind == .imageOCR })

    var boundsOnly = firstAnchor
    boundsOnly.bounds = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1)
    try await context.appendImage(item, location: boundsOnly, description: nil)
    XCTAssertTrue(context.blocks == firstBlocks, "bounds만 바뀐 같은 앵커를 복제했습니다.")

    for anchor in newAnchors {
      let start = context.blocks.count
      try await context.appendImage(item, location: anchor, description: nil)
      guard context.blocks.count == start + firstBlocks.count else {
        XCTFail("논리 위치 필드가 다른 새 앵커의 OCR 블록이 누락됐습니다.")
        return
      }
      for (offset, source) in firstBlocks.enumerated() {
        var expected = source
        expected.location = anchor
        expected.location.bounds = source.location.bounds
        expected.readingOrder = start + offset
        XCTAssertTrue(context.blocks[start + offset] == expected,
                      "새 앵커에서 텍스트·좌표·신뢰도·순서가 달라졌습니다.")
      }
    }

    let beforeRevisits = context.blocks
    let revisits = [firstAnchor] + Array(newAnchors.reversed()) + [newAnchors[0], firstAnchor]
    for var anchor in revisits {
      anchor.bounds = CGRect(x: 0.7, y: 0.1, width: 0.2, height: 0.2)
      try await context.appendImage(item, location: anchor, description: nil)
      XCTAssertTrue(context.blocks == beforeRevisits,
                    "다른 앵커를 거친 뒤 오래된 앵커의 OCR을 다시 복제했습니다.")
    }
    XCTAssertEqual(context.imageAttempts, 1)
    XCTAssertTrue(context.images.isEmpty)
    XCTAssertEqual(context.imageBytes, 0)
    XCTAssertTrue(context.warnings.isEmpty)
  }
}
