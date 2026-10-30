import Foundation
import ImageIO
import UIKit

/// 표·문단은 시스템 RTF importer의 속성을 읽고, 그림·OLE·머리말 범위를 별도로 보존한다.
/// 그림의 임시 마커를 원래 문단·셀 위치에서 소비해 OCR이 본문 뒤로 밀리지 않게 한다.
nonisolated enum DocumentRTFParser {
  static func parse(
    _ data: Data, options: DocumentParserOptions
  ) async throws -> DocumentParseResult {
    try Task.checkCancellation()
    let prepared = try DocumentRTFPictureReader.read(data, options: options)
    let attributed: NSAttributedString
    do {
      attributed = try NSAttributedString(
        data: prepared.data, options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil)
    } catch {
      return DocumentParseResult(
        format: .rtf,
        blocks: DocumentStructuredTextParser.parsePlainText(
          DocumentFormatDetector.decodeText(data) ?? ""),
        warnings: prepared.warnings + [DocumentWarning(
          code: .malformedContent, message: "RTF structure failed; original text was retained.",
          location: DocumentLocation(part: "rtf"))])
    }
    var context = Context(options: options, warnings: prepared.warnings)
    let text = attributed.string as NSString
    let pattern = try NSRegularExpression(
      pattern: prepared.marker + "(?:N([0-9]+)END|S([0-9]+)(BEGIN|END)|O([0-9]+)END)")
    var offset = 0
    var paragraph = 0
    while offset < text.length {
      try Task.checkCancellation()
      let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
      paragraph += 1
      try await context.appendParagraph(attributed, range: range, number: paragraph,
                                  prepared: prepared, pattern: pattern)
      offset = NSMaxRange(range)
    }
    for (index, picture) in prepared.pictures.enumerated()
    where !context.visitedPictures.contains(index) {
      context.warnings.append(DocumentWarning(
        code: .unsupportedElement, message: "RTF picture has no readable inline placement.",
        location: DocumentLocation(part: "rtf/byte[\(picture.range.lowerBound)]")))
    }
    return DocumentParseResult(format: .rtf, blocks: context.blocks,
                               warnings: context.warnings, images: context.images)
  }

  private struct Context {
    let options: DocumentParserOptions
    var warnings: [DocumentWarning]
    var blocks: [DocumentBlock] = []
    var images: [DocumentEmbeddedImage] = []
    var visitedPictures: Set<Int> = []
    private var tables: [ObjectIdentifier: String] = [:]
    private var partStack: [String] = []
    private var part: String { partStack.last ?? "rtf" }
    private var cells: [String: Int] = [:]
    private var warnedNestedTables: Set<ObjectIdentifier> = []
    private var imageBytes = 0
    private var objectBytes = 0
    private var imageAttempts = 0

    init(options: DocumentParserOptions, warnings: [DocumentWarning]) {
      self.options = options
      self.warnings = warnings
    }

    mutating func appendParagraph(
      _ attributed: NSAttributedString, range: NSRange, number: Int,
      prepared: DocumentRTFPictureReader.Output, pattern: NSRegularExpression
    ) async throws {
      let style = attributed.attribute(.paragraphStyle, at: range.location,
                                       effectiveRange: nil) as? NSParagraphStyle
      let (location, cellIndex) = tableLocation(style, paragraph: number)
      let text = attributed.string as NSString
      let matches = pattern.matches(in: attributed.string, range: range)
      if cellIndex != nil, !matches.isEmpty {
        warnings.append(DocumentWarning(
          code: .uncertainReadingOrder,
          message: "RTF cell text is grouped; image OCR retains the cell location.",
          location: location))
      }
      var cursor = range.location
      for match in matches {
        appendText(text.substring(with: NSRange(location: cursor,
          length: match.range.location - cursor)), location: location, cellIndex: cellIndex)
        if match.range(at: 1).location != NSNotFound,
          let index = Int(text.substring(with: match.range(at: 1))),
          prepared.pictures.indices.contains(index) {
          visitedPictures.insert(index)
          try await appendImage(prepared.pictures[index], index: index, location: location)
        } else if match.range(at: 2).location != NSNotFound,
          let index = Int(text.substring(with: match.range(at: 2))),
          prepared.sections.indices.contains(index) {
          switchSection(prepared.sections[index],
                        beginning: text.substring(with: match.range(at: 3)) == "BEGIN")
        } else if match.range(at: 4).location != NSNotFound,
          let index = Int(text.substring(with: match.range(at: 4))),
          prepared.objects.indices.contains(index) {
          try await appendObject(prepared.objects[index], index: index, location: location)
        }
        cursor = NSMaxRange(match.range)
      }
      appendText(text.substring(with: NSRange(location: cursor,
        length: NSMaxRange(range) - cursor)), location: location, cellIndex: cellIndex)
    }

    /// 바깥 셀부터 경로를 만들어 중첩 표가 같은 행·열의 별도 표와 섞이지 않게 한다.
    private mutating func tableLocation(
      _ style: NSParagraphStyle?, paragraph: Int
    ) -> (DocumentLocation, Int?) {
      var location = DocumentLocation(part: part, paragraph: paragraph)
      var parent = part
      var cellIndex: Int?
      for cell in style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }) ?? [] {
        let tableID = ObjectIdentifier(cell.table)
        if tables[tableID] == nil {
          let tablePart = "\(parent)/table[\(tables.count + 1)]"
          tables[tableID] = tablePart
          blocks.appendBlock(.table, location: DocumentLocation(part: tablePart))
        }
        location.part = tables[tableID]
        location.row = cell.startingRow + 1
        location.column = cell.startingColumn + 1
        location.rowSpan = cell.rowSpan > 1 ? cell.rowSpan : nil
        location.columnSpan = cell.columnSpan > 1 ? cell.columnSpan : nil
        let cellAddress = "\(cell.startingRow + 1),\(cell.startingColumn + 1)"
        let key = "\(location.part ?? parent)/cell[\(cellAddress)]"
        if cells[key] == nil {
          cells[key] = blocks.count
          blocks.appendBlock(.tableCell, location: location)
        }
        cellIndex = cells[key]
        parent = key
      }
      if (style?.textBlocks.count ?? 0) > 1,
        let inner = style?.textBlocks.last as? NSTextTableBlock,
        warnedNestedTables.insert(ObjectIdentifier(inner.table)).inserted {
        warnings.append(DocumentWarning(
          code: .uncertainReadingOrder,
          message: "Nested RTF cells retain their hierarchy; grouped cell text may differ inline.",
          location: location))
      }
      return (location, cellIndex)
    }

    private mutating func switchSection(
      _ section: DocumentRTFPictureReader.Section, beginning: Bool
    ) {
      if beginning {
        partStack.append(section.part)
        warnings.append(DocumentWarning(
          code: .uncertainReadingOrder,
          message: "RTF header/footer uses source order; repeated page placement is unavailable.",
          location: DocumentLocation(part: section.part)))
      } else if partStack.last == section.part { partStack.removeLast() }
    }

    private mutating func appendText(_ text: String, location: DocumentLocation, cellIndex: Int?) {
      let value = text.replacingOccurrences(of: "\u{FFFC}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return }
      if let index = cellIndex {
        if !blocks[index].text.isEmpty { blocks[index].text += "\n" }
        blocks[index].text += value
      } else { blocks.appendBlock(.paragraph, text: value, location: location) }
    }

    /// 정상 원본을 우선 사용하고, 디코딩 실패일 때만 연결된 호환본을 시도한다.
    private mutating func decode(
      _ picture: DocumentRTFPictureReader.Picture, location: inout DocumentLocation
    ) throws -> (image: CGImage, orientation: CGImagePropertyOrientation) {
      do {
        guard !picture.malformed else { throw DocumentParsingError.malformedDocument }
        return try DocumentImageDecoder.decode(
          picture.data, maximumPixels: options.maximumImagePixels)
      } catch {
        guard let backup = picture.backup, !backup.malformed else { throw error }
        let decoded = try DocumentImageDecoder.decode(
          backup.data, maximumPixels: options.maximumImagePixels)
        warnings.append(DocumentWarning(
          code: .extractionFailed,
          message: "RTF preferred image failed; its fallback was retained.",
          location: location))
        location.part = "\(part)/byte[\(backup.offset)]"
        return decoded
      }
    }

    /// native 데이터 추출이 성공하면 result 미리보기는 생략해 본문·OCR 중복을 막는다.
    private mutating func appendObject(
      _ object: DocumentRTFPictureReader.Object, index: Int, location: DocumentLocation
    ) async throws {
      var located = location
      let bytePart = "byte[\(object.range.lowerBound)]/object[\(index + 1)]"
      located.part = "\(location.part ?? part)/\(bytePart)"
      do {
        guard !object.linked else { throw DocumentParsingError.unsupportedFormat }
        guard !object.resourceLimited else { throw DocumentParsingError.inputTooLarge }
        guard !object.malformed else { throw DocumentParsingError.malformedDocument }
        var child = options
        let remaining = options.maximumExpandedBytes - imageBytes - objectBytes
        child.maximumExpandedBytes = max(0, remaining)
        child.maximumEmbeddedImages = max(0, options.maximumEmbeddedImages - imageAttempts)
        let result = try await DocumentRTFObjectReader.parse(object.data, options: child)
        objectBytes += object.data.count
        imageAttempts += DocumentRTFObjectReader.imageCount(result)
        let scoped = DocumentRTFObjectReader.scoped(result, parent: located.part ?? part)
        blocks.appendInReadingOrder(scoped.blocks)
        images.append(contentsOf: scoped.images)
        imageBytes += scoped.images.reduce(0) { $0 + $1.pngData.count }
        warnings.append(contentsOf: scoped.warnings)
      } catch {
        if error is CancellationError || Task.isCancelled
          || (error as? DocumentParsingError) == .cancelled { throw CancellationError() }
        warnings.append(DocumentWarning(
          code: (error as? DocumentParsingError) == .inputTooLarge
            ? .resourceLimitReached : .unsupportedElement,
          message: object.linked ? "RTF linked OLE object was not opened."
            : "RTF OLE native content failed; available preview and other content were retained.",
          location: located))
        if let preview = object.preview, options.extractImages || options.performOCR {
          try await appendImage(preview, index: index, location: location,
                                sourcePart: located.part.map { $0 + "/preview" })
        }
      }
    }

    private mutating func appendImage(
      _ picture: DocumentRTFPictureReader.Picture, index: Int, location: DocumentLocation,
      sourcePart: String? = nil
    ) async throws {
      var located = location
      located.part = sourcePart
        ?? "\(part)/byte[\(picture.range.lowerBound)]/image[\(index + 1)]"
      do {
        guard imageAttempts < options.maximumEmbeddedImages else {
          throw DocumentParsingError.inputTooLarge
        }
        imageAttempts += 1
        let decoded = try decode(picture, location: &located)
        let result = try await DocumentRasterParser.parseImage(
          decoded.image, orientation: decoded.orientation, format: .rtf, location: located,
          options: options,
          remainingBytes: max(0, options.maximumExpandedBytes - imageBytes - objectBytes))
        imageBytes += result.images.reduce(0) { $0 + $1.pngData.count }
        images.append(contentsOf: result.images)
        blocks.appendInReadingOrder(result.blocks)
        warnings.append(contentsOf: result.warnings)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        warnings.append(DocumentWarning(
          code: (error as? DocumentParsingError) == .inputTooLarge
            ? .resourceLimitReached : .extractionFailed,
          message: "RTF embedded image could not be decoded; other content was retained.",
          location: located))
      }
    }
  }
}
