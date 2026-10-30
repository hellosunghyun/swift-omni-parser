import Foundation

/// UIKit이 버리는 그림·OLE를 분리하고 헤더·푸터를 보존한다. 본문 서식은 importer에 맡긴다.
/// 마커는 호출마다 새로 만들어 원문 텍스트와 충돌하지 않으며 결과에는 남기지 않는다.
nonisolated enum DocumentRTFPictureReader {
  struct Backup {
    var data: Data
    var offset: Int
    var malformed: Bool
  }

  struct Picture {
    var range: Range<Int>
    var data: Data
    var fallback = false
    var preferred = false
    var malformed = false
    var backup: Backup?
  }

  struct Object {
    var range: Range<Int>
    var data: Data
    var malformed: Bool
    var linked: Bool
    var resourceLimited: Bool
    var preview: Picture?
  }

  struct Section {
    var destination: String
    var range: Range<Int>
    var prefix: Range<Int>

    var part: String { "rtf/\(destination)/byte[\(range.lowerBound)]" }
  }

  struct Replacement {
    var range: Range<Int>
    var data: Data
  }

  struct Output {
    var data: Data
    var pictures: [Picture]
    var marker: String
    var warnings: [DocumentWarning]
    var sections: [Section]
    var objects: [Object]
  }

  struct Group {
    var start: Int
    var destination: String?
    var destinationEnd: Int?
    var data = Data()
    var nibble: UInt8?
    var malformed = false
    var objectData = Data()
    var linked = false
    var resourceLimited = false
  }

  static func read(_ data: Data, options: DocumentParserOptions) throws -> Output {
    var scanner = Scanner(bytes: [UInt8](data), options: options)
    return try scanner.read()
  }

  static func isSection(_ word: String) -> Bool {
    ["header", "headerl", "headerr", "headerf", "footer", "footerl", "footerr", "footerf"]
      .contains(word)
  }

  static func isLetter(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte)
  }

  static func hex(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48...57: byte - 48
    case 65...70: byte - 55
    case 97...102: byte - 87
    default: nil
    }
  }
}
