import Foundation
import OmniParser
import XCTest

final class APIContractTests: XCTestCase {
  func testBackendErrorsUseSamePublicCategoryInSingleAndBatch() async throws {
    let input = try TestFixtures.malformedWorkbook()
    let progress = TestProgress()
    do {
      _ = try await DocumentParser.parse(input) { progress.append($0) }
      XCTFail("손상된 백엔드 입력을 허용했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .malformedDocument) }
    XCTAssertEqual(progress.values.last?.phase, .failed)
    XCTAssertEqual(progress.values.filter { $0.phase == .failed }.count, 1)
    let batch = try await DocumentParser.parseBatch([
      input, .data(Data("kept".utf8), fileName: "kept.txt")
    ])
    guard case .failure(let error) = batch[0], case .success(let kept) = batch[1] else {
      return XCTFail("개별 실패 뒤의 결과를 보존하지 못했습니다.")
    }
    XCTAssertEqual(error, .malformedDocument)
    XCTAssertTrue(kept.fullText == "kept")
  }

  func testExistingPublicErrorCategoriesArePreserved() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let cases: [(DocumentInput, DocumentParsingError)] = [
      (.url(missing), .unreadableInput),
      (.data(Data([0, 1, 2]), fileName: "unknown.bin"), .unsupportedFormat)
    ]
    for (input, expected) in cases {
      do {
        _ = try await DocumentParser.parse(input)
        XCTFail("오류 입력을 허용했습니다.")
      } catch { XCTAssertEqual(error as? DocumentParsingError, expected) }
    }
  }

  func testImageAndOCROptionsAreIndependent() async throws {
    for images in [false, true] {
      for ocr in [false, true] {
        let result = try await DocumentParser.parse(TestFixtures.input("LegacySample.doc"),
          options: .init(extractImages: images, performOCR: ocr))
        XCTAssertEqual(result.images.count, images ? 1 : 0)
        XCTAssertEqual(result.blocks.contains { $0.kind == .imageOCR }, ocr)
        if ocr {
          XCTAssertTrue(result.fullText.contains("IMAGE OCR MARKER"))
          XCTAssertTrue(result.blocks.filter { $0.kind == .imageOCR }
            .allSatisfy { $0.ocrConfidence != nil })
        }
        TestFixtures.assertTextConsistency(result)
      }
    }
    let plain = try await DocumentParser.parse(TestFixtures.input("LegacySample.doc"))
    XCTAssertTrue(plain.images.isEmpty)
    XCTAssertFalse(plain.blocks.contains { $0.kind == .imageOCR })
  }

  func testBatchOrderIndividualFailureAndProgress() async throws {
    let progress = TestProgress()
    let inputs: [DocumentInput] = [
      .data(Data("first".utf8), fileName: "first.txt"),
      .data(Data([0, 1, 2]), fileName: "broken.doc"),
      TestFixtures.input("BinarySample.hwp"),
      .data(Data("last".utf8), fileName: "last.txt")
    ]
    let results = try await DocumentParser.parseBatch(inputs,
      options: .init(maximumConcurrentDocuments: 3)) { progress.append($0) }
    XCTAssertEqual(results.count, inputs.count)
    for (index, result) in results.enumerated() {
      switch result {
      case .success(let value):
        XCTAssertNotEqual(index, 1)
        if index == 0 { XCTAssertTrue(value.fullText == "first") }
        if index == 3 { XCTAssertTrue(value.fullText == "last") }
        TestFixtures.assertTextConsistency(value)
      case .failure:
        XCTAssertEqual(index, 1)
      }
      XCTAssertEqual(progress.values.last { $0.inputIndex == index }?.phase,
                     index == 1 ? .failed : .completed)
    }
  }

  @MainActor
  func testProgressDoesNotRunOnMainActor() async throws {
    _ = try await DocumentParser.parse(.data(Data("text".utf8), fileName: "note.txt")) { _ in
      XCTAssertFalse(Thread.isMainThread)
    }
  }
}
