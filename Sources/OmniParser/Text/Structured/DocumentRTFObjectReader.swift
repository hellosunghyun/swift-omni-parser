import Foundation

/// OLE를 실행하거나 링크를 열지 않고, 메모리에 들어 있는 native 문서만 다시 파싱한다.
/// RTF object → RTF object 중첩은 TaskLocal 깊이와 호출별 축소 예산으로 제한한다.
nonisolated enum DocumentRTFObjectReader {
  @TaskLocal private static var depth = 0

  static func parse(
    _ data: Data, options: DocumentParserOptions
  ) async throws -> DocumentParseResult {
    try Task.checkCancellation()
    guard depth < 8, data.count <= options.maximumExpandedBytes else {
      throw DocumentParsingError.inputTooLarge
    }
    let payload = try payload(data, options: options)
    let vector = DocumentVectorRenderer.matches(payload.data)
    if DocumentDIBDecoder.hasHeader(payload.data) || vector {
      guard data.count < options.maximumExpandedBytes,
        payload.data.count <= options.maximumInputBytes else {
        throw DocumentParsingError.inputTooLarge
      }
      guard options.extractImages || options.performOCR else {
        return DocumentParseResult(format: .rtf, blocks: [], warnings: [])
      }
      guard options.maximumEmbeddedImages > 0 else { throw DocumentParsingError.inputTooLarge }
      let rendered = vector ? try await DocumentVectorRenderer.renderDetailed(
        payload.data, maximumPixels: options.maximumImagePixels) : nil
      let decoded = vector ? rendered?.image
        : try DocumentDIBDecoder.decode(payload.data, maximumPixels: options.maximumImagePixels)
      guard let image = decoded else {
        throw DocumentParsingError.unsupportedFormat
      }
      let location = DocumentLocation(part: vector ? "metafile" : "dib")
      var result = try await DocumentRasterParser.parseImage(
        image, orientation: .up, format: .rtf, location: location,
        options: options, remainingBytes: options.maximumExpandedBytes - data.count)
      if rendered?.hasUnsupportedElements == true {
        result.warnings.append(DocumentWarning(
          code: .unsupportedElement,
          message: "Some metafile drawing records were omitted; the partial image was retained.",
          location: location))
      }
      return result
    }
    let format = try DocumentFormatDetector.detect(
      data: payload.data, fileName: payload.name, options: options)
    if [.jpeg, .png, .heic, .tiff].contains(format),
      options.extractImages || options.performOCR, options.maximumEmbeddedImages <= 0 {
      throw DocumentParsingError.inputTooLarge
    }
    var child = options
    child.maximumInputBytes = min(options.maximumInputBytes, payload.data.count)
    child.maximumExpandedBytes = max(0, options.maximumExpandedBytes - data.count)
    guard child.maximumExpandedBytes > 0 else { throw DocumentParsingError.inputTooLarge }
    if [.jpeg, .png, .heic, .tiff].contains(format) {
      child.maximumDocumentPages = min(child.maximumDocumentPages, options.maximumEmbeddedImages)
    }
    return try await $depth.withValue(depth + 1) {
      try await DocumentParser.parse(.data(payload.data, fileName: payload.name), options: child)
    }
  }

  static func imageCount(_ result: DocumentParseResult) -> Int {
    let locations = result.blocks.filter { $0.kind == .image || $0.kind == .imageOCR }.map {
      "\($0.location.part ?? "")/page[\($0.location.page ?? 1)]"
    }
    return Set(locations).count
  }

  /// 포함 문서의 셀·페이지 위치를 유지하면서 호스트 object 경로를 앞에 붙인다.
  static func scoped(_ result: DocumentParseResult, parent: String) -> DocumentParseResult {
    func scope(_ original: DocumentLocation) -> DocumentLocation {
      var value = original
      value.part = parent + "/" + (original.part ?? result.format.rawValue)
      return value
    }
    return DocumentParseResult(format: result.format, blocks: result.blocks.map { block in
      var value = block
      value.location = scope(block.location)
      return value
    }, warnings: result.warnings.map { warning in
      var value = warning
      value.location = scope(warning.location ?? DocumentLocation())
      return value
    }, images: result.images.map { image in
      var value = image
      value.id = parent + "/" + image.id
      value.location = scope(image.location)
      return value
    })
  }

  private static func payload(
    _ data: Data, options: DocumentParserOptions
  ) throws -> (data: Data, name: String?) {
    var native = data
    var className: String?
    if !isCompound(native) {
      var reader = Reader(data: data)
      guard try reader.word() == 0x501, try reader.word() == 2 else {
        // OLE1 FormatID=1은 외부 linked object이므로 절대로 따라가지 않는다.
        throw DocumentParsingError.unsupportedFormat
      }
      className = try reader.sizedString()
      _ = try reader.sizedString() // topic과 item은 경로로 사용하지 않는다.
      _ = try reader.sizedString()
      let count = try reader.word()
      native = try reader.bytes(count)
    }
    if isCompound(native) {
      if (try? DocumentCompoundFile.identify(native)) != nil { return (native, nil) }
      let streams = try DocumentCompoundFile.streams(native, options: options)
      if let package = streams["\u{1}Ole10Native"] {
        var reader = Reader(data: package)
        let count = try reader.word()
        let native = try reader.bytes(count)
        if DocumentBinaryReader(data: native).uint16(0) == 2 {
          return try packagePayload(native)
        }
        return (native, nil)
      }
      if let contents = streams["CONTENTS"] { return (contents, nil) }
      throw DocumentParsingError.unsupportedFormat
    }
    if className?.lowercased() == "package" { return try packagePayload(native) }
    return (native, nil)
  }

  /// Ole10Native의 파일명은 판별 힌트로만 사용하고 원래 경로·임시 경로는 읽지 않는다.
  private static func packagePayload(_ data: Data) throws -> (data: Data, name: String?) {
    var reader = Reader(data: data)
    // OLE1 Package는 native 길이가 바깥 헤더에 있고 이 본문에는 2-byte flags부터 온다.
    guard try reader.short() == 2 else { throw DocumentParsingError.malformedDocument }
    let name = try reader.string().split { $0 == "/" || $0 == "\\" }.last
    _ = try reader.string()
    _ = try reader.word()
    _ = try reader.word()
    _ = try reader.string()
    let count = try reader.word()
    let payload = try reader.bytes(count)
    return (payload, name.map(String.init))
  }

  private static func isCompound(_ data: Data) -> Bool {
    data.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
  }

  private struct Reader {
    let data: Data
    var offset = 0

    mutating func word() throws -> Int {
      guard let value = DocumentBinaryReader(data: data).uint32(offset) else {
        throw DocumentParsingError.malformedDocument
      }
      offset += 4
      return value
    }

    mutating func short() throws -> Int {
      guard let value = DocumentBinaryReader(data: data).uint16(offset) else {
        throw DocumentParsingError.malformedDocument
      }
      offset += 2
      return value
    }

    mutating func bytes(_ count: Int) throws -> Data {
      guard let value = DocumentBinaryReader(data: data).slice(offset, count: count) else {
        throw DocumentParsingError.malformedDocument
      }
      offset += count
      return value
    }

    mutating func sizedString() throws -> String {
      let count = try word()
      guard count <= 4_096 else { throw DocumentParsingError.malformedDocument }
      let value = try bytes(count).prefix { $0 != 0 }
      return String(bytes: value, encoding: .windowsCP1252) ?? ""
    }

    mutating func string() throws -> String {
      let end = min(data.count, offset + 4_096)
      guard let zero = data[offset..<end].firstIndex(of: 0) else {
        throw DocumentParsingError.malformedDocument
      }
      let value = String(bytes: data[offset..<zero], encoding: .windowsCP1252) ?? ""
      offset = zero + 1
      return value
    }
  }
}
