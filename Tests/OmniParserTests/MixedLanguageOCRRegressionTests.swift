import CoreGraphics
import CoreText
import Foundation
import ImageIO
import OmniParser
import XCTest

/// 원래 실패했던 같은 행의 한영 문구를 공개 파싱 API와 자체 생성 픽셀로 검증한다.
final class MixedLanguageOCRRegressionTests: XCTestCase {
  func testMixedKoreanEnglishReceiptPreservesBothLanguages() async throws {
    try await assertMixedText(page: false)
  }

  func testMixedKoreanEnglishPagePreservesBothLanguages() async throws {
    try await assertMixedText(page: true)
  }

  func testEnglishPolicyPreservesGeneratedEnglishText() async throws {
    let lines = ["RESEARCH REPORT", "INVOICE TOTAL 125.00", "RESULTS 2026"]
    let image = try image(page: false, lines: lines)
    let result = try await DocumentParser.parse(.image(image, orientation: .up),
      options: .init(performOCR: true, ocrLanguage: .english))
    try assertResult(result, expected: lines, markers: ["RESEARCH", "TOTAL", "2026"])
  }

  func testKoreanEnglishPolicyAppliesToConcurrentBatchInputs() async throws {
    let lines = mixedLines(page: false)
    let image = try image(page: false, lines: lines)
    let input = DocumentInput.image(image, orientation: .up)
    let progress = TestProgress()
    let results = try await DocumentParser.parseBatch([input, input],
      options: .init(performOCR: true, maximumConcurrentDocuments: 2,
                     ocrLanguage: .koreanAndEnglish)) { progress.append($0) }
    XCTAssertEqual(results.count, 2)
    for (index, outcome) in results.enumerated() {
      guard case .success(let result) = outcome else {
        XCTFail("한영 배치 입력 \(index)의 성공 결과가 없습니다.")
        continue
      }
      try assertResult(result, expected: lines, markers: ["INVOICE", "영수증"])
    }
    let completed = progress.values.filter { $0.phase == .completed }.map(\.inputIndex)
    XCTAssertEqual(completed.sorted(), [0, 1])
    XCTAssertTrue(progress.values.allSatisfy { (0...1).contains($0.inputIndex) })
  }

  func testConcurrentLanguageRequestsDoNotChangeAutomaticResults() async throws {
    let lines = mixedLines(page: false)
    let image = try image(page: false, lines: lines)
    let before = try await DocumentParser.parse(.image(image, orientation: .up),
      options: .init(performOCR: true))
    async let automatic = DocumentParser.parse(.image(image, orientation: .up),
      options: .init(performOCR: true, ocrLanguage: .automatic))
    async let korean = DocumentParser.parseBatch([.image(image, orientation: .up)],
      options: .init(performOCR: true, ocrLanguage: .koreanAndEnglish))
    let (during, batch) = try await (automatic, korean)
    XCTAssertTrue(during == before, "동시에 실행한 다른 언어 정책이 자동 요청에 섞였습니다.")
    TestFixtures.assertTextConsistency(during)
    guard batch.count == 1, case .success(let result) = batch[0] else {
      return XCTFail("한영 배치의 결과가 보존되지 않았습니다.")
    }
    try assertResult(result, expected: lines, markers: ["INVOICE", "영수증"])
    let after = try await DocumentParser.parse(.image(image, orientation: .up),
      options: .init(performOCR: true))
    XCTAssertTrue(after == before, "명시한 언어 정책이 다음 기본 요청에 남았습니다.")
    TestFixtures.assertTextConsistency(after)
  }

  private func assertMixedText(page: Bool) async throws {
    let lines = mixedLines(page: page)
    let image = try image(page: page, lines: lines)
    let result = try await DocumentParser.parse(.image(image, orientation: .up),
      options: .init(performOCR: true, ocrLanguage: .koreanAndEnglish))
    try assertResult(result, expected: lines,
      markers: page ? ["RESEARCH", "연구"] : ["INVOICE", "영수증"])
  }

  private func mixedLines(page: Bool) -> [String] {
    page ? ["RESEARCH PAGE MARKER 연구 문서"] + (1...22).map {
      "연구 자료 \($0)  Document sample \($0)  Results 2026"
    } : ["INVOICE MARKER 영수증", "상품 A  12.50   ITEM B  25.00", "TOTAL 125.00  합계"]
  }

  private func assertResult(_ result: DocumentParseResult, expected: [String], markers: [String])
    throws {
    XCTAssertEqual(result.format, .image)
    XCTAssertTrue(result.images.isEmpty)
    XCTAssertTrue(result.warnings.isEmpty)
    XCTAssertFalse(result.blocks.isEmpty)
    XCTAssertTrue(result.blocks.allSatisfy { $0.kind == .imageOCR })
    for (index, marker) in markers.enumerated() {
      XCTAssertTrue(normalized(result.fullText).contains(normalized(marker)),
                    "한영 혼합 문구의 마커가 없습니다: marker \(index)")
    }
    // 원문을 assertion에 출력하지 않는다. 순서·대소문자·숫자 오류도 CER에 포함한다.
    let rate = characterErrorRate(expected.joined(separator: "\n"), result.fullText)
    XCTAssertLessThanOrEqual(rate, 0.01, "한영 혼합 문구 CER가 1%를 초과했습니다.")
    TestFixtures.assertTextConsistency(result)
    let boxes = try result.blocks.map { try XCTUnwrap($0.location.bounds) }
    XCTAssertTrue(zip(boxes, boxes.dropFirst()).allSatisfy { earlier, later in
      earlier.midY <= later.midY + min(earlier.height, later.height) / 2
    }, "단일 열의 읽기 순서가 위에서 아래로 이어지지 않습니다.")
    for block in result.blocks {
      let confidence = try XCTUnwrap(block.ocrConfidence)
      XCTAssertTrue(confidence.isFinite && (0...1).contains(confidence))
      let bounds = try XCTUnwrap(block.location.bounds)
      XCTAssertTrue(bounds.minX.isFinite && bounds.minY.isFinite)
      XCTAssertTrue(bounds.width.isFinite && bounds.height.isFinite)
      XCTAssertGreaterThan(bounds.width, 0)
      XCTAssertGreaterThan(bounds.height, 0)
      XCTAssertGreaterThanOrEqual(bounds.minX, 0)
      XCTAssertGreaterThanOrEqual(bounds.minY, 0)
      XCTAssertLessThanOrEqual(bounds.maxX, 1.000001)
      XCTAssertLessThanOrEqual(bounds.maxY, 1.000001)
    }
  }

  private func image(page: Bool, lines: [String]) throws -> CGImage {
    let width = page ? 1240 : 780, height = page ? 1754 : 326
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (index, line) in lines.enumerated() {
      let fontName = "AppleSDGothicNeo-Regular" as CFString
      let font = CTFontCreateWithName(fontName, page ? 32 : 28, nil)
      let value = NSAttributedString(string: line, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
          CGColor(gray: 0, alpha: 1)
      ])
      context.textPosition = CGPoint(x: 40, y: height - 65 - index * (page ? 65 : 80))
      CTLineDraw(CTLineCreateWithAttributedString(value), context)
    }
    return try XCTUnwrap(context.makeImage())
  }

  private func normalized(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace }
  }

  private func characterErrorRate(_ expected: String, _ actual: String) -> Double {
    let source = [Character](normalized(expected)), target = [Character](normalized(actual))
    var previous = Array(0...target.count)
    for (index, left) in source.enumerated() {
      var current = [index + 1]
      for (slot, right) in target.enumerated() {
        current.append(min(current[slot] + 1, previous[slot + 1] + 1,
                           previous[slot] + (left == right ? 0 : 1)))
      }
      previous = current
    }
    return Double(previous.last ?? 0) / Double(max(1, source.count))
  }
}
