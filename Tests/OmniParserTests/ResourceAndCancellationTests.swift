import Foundation
@testable import OmniParser
import XCTest

final class ResourceAndCancellationTests: XCTestCase {
  func testGeometricRowsDoNotChainAndPreserveMetadata() {
    let samples = [
      DocumentBlock(kind: .imageOCR, text: "a", readingOrder: 0,
        location: .init(part: "sample", bounds: .init(x: 0.6, y: 0.1, width: 0.1, height: 0.04)),
        ocrConfidence: 0.8, ocrOriginalText: "original-a"),
      DocumentBlock(kind: .imageOCR, text: "b", readingOrder: 0,
        location: .init(part: "sample", bounds: .init(x: 0.1, y: 0.115, width: 0.1, height: 0.04)),
        ocrConfidence: 0.9),
      DocumentBlock(kind: .imageOCR, text: "c", readingOrder: 0,
        location: .init(part: "sample", bounds: .init(x: 0.4, y: 0.13, width: 0.1, height: 0.04)))
    ]
    // 이웃끼리의 y 차이만 따라가면 다음 행까지 연결될 수 있어 첫 요소를 기준으로 묶는다.
    for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
      var blocks = order.map { samples[$0] }
      blocks.sortInGeometricReadingOrder()
      XCTAssertEqual(blocks.map(\.text), ["b", "a", "c"])
      XCTAssertEqual(blocks[1].location, samples[0].location)
      XCTAssertEqual(blocks[1].ocrConfidence, samples[0].ocrConfidence)
      XCTAssertEqual(blocks[1].ocrOriginalText, samples[0].ocrOriginalText)
      let once = blocks
      blocks.sortInGeometricReadingOrder()
      XCTAssertEqual(blocks, once)
    }
  }

  func testGeometricReadingOrderPreservesRowsPagesAndStructure() {
    let samples: [(String, CGRect)] = [
      ("right-1", CGRect(x: 0.5, y: 0.095, width: 0.2, height: 0.05)),
      ("left-1", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.04)),
      ("right-2", CGRect(x: 0.5, y: 0.175, width: 0.2, height: 0.05)),
      ("left-2", CGRect(x: 0.1, y: 0.18, width: 0.2, height: 0.04))
    ]
    var blocks = samples.reversed().map {
      DocumentBlock(kind: .imageOCR, text: $0.0, readingOrder: 0,
        location: .init(page: 1, bounds: $0.1))
    }
    blocks.appendBlock(.imageOCR, text: "page-2", location: .init(page: 2,
      bounds: .init(x: 0.1, y: 0.01, width: 0.2, height: 0.04)))
    blocks.appendBlock(.image, location: .init(page: 1, bounds: .init(x: 0, y: 0,
      width: 1, height: 1)))
    blocks.appendBlock(.table, location: .init(page: 1, bounds: .init(x: 0, y: 0.08,
      width: 1, height: 0.3)))
    blocks.sortInGeometricReadingOrder()
    XCTAssertEqual(blocks.prefix(2).map(\.kind), [.image, .table])
    XCTAssertEqual(blocks.filter { !$0.text.isEmpty }.map(\.text),
      ["left-1", "right-1", "left-2", "right-2", "page-2"])
    XCTAssertEqual(blocks.map(\.readingOrder), Array(blocks.indices))
  }

  func testSkippedRemoteHTMLImageKeepsBodyAndLocatedWarnings() async throws {
    let html = "<html><body><p>Kept</p><img src='https://example.invalid/image.png'></body></html>"
    let result = try await DocumentParser.parse(.data(Data(html.utf8), fileName: "remote.html"),
      options: .init(performOCR: true))
    XCTAssertEqual(result.fullText, "Kept")
    XCTAssertTrue(result.images.isEmpty)
    XCTAssertTrue(result.warnings.contains { $0.code == .externalImageSkipped })
    XCTAssertTrue(result.warnings.allSatisfy { $0.location != nil })
    TestFixtures.assertTextConsistency(result)
  }

  func testConcurrentOCRPreservesResultsAtUserInitiatedPriority() async throws {
    let input = TestFixtures.input("LegacyImage.png")
    let task = Task(priority: .userInitiated) {
      try await DocumentParser.parseBatch([input, input, input],
        options: .init(performOCR: true, maximumConcurrentDocuments: 2))
    }
    let results = try await task.value
    XCTAssertEqual(results.count, 3)
    var texts: [String] = []
    for outcome in results {
      guard case .success(let result) = outcome else { return XCTFail("병렬 OCR이 실패했습니다.") }
      XCTAssertTrue(result.fullText.contains("IMAGE OCR MARKER"))
      XCTAssertTrue(result.images.isEmpty)
      TestFixtures.assertTextConsistency(result)
      texts.append(result.fullText)
    }
    XCTAssertEqual(Set(texts).count, 1)
  }

  func testArchiveTraversalIsRejected() async {
    do {
      _ = try await DocumentParser.parse(TestFixtures.input("Generated/Traversal.docx"))
      XCTFail("경로 탈출 항목을 허용했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .malformedDocument) }
  }

  func testZIPRejectsMismatchedLocalAndCentralSizes() throws {
    let bytes = try Data(contentsOf: TestFixtures.url("Generated/LyingSize.docx"))
    XCTAssertThrowsError(try DocumentArchiveReader.xmlEntries(bytes, options: .init())) {
      XCTAssertEqual($0 as? DocumentParsingError, .malformedDocument)
    }
  }

  func testInputLimitRejectsBeforeExtraction() async {
    do {
      _ = try await DocumentParser.parse(.data(Data("too large".utf8), fileName: "note.txt"),
        options: .init(maximumInputBytes: 1))
      XCTFail("입력 한도를 적용하지 않았습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .inputTooLarge) }
  }

  func testStructuredTextRecoveryIsReported() async throws {
    for (name, text) in [("broken.json", "{\"value\":"),
                         ("broken.xml", "<root><value>kept</root>"),
                         ("broken.rtf", "{\\rtf1 kept")] {
      let result = try await DocumentParser.parse(.data(Data(text.utf8), fileName: name))
      XCTAssertFalse(result.fullText.isEmpty)
      XCTAssertTrue(result.warnings.contains {
        $0.code == .malformedContent && $0.location != nil
      })
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testSharedImagePathPreservesPNGWhenOCRFails() throws {
    let data = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let decoded = try DocumentImageDecoder.decode(data, maximumPixels: 40_000_000)
    let result = try DocumentRasterParser.parseImage(
      decoded.image, orientation: decoded.orientation, format: .image,
      location: .init(part: "test-image"), options: .init(extractImages: true, performOCR: true)
    ) { _, _, _ in throw DocumentParsingError.malformedDocument }
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.warnings.contains { $0.code == .imageOCRFailed })
    XCTAssertEqual(result.images.first?.location.part, "test-image")
  }

  func testXMLEntitiesAreNotExpanded() async throws {
    let source = "<!DOCTYPE root [<!ENTITY a 'ab'><!ENTITY b '&a;&a;'>]>"
      + "<root>&b;</root>"
    let result = try await DocumentParser.parse(.data(Data(source.utf8), fileName: "entity.xml"))
    XCTAssertFalse(result.fullText.contains("abab"))
    XCTAssertTrue(result.warnings.contains { $0.code == .unsupportedElement })
  }

  func testPartialImageFailureKeepsBodyAndTable() async throws {
    for (name, marker, hasTable) in [
      ("LegacySample.doc", "Legacy body marker", true),
      ("RealWorld/docx/real-docx-03-VariousPictures.docx", "Sheet with various pictures", false)
    ] {
      let result = try await DocumentParser.parse(TestFixtures.input(name),
        options: .init(extractImages: true, maximumImagePixels: 1))
      XCTAssertTrue(result.fullText.contains(marker))
      if hasTable { XCTAssertTrue(result.blocks.contains { $0.kind == .tableCell }) }
      XCTAssertTrue(result.images.isEmpty)
      XCTAssertTrue(result.warnings.contains { $0.location != nil })
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testCancellationAtExtractionReportsCancelled() async {
    let progress = TestProgress()
    let task = Task {
      try await DocumentParser.parse(.data(Data("cancel".utf8), fileName: "note.txt")) { event in
        progress.append(event)
        if event.phase == .extracting { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    do {
      _ = try await task.value
      XCTFail("추출 도중 취소를 무시했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
    XCTAssertEqual(progress.values.last?.phase, .cancelled)
    XCTAssertFalse(progress.values.contains { $0.phase == .completed })
  }

  func testOfficeTemporaryDirectoriesAreReleased() async throws {
    let before = try directories()
    _ = try await DocumentParser.parse(
      TestFixtures.input("RealWorld/xlsx/real-xlsx-01-DataTableCities.xlsx"))
    do {
      _ = try await DocumentParser.parse(TestFixtures.malformedWorkbook())
      XCTFail("잘못된 BIFF 버전을 허용했습니다.")
    } catch {
      XCTAssertEqual(error as? DocumentParsingError, .malformedDocument)
    }
    XCTAssertEqual(try directories(), before)
  }

}

extension ResourceAndCancellationTests {
  func testNativeZIPInputsValidateActualInflationBeforeOpening() async throws {
    let lying = try Data(contentsOf: TestFixtures.url("Generated/LyingSize.docx"))
    let directory = try DocumentArchiveGuard.readDirectory(lying)
    let entry = try DocumentArchiveGuard.readEntry(lying, at: directory.start,
                                                  directoryEnd: directory.end)
    let offset = entry.localOffset + 30 + entry.name.utf8.count
    let packed = Data(lying[offset..<(offset + entry.compressedSize)])
    let names = ["word/document.xml", "xl/workbook.xml", "ppt/presentation.xml",
                 "Contents/section0.xml"]
    for name in names {
      let data = zip(name: name, packed: packed, method: 8, size: 1, checksum: entry.checksum)
      do {
        _ = try await DocumentParser.parse(.data(data, fileName: nil),
          options: .init(maximumExpandedBytes: 64))
        XCTFail("native 백엔드 진입 전에 실제 해제량을 제한하지 않았습니다.")
      } catch { XCTAssertEqual(error as? DocumentParsingError, .inputTooLarge) }
    }
  }

  func testZIPChecksBinaryPayloadCRCAndAggregateBudget() async throws {
    let input = try Data(contentsOf: TestFixtures.url(
      "RealWorld/docx/real-docx-02-table_footnotes.docx"))
    do {
      _ = try await DocumentParser.parse(.data(input, fileName: "document.docx"),
        options: .init(maximumExpandedBytes: 1))
      XCTFail("누적 해제량 제한을 무시했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .inputTooLarge) }
    // 컨테이너 검사는 정상 CRC의 이미지 내용까지 해석하지 않는다. 디코딩 복구는 파서 책임이다.
    let opaque = zip(name: "image.bin", packed: Data([1, 2, 3]), method: 0,
                     size: 3, checksum: 0x55BC_801D)
    XCTAssertNoThrow(try DocumentArchiveGuard.validate(opaque, options: .init()))
    // XML이 아닌 항목도 버리기 전에 검증한다. 모든 출력 Data를 보관할 필요는 없다.
    let corrupted = zip(name: "image.bin", packed: Data([1, 2, 3]), method: 0,
                        size: 3, checksum: 0)
    XCTAssertThrowsError(try DocumentArchiveGuard.validate(corrupted, options: .init())) {
      XCTAssertEqual($0 as? DocumentParsingError, .malformedDocument)
    }
  }

  func testPDFWorkPoolReleasesWaitersAndCancelledReservations() async throws {
    let pool = DocumentPDFWorkPool(options: .init(maximumConcurrentPDFPages: 2,
                                                 pdfWorkingMemoryTargetBytes: 100))
    let first = try await pool.acquire(estimatedBytes: 60)
    let next = Task { try await pool.acquire(estimatedBytes: 60) }
    try await waitForQueuedWork(pool)
    let limited = await pool.snapshot()
    XCTAssertEqual(limited.activePages, 1)
    XCTAssertEqual(limited.reservedBytes, 60)
    next.cancel()
    do { _ = try await next.value; XCTFail("대기 예약 취소를 무시했습니다.") } catch is CancellationError { }
    await pool.release(first)
    // 목표보다 큰 페이지도 혼자 처리할 수 있으며 다음 예약은 반환까지 대기한다.
    let oversized = try await pool.acquire(estimatedBytes: 150)
    let after = Task { try await pool.acquire(estimatedBytes: 10) }
    try await waitForQueuedWork(pool)
    await pool.release(oversized)
    let admitted = try await after.value
    await pool.resize(admitted, actualBytes: 20)
    await pool.release(admitted)
    for _ in 0..<100 {
      let lease = try await pool.acquire(estimatedBytes: 100)
      let waiting = Task { try await pool.acquire(estimatedBytes: 1) }
      waiting.cancel()
      do {
        _ = try await waiting.value
        XCTFail("취소된 예약이 대기열에 남았습니다.")
      } catch is CancellationError { }
      await pool.release(lease)
    }
    let final = await pool.snapshot()
    XCTAssertEqual(final.activePages, 0)
    XCTAssertEqual(final.waitingRequests, 0)
    XCTAssertEqual(final.reservedBytes, 0)
  }

  private func waitForQueuedWork(_ pool: DocumentPDFWorkPool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await pool.snapshot().waitingRequests == 0, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    let state = await pool.snapshot()
    XCTAssertEqual(state.waitingRequests, 1)
  }

  /// ZIP 검증용 바이트를 메모리에서 만든다. 외부 샘플이나 영구 바이너리 자산은 추가하지 않는다.
  private func zip(name: String, packed: Data, method: Int, size: Int, checksum: Int) -> Data {
    let nameBytes = Data(name.utf8)
    func number(_ value: Int, _ count: Int = 4) -> Data {
      Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    var local = Data([0x50, 0x4B, 0x03, 0x04])
    for value in [20, 0, method, 0, 0] { local.append(number(value, 2)) }
    for value in [checksum, packed.count, size] { local.append(number(value)) }
    local.append(number(nameBytes.count, 2)); local.append(number(0, 2))
    local.append(nameBytes); local.append(packed)
    var central = Data([0x50, 0x4B, 0x01, 0x02])
    for value in [20, 20, 0, method, 0, 0] { central.append(number(value, 2)) }
    for value in [checksum, packed.count, size] { central.append(number(value)) }
    for value in [nameBytes.count, 0, 0, 0, 0] { central.append(number(value, 2)) }
    central.append(number(0)); central.append(number(0)); central.append(nameBytes)
    var end = Data([0x50, 0x4B, 0x05, 0x06])
    for value in [0, 0, 1, 1] { end.append(number(value, 2)) }
    end.append(number(central.count)); end.append(number(local.count)); end.append(number(0, 2))
    return local + central + end
  }

  private func directories() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(
      atPath: FileManager.default.temporaryDirectory.path).filter {
        $0.hasPrefix("DocumentParsing-")
      })
  }
}
