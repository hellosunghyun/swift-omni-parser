import CoreGraphics
import CoreHwp
import Foundation
import ImageIO

/// 본문의 그림 참조를 BinData와 연결해 이미지·설명·OCR을 추가한다.
/// 앵커를 찾지 못한 바이너리는 마지막에 읽고 위치가 불확실하다는 경고를 남긴다.
extension DocumentHWPParseContext {
  nonisolated mutating func appendPictures(
    _ components: [HwpShapeComponent], property: HwpCommonCtrlProperty?,
    location: DocumentLocation
  ) async throws {
    guard options.extractImages || options.performOCR else { return }
    for component in components {
      for picture in component.pictureArray {
        guard let id = picture.binaryDataId,
          let item = binaryItems.first(where: { $0.streamId == id })
        else {
          warnings.append(DocumentWarning(
            code: .extractionFailed, message: "HWP picture reference has no matching binary.",
            location: location))
          continue
        }
        let description = property.flatMap { descriptions[$0.instanceId] }
          ?? property?.objectDescription
        try await appendImage(item, location: location, description: description)
        // 논리적 문단·셀 앵커는 알지만 부동 개체의 페이지 조판 순서를 확정하지 않는다.
        warnings.append(DocumentWarning(
          code: .uncertainReadingOrder,
          message: "HWP picture has a paragraph/cell anchor; page layout order is uncertain.",
          location: location))
      }
    }
  }

  /// 문단·셀 순회에서 참조되지 않은 BinData도 마지막에 처리해 읽을 수 있는 그림을 버리지 않는다.
  nonisolated mutating func appendEmbeddedImages(_ items: [HwpBinaryData]) async throws {
    guard options.extractImages || options.performOCR else { return }
    for item in items where !visitedImages.contains(item.name) {
      try Task.checkCancellation()
      let location = DocumentLocation(part: item.name)
      try await appendImage(item, location: location, description: nil)
      warnings.append(DocumentWarning(
        code: .uncertainReadingOrder, message: "HWP binary has no resolved picture anchor.",
        location: location))
    }
  }

  nonisolated mutating func appendImage(
    _ item: HwpBinaryData, location: DocumentLocation, description: String?
  ) async throws {
    try Task.checkCancellation()
    guard let suffix = item.extensionName?.lowercased(),
      ["jpg", "jpeg", "png", "gif", "bmp", "tif", "tiff"].contains(suffix)
    else { return }
    guard visitedImages.insert(item.name).inserted else {
      // 그림 배치는 기존대로 남기고 성공한 OCR만 새로운 논리 앵커로 옮긴다.
      if options.extractImages {
        blocks.appendBlock(.image, text: description ?? "", location: location)
      }
      appendCachedImageOCR(item.name, location: location)
      return
    }
    guard imageAttempts < options.maximumEmbeddedImages,
      item.data.count <= options.maximumInputBytes
    else {
      warnings.append(DocumentWarning(
        code: .resourceLimitReached, message: "HWP image exceeded the configured resource limit.",
        location: location))
      return
    }
    imageAttempts += 1
    do {
      let decoded = try DocumentImageDecoder.decode(
        item.data, maximumPixels: options.maximumImagePixels)
      if options.extractImages {
        retainImage(decoded.image, orientation: decoded.orientation,
                    item: item, location: location, description: description)
      }
      let recognized = try await options.performOCR ? DocumentOCR.recognize(
        image: decoded.image, orientation: decoded.orientation, location: location) : []
      let start = blocks.count
      blocks.appendInReadingOrder(recognized)
      if !recognized.isEmpty {
        imageOCRRanges[item.name] = start..<blocks.count
        _ = insertImageOCRAnchor(item.name, location: location)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      warnings.append(DocumentWarning(
        code: options.performOCR ? .imageOCRFailed : .extractionFailed,
        message: "HWP image could not be decoded or recognized.",
        location: location))
    }
  }

  nonisolated private mutating func appendCachedImageOCR(
    _ name: String, location: DocumentLocation
  ) {
    guard let range = imageOCRRanges[name],
      insertImageOCRAnchor(name, location: location)
    else { return }
    // 원본 배열의 slice를 보유하지 않고 첫 성공 범위에서 한 블록씩 복제한다.
    for index in range {
      var block = blocks[index]
      let bounds = block.location.bounds
      block.location = location
      block.location.bounds = bounds
      block.readingOrder = blocks.count
      blocks.append(block)
    }
  }

  /// PNG 보관 한도는 OCR 활성화 여부와 별개로 적용한다.
  nonisolated private mutating func retainImage(
    _ image: CGImage, orientation: CGImagePropertyOrientation, item: HwpBinaryData,
    location: DocumentLocation, description: String?
  ) {
    guard let png = DocumentImageEncoder.png(image, orientation: orientation),
      png.count <= options.maximumExpandedBytes - imageBytes
    else {
      warnings.append(DocumentWarning(
        code: .resourceLimitReached, message: "HWP image raster could not be retained.",
        location: location))
      return
    }
    images.append(DocumentEmbeddedImage(
      id: item.name, pngData: png, location: location, orientation: orientation,
      sourceDescription: description?.isEmpty == false ? description : nil))
    imageBytes += png.count
    blocks.appendBlock(.image, text: description ?? "", location: location)
  }
}
