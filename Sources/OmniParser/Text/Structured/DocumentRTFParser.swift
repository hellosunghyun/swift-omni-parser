import Foundation
import ImageIO
import UIKit

/// 표·문단은 시스템 RTF importer의 속성을 읽고, pict만 별도로 추출한다.
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
    let pattern = try NSRegularExpression(pattern: prepared.marker + "N([0-9]+)END")
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
    private var tables: [ObjectIdentifier: Int] = [:]
    private var cells: [String: Int] = [:]
    private var imageBytes = 0

    init(options: DocumentParserOptions, warnings: [DocumentWarning]) {
      self.options = options
      self.warnings = warnings
    }

    mutating func appendParagraph(
      _ attributed: NSAttributedString, range: NSRange, number: Int,
      prepared: DocumentRTFPictureReader.Output, pattern: NSRegularExpression
    ) async throws {
      var location = DocumentLocation(part: "rtf", paragraph: number)
      var cellIndex: Int?
      if let style = attributed.attribute(.paragraphStyle, at: range.location,
                                          effectiveRange: nil) as? NSParagraphStyle,
        let cell = style.textBlocks.last as? NSTextTableBlock {
        let tableID = ObjectIdentifier(cell.table)
        if tables[tableID] == nil {
          tables[tableID] = tables.count + 1
          blocks.appendBlock(.table,
            location: DocumentLocation(part: "rtf/table[\(tables.count)]"))
        }
        location.part = "rtf/table[\(tables[tableID] ?? 1)]"
        location.row = cell.startingRow + 1
        location.column = cell.startingColumn + 1
        location.rowSpan = cell.rowSpan > 1 ? cell.rowSpan : nil
        location.columnSpan = cell.columnSpan > 1 ? cell.columnSpan : nil
        let key = "\(location.part ?? "")/\(cell.startingRow)/\(cell.startingColumn)"
        if cells[key] == nil {
          cells[key] = blocks.count
          blocks.appendBlock(.tableCell, location: location)
        }
        cellIndex = cells[key]
      }
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
        if let index = Int(text.substring(with: match.range(at: 1))),
          prepared.pictures.indices.contains(index) {
          visitedPictures.insert(index)
          try await appendImage(prepared.pictures[index], index: index, location: location)
        }
        cursor = NSMaxRange(match.range)
      }
      appendText(text.substring(with: NSRange(location: cursor,
        length: NSMaxRange(range) - cursor)), location: location, cellIndex: cellIndex)
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
        location.part = "rtf/byte[\(backup.offset)]"
        return decoded
      }
    }

    private mutating func appendImage(
      _ picture: DocumentRTFPictureReader.Picture, index: Int, location: DocumentLocation
    ) async throws {
      var located = location
      located.part = "rtf/byte[\(picture.range.lowerBound)]/image[\(index + 1)]"
      do {
        let decoded = try decode(picture, location: &located)
        let result = try await DocumentRasterParser.parseImage(
          decoded.image, orientation: decoded.orientation, format: .rtf, location: located,
          options: options, remainingBytes: max(0, options.maximumExpandedBytes - imageBytes))
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
