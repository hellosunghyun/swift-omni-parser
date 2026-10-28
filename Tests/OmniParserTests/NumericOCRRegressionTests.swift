import Foundation
@testable import OmniParser
import XCTest

/// 통화 기호를 보완할 때 금액과 구분자를 바꾸거나 낮은 신뢰도를 채택하지 않는다.
final class NumericOCRRegressionTests: XCTestCase {
  func testLoanCalculatorPreservesPrintedAmountsAndCorrectionHistory() async throws {
    let result = try await DocumentParser.parse(
      TestFixtures.input("RealWorld/jpeg/real-jpeg-03-loancalc.jpg"),
      options: .init(performOCR: true))
    // 기존 그림에 인쇄된 월 납입액·총이자·총비용을 확인한다.
    let amounts = ["$94.36", "$661.37", "$5,661.37"]
    let recognized = result.blocks.filter { $0.kind == .imageOCR }
    for amount in amounts {
      XCTAssertTrue(recognized.contains { $0.text == amount }, "인쇄된 금액이 누락됐습니다.")
    }
    let corrected = recognized.filter { $0.ocrOriginalText != nil }
    XCTAssertEqual(corrected.count, 2, "기존 입력에서 실제 숫자 보완이 발생해야 합니다.")
    XCTAssertTrue(Set(corrected.map(\.text)) == Set(amounts.dropFirst()),
                  "보완한 금액이 실제 인쇄된 총이자·총비용과 다릅니다.")
    for block in corrected {
      let original = try XCTUnwrap(block.ocrOriginalText)
      XCTAssertTrue(block.text.dropFirst() == original.dropFirst())
      XCTAssertNotNil(block.ocrConfidence)
      XCTAssertNotNil(block.location.bounds)
    }
    XCTAssertTrue(result.images.isEmpty)
    XCTAssertTrue(result.warnings.isEmpty)
    TestFixtures.assertTextConsistency(result)
  }

  func testCurrencyCorrectionPreservesAmountAndRequiresConfidence() {
    for original in ["S123.45", "5123.45", "S1,234.56"] {
      let corrected = "$" + original.dropFirst()
      XCTAssertTrue(DocumentNumericOCR.accepts(original, confidence: 0.5,
        alternative: corrected, alternativeConfidence: 0.5))
      XCTAssertFalse(DocumentNumericOCR.accepts(original, confidence: 0.5,
        alternative: corrected, alternativeConfidence: 0.49))
      XCTAssertFalse(DocumentNumericOCR.accepts(original, confidence: 0.5,
        alternative: "$999.99", alternativeConfidence: 0.9))
    }
  }

  func testCurrencyCorrectionRejectsOtherPrefixesAndNumberChanges() {
    let pairs = [
      ("123.45", "$23.45"), ("$123.45", "$123.45"), ("s123.45", "$123.45"),
      ("S123.45", "€123.45"), ("S123.45", "$123.46"), ("S1,234.56", "$1234.56"),
      ("S123", "$123"), ("S123.4", "$123.4"), ("S123.456", "$123.456"),
      ("S123.45 ", "$123.45"), (" S123.45", "$123.45")
    ]
    for (original, alternative) in pairs {
      XCTAssertFalse(DocumentNumericOCR.accepts(original, confidence: 0.5,
        alternative: alternative, alternativeConfidence: 0.9))
    }
  }
}
