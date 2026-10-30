import Foundation
@testable import OmniParser
import XCTest

final class RTFScannerBoundaryTests: XCTestCase {
  func testExactObjectByteBudgetAllowsTrailingWhitespace() throws {
    for suffix in ["", " ", "\n\r\t "] {
      let result = try scan(hexBytes: String(repeating: "ab", count: 32) + suffix)
      let object = try XCTUnwrap(result.objects.first)
      XCTAssertEqual(object.data.count, 32)
      XCTAssertFalse(object.resourceLimited)
      XCTAssertFalse(object.malformed)
    }
  }

  func testExactObjectBudgetStillReportsIncompleteHexNibble() throws {
    let result = try scan(hexBytes: String(repeating: "ab", count: 32) + "a\n")
    let object = try XCTUnwrap(result.objects.first)
    XCTAssertEqual(object.data.count, 32)
    XCTAssertFalse(object.resourceLimited)
    XCTAssertTrue(object.malformed)
  }

  func testNextCompleteByteTriggersSharedLimitWithoutRetainingIt() throws {
    let result = try scan(hexBytes: String(repeating: "ab", count: 32) + "cd\n")
    let object = try XCTUnwrap(result.objects.first)
    XCTAssertEqual(object.data.count, 32)
    XCTAssertTrue(object.resourceLimited)
    XCTAssertFalse(object.malformed)
    let source = "{\\rtf1{\\object{\\*\\objdata \(String(repeating: "ab", count: 16))\n}}"
      + "{\\object{\\*\\objdata \(String(repeating: "cd", count: 16))\n}}}"
    let siblings = try DocumentRTFPictureReader.read(Data(source.utf8),
      options: .init(maximumExpandedBytes: 32))
    XCTAssertEqual(siblings.objects.reduce(0) { $0 + $1.data.count }, 32)
    XCTAssertTrue(siblings.objects.allSatisfy { !$0.resourceLimited && !$0.malformed })
  }

  private func scan(hexBytes: String) throws -> DocumentRTFPictureReader.Output {
    let source = "{\\rtf1{\\object{\\*\\objdata \(hexBytes)}}}"
    return try DocumentRTFPictureReader.read(Data(source.utf8),
      options: .init(maximumExpandedBytes: 32))
  }
}
