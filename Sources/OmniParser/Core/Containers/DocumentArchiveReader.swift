import Foundation
import zlib

/// ZIP 항목을 파일로 풀지 않고 읽는다. native 백엔드로 넘기기 전에 모든 항목의 실제
/// 해제량·CRC를 확인하며, 필요한 XML만 보관하고 나머지 출력은 작은 버퍼에서 버린다.
nonisolated enum DocumentArchiveReader {
  static func validateContents(_ data: Data, options: DocumentParserOptions) throws {
    _ = try read(data, options: options, retainXML: false)
  }

  static func xmlEntries(
    _ data: Data, options: DocumentParserOptions
  ) throws -> [(String, Data)] {
    _ = try DocumentArchiveGuard.entryNames(in: data, options: options)
    return try read(data, options: options, retainXML: true)
  }

  private static func read(
    _ data: Data, options: DocumentParserOptions, retainXML: Bool
  ) throws -> [(String, Data)] {
    let directory = try DocumentArchiveGuard.readDirectory(data)
    var cursor = directory.start
    var remaining = options.maximumExpandedBytes
    var result: [(String, Data)] = []
    for _ in 0..<directory.entryCount {
      try Task.checkCancellation()
      let entry = try DocumentArchiveGuard.readEntry(
        data, at: cursor, directoryEnd: directory.end)
      cursor = entry.nextOffset
      // XML 선택 읽기는 native 진입 전 전체 검사를 반복하지 않고 필요한 파트만 해제한다.
      if retainXML && !entry.name.hasSuffix(".xml") { continue }
      guard entry.uncompressedSize <= remaining else {
        throw DocumentParsingError.inputTooLarge
      }
      let packed = try compressedBytes(data, entry: entry, end: directory.start)
      let retained = retainXML && entry.name.hasSuffix(".xml")
      let bytes = try contents(packed, entry: entry, retain: retained)
      remaining -= entry.uncompressedSize
      if retained { result.append((entry.name, bytes)) }
    }
    return result
  }

  /// 로컬 헤더도 대조해 native ZIP 읽기와 검사의 항목 범위를 맞춘다.
  private static func compressedBytes(
    _ data: Data, entry: DocumentArchiveGuard.CentralDirectoryEntry, end: Int
  ) throws -> Data {
    let reader = DocumentBinaryReader(data: data)
    let offset = entry.localOffset
    guard offset >= 0, offset <= end - 30,
      reader.uint32(offset) == 0x0403_4B50
    else { throw DocumentParsingError.malformedDocument }
    let nameLength = Int(reader.uint16(offset + 26) ?? 0)
    let extraLength = Int(reader.uint16(offset + 28) ?? 0)
    let start = offset + 30 + nameLength + extraLength
    let finish = start + entry.compressedSize
    guard start <= end, finish <= end,
      reader.uint16(offset + 8) == entry.method,
      reader.uint16(offset + 6) == entry.flags,
      String(data: data[(offset + 30)..<(offset + 30 + nameLength)], encoding: .utf8)
        == entry.name
    else { throw DocumentParsingError.malformedDocument }
    if entry.flags & 0x0008 == 0 {
      guard reader.uint32(offset + 14) == entry.checksum,
        reader.uint32(offset + 18) == entry.compressedSize,
        reader.uint32(offset + 22) == entry.uncompressedSize
      else { throw DocumentParsingError.malformedDocument }
    } else {
      // 스트리밍 ZIP의 크기·CRC는 본문 뒤의 descriptor에 있다.
      let descriptor = finish + (reader.uint32(finish) == 0x0807_4B50 ? 4 : 0)
      guard descriptor <= end - 12,
        reader.uint32(descriptor) == entry.checksum,
        reader.uint32(descriptor + 4) == entry.compressedSize,
        reader.uint32(descriptor + 8) == entry.uncompressedSize
      else { throw DocumentParsingError.malformedDocument }
    }
    return data[start..<finish]
  }

  private static func contents(
    _ packed: Data, entry: DocumentArchiveGuard.CentralDirectoryEntry, retain: Bool
  ) throws -> Data {
    var output = Data()
    var count = 0
    var checksum: uLong = 0
    func consume(_ buffer: UnsafeRawBufferPointer) throws {
      guard buffer.count <= entry.uncompressedSize - count else {
        throw DocumentParsingError.inputTooLarge
      }
      count += buffer.count
      checksum = crc32(checksum, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count))
      if retain { output.append(buffer.bindMemory(to: UInt8.self)) }
    }
    switch entry.method {
    case 0: try packed.withUnsafeBytes(consume)
    case 8: try expand(packed, consume: consume)
    default: throw DocumentParsingError.unsupportedFormat
    }
    guard count == entry.uncompressedSize, Int(checksum) == entry.checksum else {
      throw DocumentParsingError.malformedDocument
    }
    return output
  }

  /// ZIP raw DEFLATE를 64KiB 단위로 해제한다. 출력 크기 초과·취소 시 즉시 중단하고
  /// 보관하지 않는 이미지·바이너리 항목도 전체 Data를 할당하지 않고 CRC를 확인한다.
  private static func expand(
    _ data: Data, consume: (UnsafeRawBufferPointer) throws -> Void
  ) throws {
    var stream = z_stream()
    guard inflateInit2_(
      &stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
    else { throw DocumentParsingError.malformedDocument }
    defer { inflateEnd(&stream) }
    try data.withUnsafeBytes { input in
      stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(input.count)
      var buffer = [UInt8](repeating: 0, count: 65_536)
      while true {
        try Task.checkCancellation()
        let status = buffer.withUnsafeMutableBytes { bytes -> Int32 in
          stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(bytes.count)
          return inflate(&stream, Z_NO_FLUSH)
        }
        let count = buffer.count - Int(stream.avail_out)
        try buffer.withUnsafeBytes { try consume(UnsafeRawBufferPointer(rebasing: $0[..<count])) }
        if status == Z_STREAM_END {
          guard stream.avail_in == 0 else { throw DocumentParsingError.malformedDocument }
          return
        }
        guard status == Z_OK, count > 0 else { throw DocumentParsingError.malformedDocument }
      }
    }
  }
}
