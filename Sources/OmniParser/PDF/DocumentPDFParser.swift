import Foundation
import PDFKit

/// PDF 열기·페이지 파이프라인·최종 결과 조합을 담당한다.
/// 페이지 작업 완료 순서와 관계없이 페이지·좌표 순으로 블록을 정리한다.
nonisolated enum DocumentPDFParser {
  static func parse(
    _ data: Data,
    options: DocumentParserOptions,
    progress: DocumentParser.ProgressHandler?
  ) async throws -> DocumentParseResult {
    guard let document = PDFDocument(data: data) else {
      throw DocumentParsingError.malformedDocument
    }
    guard !document.isLocked else { throw DocumentParsingError.encryptedDocument }
    guard document.pageCount > 0 else { throw DocumentParsingError.malformedDocument }
    let count = min(document.pageCount, max(1, options.maximumDocumentPages))
    var pipeline = DocumentPDFPipeline(document: document, options: options)
    let pages = try await pipeline.run(count: count, progress: progress)
    try Task.checkCancellation()
    var blocks = pages.flatMap { $0.result.blocks }
    let images = pages.flatMap { $0.result.images }
    var warnings = pages.flatMap { $0.result.warnings }
    if count < document.pageCount {
      warnings.append(DocumentWarning(
        code: .resourceLimitReached, message: "Remaining PDF pages exceeded the configured limit.",
        location: DocumentLocation(page: count + 1)))
    }
    blocks.sortInGeometricReadingOrder()
    return DocumentParseResult(
      format: .pdf, blocks: blocks, warnings: warnings, images: images)
  }
}
