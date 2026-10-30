import CoreGraphics
import Foundation
import ImageIO

/// 래스터·벡터 그림을 같은 위치에서 읽고, 원본 실패 때만 연결된 호환본을 사용한다.
nonisolated enum DocumentRTFImageDecoder {
  struct Decoded {
    var image: CGImage
    var orientation: CGImagePropertyOrientation
    var location: DocumentLocation
    var warnings: [DocumentWarning] = []
  }

  static func decode(
    _ picture: DocumentRTFPictureReader.Picture, location: DocumentLocation,
    fallbackPart: String, options: DocumentParserOptions
  ) async throws -> Decoded {
    do {
      guard !picture.malformed else { throw DocumentParsingError.malformedDocument }
      return try await decodeImage(picture.data, location: location, options: options)
    } catch {
      if error is CancellationError || Task.isCancelled { throw CancellationError() }
      guard let backup = picture.backup, !backup.malformed else { throw error }
      var recovered = location
      recovered.part = "\(fallbackPart)/byte[\(backup.offset)]"
      var result = try await decodeImage(backup.data, location: recovered, options: options)
      result.warnings.insert(DocumentWarning(
        code: .extractionFailed, message: "RTF preferred image failed; its fallback was retained.",
        location: location), at: 0)
      return result
    }
  }

  private static func decodeImage(
    _ data: Data, location: DocumentLocation, options: DocumentParserOptions
  ) async throws -> Decoded {
    try Task.checkCancellation()
    if let rendered = try await DocumentVectorRenderer.renderDetailed(
      data, maximumPixels: options.maximumImagePixels) {
      let warnings: [DocumentWarning] = rendered.hasUnsupportedElements ? [DocumentWarning(
        code: .unsupportedElement,
        message: "Some metafile drawing records were omitted; the partial image was retained.",
        location: location)] : []
      return Decoded(image: rendered.image, orientation: .up, location: location,
                     warnings: warnings)
    }
    let decoded = try DocumentImageDecoder.decode(data, maximumPixels: options.maximumImagePixels)
    return Decoded(image: decoded.image, orientation: decoded.orientation, location: location)
  }
}
