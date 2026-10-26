import CryptoKit
import Foundation
import OmniParser
import XCTest

/// 테스트 자산은 번들에서만 읽으며 원격 파일을 가져오지 않는다.
enum TestFixtures {
  static let root = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")

  static func url(_ name: String) -> URL { root.appendingPathComponent(name) }

  static func input(_ name: String) -> DocumentInput { .url(url(name)) }

  static func json<T: Decodable>(_ name: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(contentsOf: url(name)))
  }

  static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// CFB는 유지하고 BIFF 버전만 손상시켜 백엔드의 실제 열기 실패를 유도한다.
  static func malformedWorkbook() throws -> DocumentInput {
    var bytes = try Data(contentsOf: url("LegacySample.xls"))
    let signature = Data([0x09, 0x08, 0x10, 0x00, 0x00, 0x06, 0x05, 0x00])
    let record = try XCTUnwrap(bytes.range(of: signature))
    bytes[record.lowerBound + 4] = 0xFF
    bytes[record.lowerBound + 5] = 0xFF
    return .data(bytes, fileName: "broken.xls")
  }

  static func assertTextConsistency(_ result: DocumentParseResult, file: StaticString = #filePath,
                                    line: UInt = #line) {
    XCTAssertEqual(result.blocks.map(\.readingOrder), Array(result.blocks.indices),
                   file: file, line: line)
    let text = result.blocks.filter {
      !$0.text.isEmpty && $0.kind != .table && $0.kind != .image
    }.map(\.text).joined(separator: "\n")
    // 원문을 assertion 진단 문자열에 넣지 않는다.
    XCTAssertTrue(result.fullText == text, "fullText와 블록이 다릅니다.", file: file, line: line)
  }
}

final class TestProgress: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [DocumentProgress] = []
  var values: [DocumentProgress] { lock.withLock { events } }
  func append(_ event: DocumentProgress) { lock.withLock { events.append(event) } }
}
