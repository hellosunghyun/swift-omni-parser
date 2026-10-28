import CoreHwp
import Foundation
@testable import OmniParser
import XCTest

/// 같은 BinData의 다른 앵커와 이미 읽은 앵커의 재방문을 구별한다.
/// 자체 생성 HWPX이며 한컴 앱의 문서 수용·페이지 조판 검증을 대신하지 않는다.
final class HWPRepeatedAnchorRegressionTests: XCTestCase {
  private let before = "Native before"
  private let between = "Native between"
  private let after = "Native after"
  private let anchors = [
    DocumentLocation(part: "section[0]/paragraph[2]/control[0]", paragraph: 2),
    DocumentLocation(part: "section[0]/paragraph[4]/control[0]", paragraph: 4)
  ]

  private var cellAnchors: [DocumentLocation] {
    [anchors[0]] + (1...2).map { (column: Int) -> DocumentLocation in
      let part = "section[0]/paragraph[4]/table[0]/cell[1,\(column)]"
        + "/paragraph[2]/control[0]"
      return DocumentLocation(part: part, row: 1, column: column, paragraph: 2,
        rowSpan: 1, columnSpan: 1)
    }
  }

  func testRepeatedHWPXBinaryPreservesNewAnchorsWithoutRevisitingOldAnchors() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let bytes = makeHWPX(png: png)
    guard let file = try paragraphFixture(bytes),
      let text = try await oracleText(png) else { return }
    try await assertExtraction(bytes, file: file, text: text, anchors: anchors)
  }

  func testRepeatedHWPXBinaryPreservesParagraphAndCellAnchors() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let bytes = makeHWPX(png: png, includeCells: true)
    guard let file = try cellFixture(bytes),
      let text = try await oracleText(png) else { return }
    try await assertExtraction(bytes, file: file, text: text, anchors: cellAnchors, cells: true)
  }

  private func baseFixture(_ bytes: Data) throws -> HwpFile? {
    let file = try HwpFile(fromData: bytes)
    // 구조 수용이 먼저다. 여기서 실패하면 OCR 누락 결함이 재현됐다고 판정하지 않는다.
    guard file.binaryDataArray.count == 1, file.displaySectionArray.count == 1,
      file.displaySectionArray[0].paragraph.count == 5
    else { XCTFail("자체 fixture의 기본 구조를 수용하지 못했습니다."); return nil }
    let hasLeadingSection = file.displaySectionArray[0].paragraph[0].ctrlHeaderArray?
      .contains { if case .section = $0 { return true }; return false } ?? false
    guard hasLeadingSection else {
      XCTFail("자체 fixture의 첫 문단에 section 컨트롤이 없습니다."); return nil
    }
    return file
  }

  private func paragraphFixture(_ bytes: Data) throws -> HwpFile? {
    guard let file = try baseFixture(bytes) else { return nil }
    let pictures = file.displaySectionArray[0].paragraph.flatMap {
      $0.ctrlHeaderArray ?? []
    }.compactMap { control -> HwpShapeControl? in
      if case .picture(let shape) = control { return shape }
      return nil
    }.flatMap(\.shapeComponentArray).flatMap(\.pictureArray)
    guard pictures.count == 2,
      pictures.allSatisfy({ $0.binaryDataId == file.binaryDataArray[0].streamId })
    else { XCTFail("자체 fixture가 하나의 BinData를 두 그림에서 참조하지 않습니다."); return nil }

    return file
  }

  private func oracleText(_ png: Data) async throws -> String? {
    let direct = try await DocumentParser.parse(.data(png, fileName: "probe.png"),
      options: .init(performOCR: true))
    let oracle = direct.blocks.filter { $0.kind == .imageOCR }
    let expectedText = oracle.map(\.text).joined(separator: "\n")
    guard !oracle.isEmpty, normalized(expectedText).contains("IMAGEOCRMARKER") else {
      XCTFail("직접 PNG OCR이 자체 마커를 읽지 못했습니다."); return nil
    }

    return expectedText
  }

  private func assertExtraction(
    _ bytes: Data, file: HwpFile, text: String, anchors: [DocumentLocation], cells: Bool = false
  ) async throws {
    for extractImages in [false, true] {
      let options = DocumentParserOptions(extractImages: extractImages, performOCR: true,
                                          maximumEmbeddedImages: 1)
      let result = try await DocumentParser.parse(
        .data(bytes, fileName: "repeated-paragraphs.hwpx"), options: options)
      assertPublicResult(result, file: file, expectedText: text, anchors: anchors,
                         extractImages: extractImages)
      if cells { assertCellOrder(result.blocks) }
      try await assertContext(file, options: options, expectedText: text, anchors: anchors)
    }
  }

  private func assertPublicResult(
    _ result: DocumentParseResult, file: HwpFile, expectedText: String,
    anchors: [DocumentLocation], extractImages: Bool
  ) {
    XCTAssertEqual(result.format, .hwpx)
    assertAnchors(result.blocks, expectedText: expectedText, expectedAnchors: anchors)
    XCTAssertEqual(result.images.count, extractImages ? 1 : 0)
    XCTAssertEqual(result.blocks.filter { $0.kind == .image }.count,
                   extractImages ? anchors.count : 0)
    XCTAssertEqual(result.warnings.count, anchors.count)
    XCTAssertTrue(result.warnings.allSatisfy {
      $0.code == .uncertainReadingOrder && anchors.contains($0.location ?? .init())
    })
    XCTAssertTrue(result.images.allSatisfy {
      $0.id == file.binaryDataArray[0].name && $0.location == anchors[0]
    })
    assertInlineOrder(result.blocks, expectedAnchors: anchors)
    TestFixtures.assertTextConsistency(result)

  }

  private func assertContext(
    _ file: HwpFile, options: DocumentParserOptions, expectedText: String,
    anchors: [DocumentLocation]
  ) async throws {
    let extractImages = options.extractImages
    var context = DocumentHWPParseContext(options: options)
    context.binaryItems = file.binaryDataArray
    try await context.appendSections(file.displaySectionArray)
    assertAnchors(context.blocks, expectedText: expectedText, expectedAnchors: anchors)
    XCTAssertEqual(context.imageAttempts, 1)
    let blocksBefore = context.blocks, imagesBefore = context.images
    let recognizedBefore = blocksBefore.filter { $0.kind == .imageOCR }
    let imageBlockCountBefore = blocksBefore.filter { $0.kind == .image }.count
    let textBefore = textContent(blocksBefore)
    let warningsBefore = context.warnings, retainedBytesBefore = context.imageBytes
    for (index, anchor) in anchors.enumerated() {
      try await context.appendImage(file.binaryDataArray[0], location: anchor, description: nil)
      // 같은 control part의 복수 그림 배치를 합치지 않는다. 기존 image 블록 정책을 유지한다.
      let addedPlacements = extractImages ? index + 1 : 0
      XCTAssertEqual(context.blocks.count, blocksBefore.count + addedPlacements)
      XCTAssertEqual(context.blocks.filter { $0.kind == .image }.count,
                     imageBlockCountBefore + addedPlacements)
      if extractImages {
        XCTAssertTrue(context.blocks.last?.kind == .image
          && context.blocks.last?.location == anchor && context.blocks.last?.text == "")
      }
      XCTAssertTrue(context.blocks.filter { $0.kind != .image }
        == blocksBefore.filter { $0.kind != .image })
      XCTAssertTrue(context.blocks.filter { $0.kind == .imageOCR } == recognizedBefore,
                    "같은 앵커를 재방문하면서 OCR 블록이나 메타데이터가 바뀌었습니다.")
      XCTAssertTrue(textContent(context.blocks) == textBefore)
      XCTAssertTrue(context.images == imagesBefore)
      XCTAssertTrue(context.warnings == warningsBefore)
      XCTAssertEqual(context.imageBytes, retainedBytesBefore)
      XCTAssertEqual(context.imageAttempts, 1)
    }
    // fallback의 비교 기준은 기존 정책의 image 배치 추가가 끝난 뒤의 전체 결과다.
    let blocksBeforeFallback = context.blocks
    try await context.appendEmbeddedImages(file.binaryDataArray)
    XCTAssertTrue(context.blocks == blocksBeforeFallback,
                  "fallback이 이미 읽은 바이너리의 블록을 다시 추가했습니다.")
    XCTAssertTrue(context.images == imagesBefore)
    XCTAssertTrue(context.warnings == warningsBefore)
    XCTAssertEqual(context.imageBytes, retainedBytesBefore)
    XCTAssertEqual(context.imageAttempts, 1)
  }

  private func assertAnchors(
    _ blocks: [DocumentBlock], expectedText: String, expectedAnchors: [DocumentLocation]? = nil,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let anchors = expectedAnchors ?? self.anchors
    let groups = anchors.map { anchor in
      blocks.filter { $0.kind == .imageOCR && sameAnchor($0.location, anchor) }
    }
    XCTAssertTrue(groups.allSatisfy { !$0.isEmpty },
                  "서로 다른 두 앵커에 OCR 블록이 있어야 합니다.", file: file, line: line)
    XCTAssertEqual(blocks.filter { $0.kind == .imageOCR }.count,
                   groups.reduce(0) { $0 + $1.count }, file: file, line: line)
    for group in groups {
      XCTAssertTrue(normalized(group.map(\.text).joined(separator: "\n"))
        == normalized(expectedText), "앵커의 OCR 문구가 직접 PNG와 다릅니다.", file: file, line: line)
      XCTAssertTrue(group.allSatisfy {
        $0.location.bounds != nil && $0.ocrConfidence?.isFinite == true
      }, file: file, line: line)
    }
    for group in groups.dropFirst() {
      XCTAssertEqual(groups[0].count, group.count, file: file, line: line)
      for (first, second) in zip(groups[0], group) {
        XCTAssertTrue(first.text == second.text && first.location.bounds == second.location.bounds
          && first.ocrConfidence == second.ocrConfidence
          && first.ocrOriginalText == second.ocrOriginalText,
          "새 앵커에서 같은 그림의 OCR 메타데이터가 바뀌었습니다.", file: file, line: line)
      }
    }
  }

  private func sameAnchor(_ actual: DocumentLocation, _ expected: DocumentLocation) -> Bool {
    var anchor = actual
    // 이 bounds는 그림 내부 OCR 위치다. 페이지 위치를 만들어 비교하지 않는다.
    anchor.bounds = nil
    return anchor == expected
  }

  private func assertInlineOrder(
    _ blocks: [DocumentBlock], expectedAnchors: [DocumentLocation]? = nil
  ) {
    let anchors = expectedAnchors ?? self.anchors
    guard let start = blocks.firstIndex(where: { $0.kind == .paragraph && $0.text == before }),
      let middle = blocks.firstIndex(where: { $0.kind == .paragraph && $0.text == between }),
      let end = blocks.firstIndex(where: { $0.kind == .paragraph && $0.text == after })
    else { return XCTFail("자체 본문 문단이 보존되지 않았습니다.") }
    XCTAssertTrue(start < middle && middle < end)
    for (index, anchor) in anchors.enumerated() {
      let positions = blocks.indices.filter {
        blocks[$0].kind == .imageOCR && sameAnchor(blocks[$0].location, anchor)
      }
      XCTAssertFalse(positions.isEmpty)
      XCTAssertTrue(positions.allSatisfy {
        index == 0 ? start < $0 && $0 < middle : middle < $0 && $0 < end
      })
    }
  }

  private func cellFixture(_ bytes: Data) throws -> HwpFile? {
    guard let file = try baseFixture(bytes) else { return nil }
    let paragraphs = file.displaySectionArray[0].paragraph
    let tables = (paragraphs[3].ctrlHeaderArray ?? []).compactMap { control -> HwpTable? in
      if case .table(let table) = control { return table }; return nil
    }
    guard tables.count == 1, tables[0].tableProperty.rowCount == 1,
      tables[0].tableProperty.columnCount == 2, tables[0].cellArray.count == 2
    else { XCTFail("자체 fixture의 1행 2열 표를 수용하지 못했습니다."); return nil }
    let cells = tables[0].cellArray
    guard cells.enumerated().allSatisfy({ index, cell in
      cell.paragraphArray.count == 2 && cell.header.cellProperty?.rowAddress == 0
        && cell.header.cellProperty?.columnAddress == UInt16(index)
        && cell.header.cellProperty?.rowSpan == 1 && cell.header.cellProperty?.columnSpan == 1
    }) else { XCTFail("셀 주소·병합 범위·두 내부 문단이 다릅니다."); return nil }
    let references = pictureReferences(in: paragraphs)
      + cells.flatMap { pictureReferences(in: $0.paragraphArray) }
    guard references.count == 3,
      references.allSatisfy({ $0.binaryDataId == file.binaryDataArray[0].streamId })
    else { XCTFail("문단·두 셀이 하나의 BinData를 참조하지 않습니다."); return nil }
    return file
  }

  private func pictureReferences(in paragraphs: [HwpParagraph]) -> [HwpShapeComponentPicture] {
    paragraphs.flatMap { $0.ctrlHeaderArray ?? [] }
      .compactMap { control -> HwpShapeControl? in
        if case .picture(let shape) = control { return shape }; return nil
      }.flatMap(\.shapeComponentArray).flatMap(\.pictureArray)
  }

  private func assertCellOrder(_ blocks: [DocumentBlock]) {
    let cells = blocks.filter { $0.kind == .tableCell }
    XCTAssertEqual(blocks.filter { $0.kind == .table }.count, 1)
    XCTAssertEqual(cells.count, 2)
    for column in 1...2 {
      XCTAssertTrue(cells.contains {
        $0.text == "Cell \(column)" && $0.location.row == 1 && $0.location.column == column
          && $0.location.rowSpan == 1 && $0.location.columnSpan == 1
          && $0.location.part == "section[0]/paragraph[4]/table[0]"
      })
      guard let cellIndex = blocks.firstIndex(where: {
        $0.kind == .tableCell && $0.location.row == 1 && $0.location.column == column
      }) else { XCTFail("예상 셀의 본문 블록이 없습니다."); continue }
      let positions = blocks.indices.filter {
        blocks[$0].kind == .imageOCR && sameAnchor(blocks[$0].location, cellAnchors[column])
      }
      XCTAssertFalse(positions.isEmpty)
      XCTAssertTrue(positions.allSatisfy { cellIndex < $0 })
      if column == 1, let next = blocks.firstIndex(where: {
        $0.kind == .tableCell && $0.location.row == 1 && $0.location.column == 2
      }) { XCTAssertTrue(positions.allSatisfy { $0 < next }) }
    }
  }

}

private extension HWPRepeatedAnchorRegressionTests {
  func textContent(_ blocks: [DocumentBlock]) -> String {
    blocks.filter { !$0.text.isEmpty && $0.kind != .image && $0.kind != .table }
      .map(\.text).joined(separator: "\n")
  }

  func normalized(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace }
  }

  func makeHWPX(png: Data, includeCells: Bool = false) -> Data {
    HWPRepeatedAnchorFixtures.make(png: png, before: before, between: between, after: after,
                                   includeCells: includeCells)
  }}
