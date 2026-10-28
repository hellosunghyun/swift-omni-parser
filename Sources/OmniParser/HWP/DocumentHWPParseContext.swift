import CoreHwp
import Foundation

/// HWP 섹션·문단·표·컨트롤을 원본 순서로 순회하는 문서별 상태다.
/// 문단·셀의 논리적 위치와 실제 페이지 조판 좌표는 구분해서 다룬다.
nonisolated struct DocumentHWPParseContext {
  let options: DocumentParserOptions
  var blocks: [DocumentBlock] = []
  var warnings: [DocumentWarning] = []
  var images: [DocumentEmbeddedImage] = []
  var imageBytes = 0
  var imageAttempts = 0
  var binaryItems: [HwpBinaryData] = []
  var descriptions: [UInt32: String] = [:]
  var visitedImages: Set<String> = []
  /// 성공한 첫 OCR의 블록 범위만 저장하며 픽셀·OCR 배열을 별도로 보관하지 않는다.
  var imageOCRRanges: [String: Range<Int>] = [:]
  /// 그림 내부 OCR bounds를 제외한 전체 논리 앵커를 보관한다.
  private var imageOCRAnchors: [String: Set<ImageOCRAnchor>] = [:]

  nonisolated private struct ImageOCRAnchor: Hashable {
    let part: String?
    let page: Int?
    let row: Int?
    let column: Int?
    let paragraph: Int?
    let rowSpan: Int?
    let columnSpan: Int?

    init(_ location: DocumentLocation) {
      part = location.part
      page = location.page
      row = location.row
      column = location.column
      paragraph = location.paragraph
      rowSpan = location.rowSpan
      columnSpan = location.columnSpan
    }
  }

  init(options: DocumentParserOptions) {
    self.options = options
  }

  /// 사전 저장소를 직접 갱신해 Set의 복사본을 붙잡지 않는다.
  mutating func insertImageOCRAnchor(_ name: String, location: DocumentLocation) -> Bool {
    imageOCRAnchors[name, default: []].insert(ImageOCRAnchor(location)).inserted
  }

  mutating func appendSections(_ sections: [HwpSection]) async throws {
    for (sectionIndex, section) in sections.enumerated() {
      for (paragraphIndex, paragraph) in section.paragraph.enumerated() {
        try Task.checkCancellation()
        try await append(
          paragraph,
          location: DocumentLocation(
            part: "section[\(sectionIndex)]",
            paragraph: paragraphIndex + 1
          )
        )
      }
    }
  }

  mutating func appendDiagnostics(_ diagnostics: [HwpParseDiagnostic]) {
    for diagnostic in diagnostics {
      let isRecovered =
        diagnostic.kind == .recoveredParagraph
        || diagnostic.kind == .recoveredSection
        || diagnostic.kind == .recoveredMemoParagraph
      warnings.append(
        DocumentWarning(
          code: isRecovered ? .extractionFailed : .unsupportedElement,
          message: "Some HWP/HWPX elements could not be represented in the extracted result.",
          location: DocumentLocation(part: diagnostic.path)
        ))
    }
  }

  mutating func append(_ paragraph: HwpParagraph, location: DocumentLocation) async throws {
    let text = paragraphText(paragraph)
    if !text.isEmpty {
      blocks.appendBlock(.paragraph, text: text, location: location)
    }
    try await appendControls(paragraph, location: location)
  }

  /// 셀 주소·병합 범위를 보존하고 셀 안의 그림 컨트롤에는 같은 논리적 앵커를 넘긴다.
  mutating func append(_ table: HwpTable, part: String?) async throws {
    blocks.appendBlock(.table, location: DocumentLocation(part: part))
    for (index, cell) in table.cellArray.enumerated() {
      let value = cell.paragraphArray.map(paragraphText)
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      let row = cell.header.cellProperty.map { Int($0.rowAddress) + 1 } ?? index + 1
      let column = Int(cell.header.cellProperty?.columnAddress ?? 0) + 1
      let location = DocumentLocation(
        part: part, row: row, column: column,
        rowSpan: cell.header.cellProperty.map { max(1, Int($0.rowSpan)) },
        columnSpan: cell.header.cellProperty.map { max(1, Int($0.columnSpan)) })
      if !value.isEmpty {
        blocks.appendBlock(.tableCell, text: value, location: location)
      }
      for (paragraphIndex, paragraph) in cell.paragraphArray.enumerated() {
        var source = location
        source.paragraph = paragraphIndex + 1
        try await appendControls(paragraph, location: source)
      }
    }
  }

  mutating func appendControls(
    _ paragraph: HwpParagraph, location: DocumentLocation
  ) async throws {
    for (index, control) in (paragraph.ctrlHeaderArray ?? []).enumerated() {
      try Task.checkCancellation()
      var parent = location.part ?? "section"
      if let row = location.row, let column = location.column {
        parent += "/cell[\(row),\(column)]"
      }
      var anchor = location
      anchor.part = "\(parent)/paragraph[\(location.paragraph ?? 0)]"
        + "/control[\(index)]"
      switch control {
      case .table(let table):
        let part = "\(parent)/paragraph[\(location.paragraph ?? 0)]"
          + "/table[\(index)]"
        try await append(table, part: part)
      case .picture(let shape), .shape(let shape), .container(let shape):
        try await appendPictures(shape.shapeComponentArray,
                           property: shape.commonCtrlProperty, location: anchor)
      case .genShapeObject(let shape):
        try await appendPictures(shape.shapeComponentArray,
                           property: shape.commonCtrlProperty, location: anchor)
      default: break
      }
    }
  }

  /// 탭과 공백 제어 문자를 본문에 반영하고 그림·표 같은 컨트롤 레코드는 텍스트에서 제외한다.
  func paragraphText(_ paragraph: HwpParagraph) -> String {
    let units = (paragraph.paraText?.charArray ?? []).compactMap { character -> UInt16? in
      if character.value == 9 { return 9 }
      if character.value == 30 || character.value == 31 { return 32 }
      guard character.type == .char, character.value != 0 else { return nil }
      return character.value
    }
    return String(decoding: units, as: UTF16.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
