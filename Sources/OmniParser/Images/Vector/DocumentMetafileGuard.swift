import Foundation

/// 레코드의 실제 범위와 알려진 배열·DIB 크기를 JS 실행 전에 검사한다.
nonisolated enum DocumentMetafileGuard {
  enum Kind { case wmf(Int), emf }

  static func kind(_ data: Data) -> Kind? {
    let reader = DocumentBinaryReader(data: data)
    if reader.uint32(0) == 0x9AC6CDD7 { return .wmf(22) }
    if reader.uint32(0) == 1, reader.uint32(40) == 0x464D4520 { return .emf }
    if let type = reader.uint16(0), [1, 2].contains(type), reader.uint16(2) == 9,
      let version = reader.uint16(4), [0x100, 0x300].contains(version) { return .wmf(0) }
    return nil
  }

  static func validate(_ data: Data, kind: Kind, maximumPixels: Int) throws {
    guard data.count <= 8 * 1024 * 1024, maximumPixels > 0 else {
      throw DocumentParsingError.inputTooLarge
    }
    let reader = DocumentBinaryReader(data: data)
    var offset = try initialOffset(reader, count: data.count, kind: kind)
    var count = 0
    while offset < data.count {
      try Task.checkCancellation()
      count += 1
      guard count <= 10_000 else { throw DocumentParsingError.inputTooLarge }
      let length: Int
      switch kind {
      case .wmf:
        guard let words = reader.uint32(offset), words >= 3,
          words <= (data.count - offset) / 2 else {
          throw DocumentParsingError.malformedDocument
        }
        length = words * 2
        try validateWMF(reader, offset: offset, length: length, maximumPixels: maximumPixels)
      case .emf:
        guard let size = reader.uint32(offset + 4), size >= 8,
          size % 4 == 0, size <= data.count - offset else {
          throw DocumentParsingError.malformedDocument
        }
        length = size
        try validateEMF(reader, offset: offset, length: length, maximumPixels: maximumPixels)
      }
      offset += length
    }
  }

  private static func initialOffset(
    _ reader: DocumentBinaryReader, count: Int, kind: Kind
  ) throws -> Int {
    switch kind {
    case .wmf(let header):
      guard reader.uint16(header + 2) == 9, let size = reader.uint32(header + 6),
        size >= 9, size <= (count - header) / 2 else {
        throw DocumentParsingError.malformedDocument
      }
      return header + 18
    case .emf:
      guard let header = reader.uint32(4), header >= 88, header <= count,
        let size = reader.uint32(48), size <= count, size >= header,
        let records = reader.uint32(52), records > 0 else {
        throw DocumentParsingError.malformedDocument
      }
      guard records <= 10_000 else { throw DocumentParsingError.inputTooLarge }
      return header
    }
  }

  private static func validateWMF(
    _ reader: DocumentBinaryReader, offset: Int, length: Int, maximumPixels: Int
  ) throws {
    let function = reader.uint16(offset + 4)
    if function == 0x0324 || function == 0x0325 {
      guard let points = reader.uint16(offset + 6), points <= (length - 8) / 4 else {
        throw DocumentParsingError.malformedDocument
      }
    }
    if function == 0x0521 {
      guard let bytes = reader.uint16(offset + 6), length >= 12 + bytes + bytes % 2 else {
        throw DocumentParsingError.malformedDocument
      }
    }
    let dibOffsets = [0x0B41: 26, 0x0F43: 28, 0x0940: 22]
    if let start = function.flatMap({ dibOffsets[$0] }), length >= start + 40 {
      try validateBitmap(reader, offset: offset + start, maximumPixels: maximumPixels)
    }
  }

  private static func validateEMF(
    _ reader: DocumentBinaryReader, offset: Int, length: Int, maximumPixels: Int
  ) throws {
    guard let type = reader.uint32(offset) else { throw DocumentParsingError.malformedDocument }
    if (2...6).contains(type) || (85...89).contains(type) {
      let stride = type >= 85 ? 4 : 8
      guard length >= 28, let points = reader.uint32(offset + 24),
        points <= (length - 28) / stride else { throw DocumentParsingError.malformedDocument }
    }
    let bitmapOffsets = [76: 84, 77: 84, 78: 84, 79: 84, 80: 48, 81: 48,
                         114: 84, 116: 84]
    if let field = bitmapOffsets[type], length >= field + 8,
      let start = reader.uint32(offset + field), start > 0 {
      guard start <= length - 40 else { throw DocumentParsingError.malformedDocument }
      try validateBitmap(reader, offset: offset + start, maximumPixels: maximumPixels)
    }
  }

  private static func validateBitmap(
    _ reader: DocumentBinaryReader, offset: Int, maximumPixels: Int
  ) throws {
    guard let header = reader.uint32(offset), header >= 40,
      let rawWidth = reader.uint32(offset + 4), let rawHeight = reader.uint32(offset + 8) else {
      throw DocumentParsingError.malformedDocument
    }
    let width = abs(Int(Int32(bitPattern: UInt32(rawWidth))))
    let height = abs(Int(Int32(bitPattern: UInt32(rawHeight))))
    guard width > 0, height > 0, width <= min(maximumPixels, 4_000_000) / height else {
      throw DocumentParsingError.inputTooLarge
    }
  }
}
