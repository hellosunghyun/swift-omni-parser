import CoreGraphics
import Foundation

/// RTF의 BMP 파일 헤더 없는 DIB를 검사한 뒤 ImageIO가 읽을 BMP로 감싼다.
/// 무압축 1·4·8비트 팔레트와 24·32비트 BITMAPINFOHEADER 계열만 처리한다.
nonisolated enum DocumentDIBDecoder {
  static func hasHeader(_ data: Data) -> Bool {
    guard let header = DocumentBinaryReader(data: data).uint32(0) else { return false }
    return [40, 52, 56, 108, 124].contains(header)
  }

  /// 미지원 헤더·압축 방식은 nil, 인식한 DIB의 손상·제한 초과는 오류로 구분한다.
  static func decode(_ data: Data, maximumPixels: Int) throws -> CGImage? {
    let reader = DocumentBinaryReader(data: data)
    guard hasHeader(data), let header = reader.uint32(0) else {
      return nil
    }
    guard header <= data.count,
      let rawWidth = reader.uint32(4), let rawHeight = reader.uint32(8),
      reader.uint16(12) == 1, let bits = reader.uint16(14),
      let compression = reader.uint32(16),
      let declaredSize = reader.uint32(20), let colorsUsed = reader.uint32(32)
    else { throw DocumentParsingError.malformedDocument }
    guard compression == 0, [1, 4, 8, 24, 32].contains(bits) else { return nil }
    let width = Int(Int32(bitPattern: UInt32(rawWidth)))
    let signedHeight = Int(Int32(bitPattern: UInt32(rawHeight)))
    let height = abs(signedHeight)
    guard width > 0, height > 0 else { throw DocumentParsingError.malformedDocument }
    guard maximumPixels > 0, width <= maximumPixels / height else {
      throw DocumentParsingError.inputTooLarge
    }
    let palette = colorsUsed == 0 && bits <= 8 ? 1 << bits : colorsUsed
    guard palette <= 256, bits > 8 || palette <= 1 << bits else {
      throw DocumentParsingError.malformedDocument
    }
    // BMP 행은 4바이트 경계다. 나눗셈으로 먼저 상한을 확인해 산술 오버플로를 막는다.
    guard width <= (Int.max - 31) / bits else {
      throw DocumentParsingError.inputTooLarge
    }
    let stride = ((width * bits + 31) / 32) * 4
    let pixelOffset = header + palette * 4
    guard pixelOffset <= data.count, stride <= (data.count - pixelOffset) / height else {
      throw DocumentParsingError.malformedDocument
    }
    let pixelBytes = stride * height
    guard declaredSize == 0 || (declaredSize >= pixelBytes
      && declaredSize <= data.count - pixelOffset) else {
      throw DocumentParsingError.malformedDocument
    }
    guard data.count <= Int(UInt32.max) - 14 else {
      throw DocumentParsingError.inputTooLarge
    }
    var bitmap = Data([0x42, 0x4D])
    appendWord(data.count + 14, to: &bitmap)
    appendWord(0, to: &bitmap)
    appendWord(pixelOffset + 14, to: &bitmap)
    bitmap.append(data)
    return try DocumentImageDecoder.decode(bitmap, maximumPixels: maximumPixels).image
  }

  private static func appendWord(_ value: Int, to data: inout Data) {
    for shift in stride(from: 0, to: 32, by: 8) {
      data.append(UInt8(truncatingIfNeeded: value >> shift))
    }
  }
}
