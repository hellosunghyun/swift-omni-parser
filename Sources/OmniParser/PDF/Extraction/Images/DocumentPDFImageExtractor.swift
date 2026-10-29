import CoreGraphics
import Foundation
import ImageIO

/// PDF에 실제 표시된 그림 영역을 페이지 래스터에서 잘라 PNG와 OCR 작업으로 만든다.
/// 원본 JPEG·필터 스트림의 직접 추출이 아니라 표시 영역의 래스터화 결과를 반환한다.
nonisolated enum DocumentPDFImageExtractor {
  struct Result: Sendable {
    var blocks: [DocumentBlock] = []
    var images: [DocumentEmbeddedImage] = []
    var warnings: [DocumentWarning] = []
    var inspectedImages = 0
  }

  static func prepare(
    scanner: DocumentPDFScanner, raster: CGImage,
    space: DocumentPDFPageSpace, pageIndex: Int, limits: (images: Int, bytes: Int)
  ) throws -> (result: Result, jobs: [DocumentPDFImageJob]) {
    let options = scanner.options
    var result = Result()
    var jobs: [DocumentPDFImageJob] = []
    var bytes = 0
    for placement in scanner.images {
      try Task.checkCancellation()
      let bounds = space.normalized(placement.bounds)
      guard !bounds.isNull, !bounds.isEmpty else { continue }
      let location = DocumentLocation(part: placement.name, page: pageIndex + 1, bounds: bounds)
      guard result.inspectedImages < limits.images else {
        result.warnings.append(
          DocumentWarning(
            code: .resourceLimitReached, message: "PDF image count exceeded the configured limit.",
            location: location))
        break
      }
      result.inspectedImages += 1
      guard let crop = DocumentPDFPageSpace.crop(bounds, from: raster)
      else {
        result.warnings.append(
          DocumentWarning(
            code: .extractionFailed, message: "PDF image region could not be rasterized.",
            location: location))
        continue
      }
      if options.extractImages {
        guard let png = DocumentPDFPNGEncoder.png(crop), png.count <= limits.bytes - bytes else {
          result.warnings.append(DocumentWarning(
            code: .resourceLimitReached, message: "PDF image bytes exceeded the configured limit.",
            location: location))
          continue
        }
        bytes += png.count
        let id = "page[\(pageIndex + 1)]/\(placement.name)"
        result.images.append(DocumentEmbeddedImage(id: id, pngData: png, location: location))
        result.blocks.append(
          DocumentBlock(kind: .image, text: "", readingOrder: 0, location: location))
      }
      if options.performOCR {
        jobs.append(DocumentPDFImageJob(
          raster: DocumentPDFRaster(image: crop), location: location))
      }
    }
    return (result, jobs)
  }

  /// 잘라낸 그림 안의 OCR 좌표를 그림의 페이지 위치·크기에 맞춰 다시 변환한다.
  static func recognize(
    _ crop: CGImage, location: DocumentLocation, bounds: CGRect, maximumPixels: Int = 0
  ) async throws -> [DocumentBlock] {
    let pool = DocumentOCR.sessions ?? DocumentOCRSessionPool()
    let recognized = try await DocumentOCR.$sessions.withValue(pool) {
      let primary = try await DocumentOCR.recognize(
        image: crop, orientation: .up, location: location)
      try Task.checkCancellation()
      guard primary.isEmpty else { return primary }
      let size = paddingSize(
        width: crop.width, height: crop.height, maximumPixels: maximumPixels)
      try Task.checkCancellation()
      guard let size else { return primary }
      let padded = padded(crop, size: size)
      try Task.checkCancellation()
      guard let padded else { return primary }
      let blocks = try await DocumentOCR.recognize(
        image: padded, orientation: .up, location: location)
      try Task.checkCancellation()
      return blocks.compactMap { block in
        guard let local = unpaddedBounds(
          block.location.bounds, cropWidth: crop.width, cropHeight: crop.height)
        else { return nil }
        var located = block
        located.location.bounds = local
        return located
      }
    }
    return recognized.map { block in
      var located = block
      if let local = block.location.bounds {
        located.location.bounds = CGRect(
          x: bounds.minX + local.minX * bounds.width,
          y: bounds.minY + local.minY * bounds.height,
          width: local.width * bounds.width, height: local.height * bounds.height)
      }
      return located
    }
  }

  /// 페이지의 실제 래스터 면적 안에서만 고정 테두리를 추가한다. 0은 보완 비활성이다.
  static func paddingSize(width: Int, height: Int, maximumPixels: Int) -> CGSize? {
    let limit = min(maximumPixels, 1_000_000)
    guard limit > 0, width > 0, height > 0,
      width <= Int.max - 32, height <= Int.max - 32
    else { return nil }
    let paddedWidth = width + 32, paddedHeight = height + 32
    guard paddedWidth <= limit / paddedHeight else { return nil }
    return CGSize(width: paddedWidth, height: paddedHeight)
  }

  /// OCR의 좌상단 좌표에서 테두리를 빼고 원래 그림 안의 교차 영역만 남긴다.
  static func unpaddedBounds(
    _ bounds: CGRect?, cropWidth: Int, cropHeight: Int
  ) -> CGRect? {
    guard let bounds, cropWidth > 0, cropHeight > 0,
      bounds.origin.x.isFinite, bounds.origin.y.isFinite,
      bounds.size.width.isFinite, bounds.size.height.isFinite,
      bounds.size.width > 0, bounds.size.height > 0
    else { return nil }
    let width = CGFloat(cropWidth), height = CGFloat(cropHeight)
    let local = CGRect(
      x: (bounds.minX * (width + 32) - 16) / width,
      y: (bounds.minY * (height + 32) - 16) / height,
      width: bounds.width * (width + 32) / width,
      height: bounds.height * (height + 32) / height)
    guard local.origin.x.isFinite, local.origin.y.isFinite,
      local.size.width.isFinite, local.size.height.isFinite
    else { return nil }
    let clipped = local.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !clipped.isNull, !clipped.isEmpty,
      clipped.origin.x.isFinite, clipped.origin.y.isFinite,
      clipped.size.width.isFinite, clipped.size.height.isFinite
    else { return nil }
    return clipped
  }

  private static func padded(_ image: CGImage, size: CGSize) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 16, y: 16, width: image.width, height: image.height))
    return context.makeImage()
  }

}
