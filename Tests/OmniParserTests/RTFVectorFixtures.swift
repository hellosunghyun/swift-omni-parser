import Foundation

/// 외부 파일 없이 MS-WMF/MS-EMF의 도형·문자 record를 직접 생성한다.
/// 그림 뒤의 빨간 사각형은 텍스트 OCR 성공과 별도로 실제 렌더링 픽셀을 검증한다.
enum RTFVectorFixtures {
  static let text = "VECTOR 한글 TEST"

  static func wmf(extraRecords: Int = 0, textSuffix: String = "") -> Data {
    var records = [wmfRecord(0x020B, word(0) + word(0)),
                   wmfRecord(0x020C, word(384) + word(1024))]
    records += [wmfRecord(0x02FC, word(0) + dword(0x00FF_FFFF) + word(0)),
                wmfRecord(0x012D, word(0)),
                wmfRecord(0x041B, word(384) + word(1024) + word(0) + word(0)),
                wmfRecord(0x02FC, word(0) + dword(0x0000_00FF) + word(0)),
                wmfRecord(0x012D, word(1)),
                wmfRecord(0x041B, word(340) + word(220) + word(240) + word(20))]
    var font = word(-64) + word(0) + word(0) + word(0) + word(700)
    font.append(contentsOf: [0, 0, 0, 129, 0, 0, 4, 0]) // HANGEUL_CHARSET
    let face = Data("Apple SD Gothic Neo\0".utf8)
    font.append(face + Data(repeating: 0, count: 32 - face.count))
    records += [wmfRecord(0x02FB, font), wmfRecord(0x012D, word(2)),
                wmfRecord(0x0209, dword(0)), wmfRecord(0x0102, word(1))]
    // WMF TextOut은 Unicode record가 없으므로 charset129의 CP949로 한글을 저장한다.
    let text = Data("VECTOR ".utf8) + Data([0xC7, 0xD1, 0xB1, 0xDB]) + Data((" TEST" + textSuffix).utf8)
    var output = word(text.count) + text
    if !output.count.isMultiple(of: 2) { output.append(0) }
    output.append(word(60) + word(40))
    records.append(wmfRecord(0x0521, output))
    for _ in 0..<extraRecords { records.append(wmfRecord(0x0102, word(1))) }
    records.append(wmfRecord(0, Data()))
    let body = records.reduce(into: Data()) { $0.append($1) }
    var placeable = join([dword(0x9AC6_CDD7), word(0), word(0), word(0),
                          word(1024), word(384), word(96), dword(0)])
    let words = stride(from: 0, to: 20, by: 2).map {
      Int(placeable[$0]) | Int(placeable[$0 + 1]) << 8
    }
    placeable.append(word(words.reduce(0, ^)))
    let header = join([word(1), word(9), word(0x0300), dword(9 + body.count / 2),
                       word(3), dword(records.map { $0.count / 2 }.max() ?? 3), word(0)])
    return placeable + header + body
  }

  static func emf(extraRecords: Int = 0) -> Data {
    var records = [emfRecord(17, dword(1)),
                   emfRecord(37, dword(0x8000_0000)),
                   emfRecord(43, rectangle(0, 0, 1024, 384)),
                   emfRecord(39, dword(1) + dword(0) + dword(0x0000_00FF) + dword(0)),
                   emfRecord(37, dword(1)),
                   emfRecord(43, rectangle(20, 240, 220, 340))]
    var font = dword(-64) + dword(0) + dword(0) + dword(0) + dword(700)
    font.append(contentsOf: [0, 0, 0, 1, 0, 0, 4, 0])
    let face = "Apple SD Gothic Neo".utf16.map { word(Int($0)) }.reduce(Data(), +)
    font.append(face + Data(repeating: 0, count: 64 - face.count))
    // ExtLogFontW는 LogFontW(92 bytes) 뒤의 optional font metadata까지 320 bytes다.
    font.append(Data(repeating: 0, count: 320 - font.count))
    records += [emfRecord(82, dword(2) + font), emfRecord(37, dword(2)),
                emfRecord(24, dword(0)), emfRecord(18, dword(1))]
    let string = text.utf16.map { word(Int($0)) }.reduce(Data(), +)
    var output = join([rectangle(0, 0, 1024, 384), dword(1),
                       dword(0x3F80_0000), dword(0x3F80_0000), dword(40), dword(60),
                       dword(text.utf16.count), dword(76), dword(0),
                       rectangle(0, 0, 0, 0), dword(0)])
    output.append(string)
    records.append(emfRecord(84, output))
    for _ in 0..<extraRecords { records.append(emfRecord(18, dword(1))) }
    records.append(emfRecord(14, dword(0) + dword(0) + dword(20)))
    let body = records.reduce(into: Data()) { $0.append($1) }
    let header = join([rectangle(0, 0, 1024, 384), rectangle(0, 0, 27093, 10160),
                       dword(0x464D_4520), dword(0x0001_0000), dword(88 + body.count),
                       dword(records.count + 1), word(3), word(0), dword(0), dword(0), dword(0),
                       dword(1024), dword(384), dword(271), dword(102)])
    return emfRecord(1, header) + body
  }

  static func rtf(_ data: Data, format: String, objectPreview: Bool = false) -> Data {
    var picture = "{\\pict\\\(format) \(hex(data))}"
    if objectPreview {
      picture = "{\\object\\objemb{\\*\\objdata 00}{\\result\(picture)}}"
    }
    return Data("{\\rtf1 Before\\par \(picture) After\\par}".utf8)
  }

  static func rtfNativeObject(_ data: Data) -> Data {
    let name = Data("StaticMetafile\0".utf8)
    let native = join([dword(0x501), dword(2), dword(name.count), name,
                       dword(0), dword(0), dword(data.count), data])
    let object = "{\\object\\objemb{\\*\\objdata \(hex(native))}}"
    return Data("{\\rtf1 Before\\par \(object) After\\par}".utf8)
  }

  static func rtfWithFallback(_ primary: Data, format: String, png: Data) -> Data {
    let source = "{\\rtf1 Before\\par{\\*\\shppict{\\pict\\\(format) \(hex(primary))}}"
      + "{\\nonshppict{\\pict\\pngblip \(hex(png))}}After\\par}"
    return Data(source.utf8)
  }

  private static func wmfRecord(_ function: Int, _ parameters: Data) -> Data {
    dword(3 + parameters.count / 2) + word(function) + parameters
  }

  private static func emfRecord(_ type: Int, _ parameters: Data) -> Data {
    let padding = (4 - parameters.count % 4) % 4
    return dword(type) + dword(8 + parameters.count + padding)
      + parameters + Data(repeating: 0, count: padding)
  }

  private static func rectangle(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Data {
    dword(left) + dword(top) + dword(right) + dword(bottom)
  }

  private static func join(_ parts: [Data]) -> Data {
    parts.reduce(into: Data()) { $0.append($1) }
  }

  private static func word(_ value: Int) -> Data {
    Data((0..<2).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
  }

  private static func dword(_ value: Int) -> Data {
    Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
  }

  private static func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
}
