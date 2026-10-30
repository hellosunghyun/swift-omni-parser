import Foundation

/// UIKit이 버리는 pict 그룹만 분리한다. 본문·유니코드·표 해석은 시스템 importer에 맡긴다.
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

  struct Section {
    var destination: String
    var range: Range<Int>
    var prefix: Range<Int>

    var part: String { "rtf/\(destination)/byte[\(range.lowerBound)]" }
  }

  private struct Replacement {
    var range: Range<Int>
    var data: Data
  }

  struct Output {
    var data: Data
    var pictures: [Picture]
    var marker: String
    var warnings: [DocumentWarning]
    var sections: [Section]
  }

  private struct Group {
    var start: Int
    var destination: String?
    var destinationEnd: Int?
    var data = Data()
    var nibble: UInt8?
    var malformed = false
  }

  static func read(_ data: Data, options: DocumentParserOptions) throws -> Output {
    var scanner = Scanner(bytes: [UInt8](data), options: options)
    return try scanner.read()
  }

  private struct Scanner {
    let bytes: [UInt8]
    let options: DocumentParserOptions
    var groups: [Group] = []
    var pictures: [Picture] = []
    var sections: [Section] = []
    var warnings: [DocumentWarning] = []
    var index = 0
    var attempts = 0

    var collecting: Bool {
      let backup = groups.dropLast().last?.destination == "nonshppict"
        && pictures.last?.preferred == true && attempts <= options.maximumEmbeddedImages
      return groups.last?.destination == "pict"
        && (attempts < options.maximumEmbeddedImages || backup)
        && (options.extractImages || options.performOCR)
    }

    mutating func read() throws -> Output {
      try Task.checkCancellation()
      var checkedOffset = 0
      while index < bytes.count {
        if index - checkedOffset >= 4_096 {
          try Task.checkCancellation()
          checkedOffset = index
        }
        switch bytes[index] {
        case 123:
          guard groups.count < 256 else { throw DocumentParsingError.inputTooLarge }
          groups.append(Group(start: index))
        case 125: try closeGroup()
        case 92:
          try control()
          continue
        default: appendHex(bytes[index])
        }
        index += 1
      }
      if !groups.isEmpty { warnTruncated() }
      return output()
    }

    private mutating func closeGroup() throws {
      guard let group = groups.popLast() else { warnTruncated(); return }
      if let destination = group.destination, isSection(destination),
        let end = group.destinationEnd {
        guard sections.count < options.maximumArchiveEntries else {
          throw DocumentParsingError.inputTooLarge
        }
        sections.append(Section(destination: destination, range: group.start..<(index + 1),
                                prefix: (group.start + 1)..<end))
      } else if group.destination == "pict" {
        guard pictures.count < options.maximumArchiveEntries else {
          throw DocumentParsingError.inputTooLarge
        }
        let isFallback = groups.last?.destination == "nonshppict"
        if !(isFallback && pictures.last?.preferred == true) { attempts += 1 }
        pictures.append(Picture(range: group.start..<(index + 1), data: group.data,
                                malformed: group.malformed || group.nibble != nil))
      } else if ["shppict", "nonshppict"].contains(group.destination),
        let last = pictures.indices.last, pictures[last].range.lowerBound > group.start {
        // Word의 연속된 shppict/nonshppict는 같은 그림의 원본·호환본이다.
        pictures[last].range = group.start..<(index + 1)
        pictures[last].fallback = group.destination == "nonshppict"
        pictures[last].preferred = group.destination == "shppict"
      }
    }

    private mutating func control() throws {
      index += 1
      guard index < bytes.count else { return }
      if bytes[index] == 39 {
        index = min(bytes.count, index + 3) // \'hh 안의 괄호는 그룹 경계가 아니다.
        return
      }
      guard isLetter(bytes[index]) else { index += 1; return }
      let start = index
      while index < bytes.count, isLetter(bytes[index]) {
        index += 1
        guard index - start <= 64 else { throw DocumentParsingError.malformedDocument }
      }
      let word = String(bytes: bytes[start..<index], encoding: .ascii) ?? ""
      let number = try parameter()
      if index < bytes.count, bytes[index] == 32 { index += 1 }
      if !groups.isEmpty, groups[groups.count - 1].destination == nil {
        groups[groups.count - 1].destination = word
        groups[groups.count - 1].destinationEnd = index
      }
      if word == "bin" { try appendBinary(number) }
    }

    private mutating func parameter() throws -> Int? {
      let start = index
      if index < bytes.count, bytes[index] == 45 { index += 1 }
      while index < bytes.count, (48...57).contains(bytes[index]) {
        index += 1
        guard index - start <= 20 else { throw DocumentParsingError.malformedDocument }
      }
      guard start < index else { return nil }
      guard let value = String(bytes: bytes[start..<index], encoding: .ascii).flatMap(Int.init)
      else { throw DocumentParsingError.malformedDocument }
      return value
    }

    private mutating func appendBinary(_ length: Int?) throws {
      // 손상된 길이를 시스템 importer에 전달하지 않아 거대한 할당을 유도하지 못하게 한다.
      guard let count = length, count >= 0, count <= bytes.count - index else {
        throw DocumentParsingError.malformedDocument
      }
      if collecting {
        groups[groups.count - 1].data.append(contentsOf: bytes[index..<(index + count)])
      }
      index += count
    }

    private mutating func appendHex(_ byte: UInt8) {
      guard collecting else { return }
      let slot = groups.count - 1
      if let value = hex(byte) {
        if let high = groups[slot].nibble {
          groups[slot].data.append(high * 16 + value)
          groups[slot].nibble = nil
        } else { groups[slot].nibble = value }
      } else if ![9, 10, 13, 32].contains(byte) { groups[slot].malformed = true }
    }

    private func output() -> Output {
      let marker = "OMNIRTF" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
      var replacements: [Replacement] = []
      var cursor = 0
      var selected: [Picture] = []
      var warnings = warnings
      var precedingPreferred: Range<Int>?
      for picture in pictures {
        guard picture.range.lowerBound >= cursor else { continue }
        let gap = bytes[cursor..<picture.range.lowerBound]
        let duplicate = picture.fallback && precedingPreferred != nil
          && gap.allSatisfy { [9, 10, 13, 32].contains($0) }
        if duplicate, let last = selected.indices.last,
          selected[last].range == precedingPreferred {
          selected[last].backup = Backup(data: picture.data,
            offset: picture.range.lowerBound, malformed: picture.malformed)
        }
        precedingPreferred = picture.preferred ? picture.range : nil
        // 그림을 생략할 때도 그룹 경계를 남겨 인접 control word와 본문이 합쳐지지 않게 한다.
        var value = Data([123])
        if !duplicate, options.extractImages || options.performOCR {
          appendMarker(picture, marker: marker, output: &value,
                       selected: &selected, warnings: &warnings)
        }
        value.append(125)
        replacements.append(Replacement(range: picture.range, data: value))
        cursor = picture.range.upperBound
      }
      let orderedSections = sections.sorted { $0.range.lowerBound < $1.range.lowerBound }
      for (index, section) in orderedSections.enumerated() {
        replacements.append(Replacement(range: section.prefix,
          data: Data("\\par \(marker)S\(index)BEGIN\\par ".utf8)))
        let end = section.range.upperBound - 1
        replacements.append(Replacement(range: end..<end,
          data: Data("\\par \(marker)S\(index)END\\par ".utf8)))
      }
      return Output(data: compose(replacements), pictures: selected, marker: marker,
                    warnings: warnings, sections: orderedSections)
    }

    private func compose(_ replacements: [Replacement]) -> Data {
      var output = Data()
      var cursor = 0
      for replacement in replacements.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
        guard replacement.range.lowerBound >= cursor else { continue }
        output.append(contentsOf: bytes[cursor..<replacement.range.lowerBound])
        output.append(replacement.data)
        cursor = replacement.range.upperBound
      }
      output.append(contentsOf: bytes[cursor...])
      return output
    }

    private func appendMarker(
      _ picture: Picture, marker: String, output: inout Data,
      selected: inout [Picture], warnings: inout [DocumentWarning]
    ) {
      if selected.count < options.maximumEmbeddedImages {
        output.append(Data("\(marker)N\(selected.count)END".utf8))
        selected.append(picture)
      } else if !warnings.contains(where: { $0.code == .resourceLimitReached }) {
        warnings.append(DocumentWarning(
          code: .resourceLimitReached, message: "RTF image count exceeded the limit.",
          location: DocumentLocation(part: "rtf/byte[\(picture.range.lowerBound)]")))
      }
    }

    private mutating func warnTruncated() {
      guard !warnings.contains(where: { $0.code == .malformedContent }) else { return }
      warnings.append(DocumentWarning(
        code: .malformedContent, message: "RTF group is unbalanced or truncated.",
        location: DocumentLocation(part: "rtf/byte[\(index)]")))
    }
  }

  private static func isSection(_ word: String) -> Bool {
    ["header", "headerl", "headerr", "headerf", "footer", "footerl", "footerr", "footerf"]
      .contains(word)
  }

  private static func isLetter(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte)
  }

  private static func hex(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48...57: byte - 48
    case 65...70: byte - 55
    case 97...102: byte - 87
    default: nil
    }
  }
}
