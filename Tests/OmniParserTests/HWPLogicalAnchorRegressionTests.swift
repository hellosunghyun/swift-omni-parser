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

  func testHWPXDescriptionsPreserveNamespacedDescriptionsAcrossEntries() throws {
    let first = descriptionXML(id: 42, text: "그림 설명")
    let second = descriptionXML(id: 43, text: "다른 그림").replacingOccurrences(
      of: "instid=", with: "id=")
    let ignored = descriptionXML(id: 42, text: "다른 설명", namespace: "urn:other")
    let atDepthLimit = nestedDescription(depth: 61)
    let archive = descriptionArchive(try [first, first, second, ignored, atDepthLimit].map {
      try encodedXML($0, encoding: .utf8)
    })
    let result = try DocumentHWPXDescriptions.read(archive, options: .init())
    let expected: [UInt32: String] = [42: "그림 설명", 43: "다른 그림", 44: "깊이 경계"]
    XCTAssertTrue(result == expected, "이름공간·설명 합치기·깊이 경계가 달라졌습니다.")
  }

  func testHWPXDescriptionsRejectDeclarationTokensAcrossEncodings() throws {
    let encodings: [String.Encoding] = [
      .utf8, .utf16LittleEndian, .utf16BigEndian, .utf32BigEndian
    ]
    let body = descriptionXML(id: 42, text: "그림 설명")
    for encoding in encodings {
      let clean = descriptionArchive([try encodedXML(body, encoding: encoding)])
      let result = try DocumentHWPXDescriptions.read(clean, options: .init())
      XCTAssertTrue(result == [42: "그림 설명"], "유효한 인코딩 대조군을 읽지 못했습니다.")
      // 유효한 XML 주석도 기존 바이트 차단 대상이다. XML 문법 오류로만 거부되지 않게 한다.
      for token in ["<!DOCTYPE", "<!ENTITY"] {
        let xml = "<!-- \(token) -->\n\(body)"
        assertMalformedDescriptions(descriptionArchive([try encodedXML(xml, encoding: encoding)]))
      }
    }
  }

  func testHWPXDescriptionsRejectUTF32LEDeclarationTokens() throws {
    let body = descriptionXML(id: 42, text: "그림 설명")
    // 정상 LE 지원 여부는 고정하지 않는다. LE preflight 경로도 이 회귀만으로 입증하지 못한다.
    for prefix in ["<!-- <!DOCTYPE -->\n", "<!-- <!ENTITY -->\n"] {
      let xml = try encodedXML(prefix + body, encoding: .utf32LittleEndian)
      assertMalformedDescriptions(descriptionArchive([xml]))
    }
  }

  func testHWPXDescriptionsRejectConflictsAndExcessiveDepth() throws {
    let first = descriptionXML(id: 42, text: "그림 설명")
    let conflict = descriptionXML(id: 42, text: "다른 설명")
    let repeatedComment = first.replacingOccurrences(
      of: "</hp:pic>", with: "<hp:shapeComment>다른 설명</hp:shapeComment></hp:pic>")
    for documents in [[first, conflict], [repeatedComment], [nestedDescription(depth: 62)]] {
      assertMalformedDescriptions(descriptionArchive(try documents.map {
        try encodedXML($0, encoding: .utf8)
      }))
    }
  }

  private func descriptionXML(
    id: UInt32, text: String,
    namespace: String = "http://www.hancom.co.kr/hwpml/2011/paragraph"
  ) -> String {
    """
    <hp:sec xmlns:hp="\(namespace)"><hp:pic instid="\(id)">\
    <hp:shapeComment>\(text)</hp:shapeComment></hp:pic></hp:sec>
    """
  }

  private func nestedDescription(depth: Int) -> String {
    String(repeating: "<n>", count: depth)
      + descriptionXML(id: 44, text: "깊이 경계") + String(repeating: "</n>", count: depth)
  }

  private func encodedXML(_ body: String, encoding: String.Encoding) throws -> Data {
    let name: String
    let prefix: [UInt8]
    switch encoding {
    case .utf16LittleEndian:
      name = "UTF-16"
      prefix = [0xFF, 0xFE]
    case .utf16BigEndian:
      name = "UTF-16"
      prefix = [0xFE, 0xFF]
    case .utf32LittleEndian:
      name = "UTF-32"
      prefix = [0xFF, 0xFE, 0, 0]
    case .utf32BigEndian:
      name = "UTF-32"
      // 기존 XMLParser가 읽는 BOM 없는 BE 시료를 사용한다.
      prefix = []
    default:
      name = "UTF-8"
      prefix = []
    }
    let xml = "<?xml version=\"1.0\" encoding=\"\(name)\"?>\n\(body)"
    let bytes = try XCTUnwrap(xml.data(using: encoding), "고정 XML을 인코딩하지 못했습니다.")
    return Data(prefix) + bytes
  }

  private func descriptionArchive(_ documents: [Data]) -> Data {
    HWPRepeatedAnchorFixtures.makeZIP(documents.enumerated().map { index, data in
      ("Contents/section\(index).xml", data)
    })
  }

  private func assertMalformedDescriptions(
    _ archive: Data, file: StaticString = #filePath, line: UInt = #line
  ) {
    do {
      _ = try DocumentHWPXDescriptions.read(archive, options: .init())
      XCTFail("거부해야 하는 HWPX 설명을 허용했습니다.", file: file, line: line)
    } catch {
      XCTAssertTrue(error as? DocumentParsingError == .malformedDocument,
                    "기존 HWPX 설명 오류 범주가 달라졌습니다.", file: file, line: line)
    }
  }
}
