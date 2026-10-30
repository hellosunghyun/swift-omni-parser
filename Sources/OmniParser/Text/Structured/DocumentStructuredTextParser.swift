import CoreFoundation
import Foundation

/// 일반 텍스트·JSON·XML을 공통 문단 블록으로 바꾼다.
/// 구조를 읽지 못한 경우 원문 텍스트로 복구하며, 각 형식의 전체 표현을 재현하지는 않는다.
nonisolated enum DocumentStructuredTextParser {
  static func parsePlainText(_ text: String) -> [DocumentBlock] {
    text.components(separatedBy: .newlines).enumerated().compactMap { index, line in
      let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return nil }
      return DocumentBlock(
        kind: .paragraph,
        text: value,
        readingOrder: index,
        location: DocumentLocation(paragraph: index + 1)
      )
    }
  }

  /// 객체 키는 정렬해 안정된 순서를 만든다. 원본 JSON의 키 배치 순서를 복원하는 기능은 아니다.
  static func parseJSON(_ text: String, warnings: inout [DocumentWarning]) -> [DocumentBlock] {
    guard let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else {
      warnings.append(DocumentWarning(
        code: .malformedContent, message: "JSON structure failed; original text was retained.",
        location: DocumentLocation(part: "json")))
      return parsePlainText(text)
    }
    var blocks: [DocumentBlock] = []
    func visit(_ value: Any, path: String) {
      if let dictionary = value as? [String: Any] {
        for key in dictionary.keys.sorted() {
          visit(dictionary[key] ?? NSNull(), path: path.isEmpty ? key : "\(path).\(key)")
        }
      } else if let array = value as? [Any] {
        for (index, child) in array.enumerated() {
          visit(child, path: "\(path)[\(index)]")
        }
      } else {
        let string: String
        if let value = value as? String {
          string = value
        } else if value is NSNull {
          string = "null"
        } else if let number = value as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() {
          // JSONSerialization은 Bool도 NSNumber로 전달하므로 숫자 0·1과 구분한다.
          string = number.boolValue ? "true" : "false"
        } else {
          string = String(describing: value)
        }
        blocks.appendBlock(
          .paragraph, text: path.isEmpty ? string : "\(path): \(string)",
          location: DocumentLocation(part: path))
      }
    }
    visit(object, path: "")
    return blocks
  }

  static func parseXML(
    _ data: Data, fallbackText: String, warnings: inout [DocumentWarning]
  ) -> [DocumentBlock] {
    let delegate = XMLTextDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.externalEntityResolvingPolicy = .never
    guard parser.parse() else {
      warnings.append(DocumentWarning(
        code: delegate.blockedEntity ? .unsupportedElement : .malformedContent,
        message: "XML structure or entity expansion was skipped; original text was retained.",
        location: DocumentLocation(part: "xml", paragraph: max(1, parser.lineNumber))))
      return parsePlainText(fallbackText)
    }
    return delegate.blocks
  }

}
