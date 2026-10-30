import Foundation
import OmniParser
import XCTest

final class RTFObjectTests: XCTestCase {
  func testEmbeddedNativeDocumentKeepsTextTablesAndHostPosition() async throws {
    let native = try Data(contentsOf:
      TestFixtures.url("RealWorld/doc/real-doc-02-simple-table.doc"))
    let expected = try await DocumentParser.parse(.data(native, fileName: "sample.doc"))
    let result = try await parse(object(native, className: "Word.Document.8"))
    XCTAssertTrue(result.fullText.contains("Before"))
    XCTAssertTrue(result.fullText.contains("After"))
    for block in expected.blocks where !block.text.isEmpty {
      XCTAssertTrue(result.fullText.contains(block.text))
    }
    XCTAssertTrue(result.blocks.contains { $0.kind == .tableCell })
    XCTAssertTrue(result.blocks.filter { $0.kind == .tableCell }.allSatisfy {
      $0.location.part?.contains("/object[1]/") == true
    })
    XCTAssertTrue(result.images.isEmpty)
    TestFixtures.assertTextConsistency(result)
  }

  func testPackagedTextIgnoresStoredFilePaths() async throws {
    var package = Data([2, 0])
    package.append(Data("../../proof.txt\0https://example.invalid/private\0".utf8))
    package.append(word(0) + word(0))
    package.append(Data("/outside/temp/path\0".utf8))
    let text = Data("Packaged text marker".utf8)
    package.append(word(text.count) + text)
    let result = try await parse(object(package, className: "Package"))
    XCTAssertTrue(result.fullText.contains("Packaged text marker"))
    XCTAssertFalse(result.fullText.contains("example.invalid"))
    XCTAssertFalse(result.fullText.contains("outside/temp"))
    XCTAssertTrue(result.warnings.isEmpty)
    TestFixtures.assertTextConsistency(result)
  }

  func testCompoundNativeAndContentsStreamsAreExtracted() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    for (name, payload) in [("CONTENTS", png), ("\u{1}Ole10Native", word(png.count) + png)] {
      let container = RTFObjectContainer.make(name: name, payload: payload)
      let result = try await parse(object(container, className: "Paint.Picture"),
                                   options: .init(extractImages: true))
      XCTAssertEqual(result.images.count, 1)
      XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
      XCTAssertTrue(result.images.first?.location.part?.contains("/object[1]/") == true)
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testCompoundPackageRetainsNestedRTFTable() async throws {
    let rtf = Data("{\\rtf1\\trowd\\cellx4000\\intbl Native cell\\cell\\row}".utf8)
    var package = Data([2, 0]) + Data("table.rtf\0ignored-source\0".utf8)
    package.append(word(0) + word(0) + Data("ignored-temp\0".utf8))
    package.append(word(rtf.count) + rtf)
    // 큰 regular stream을 생성해 MiniFAT과 무관하게 native wrapper를 검증한다.
    package.append(Data(repeating: 0, count: 4096))
    let container = RTFObjectContainer.make(name: "\u{1}Ole10Native",
                                          payload: word(package.count) + package)
    let result = try await parse(object(container, className: "Package"))
    XCTAssertTrue(result.blocks.contains { $0.kind == .tableCell && $0.text == "Native cell" })
    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    TestFixtures.assertTextConsistency(result)
  }

  func testNativeImageSkipsDuplicatePreviewAndHonorsOptions() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    for images in [false, true] {
      let result = try await parse(object(png, className: "StaticDIB", preview: png),
        options: .init(extractImages: images))
      XCTAssertEqual(result.images.count, images ? 1 : 0)
      XCTAssertTrue(result.warnings.isEmpty)
      XCTAssertFalse(result.fullText.contains("OMNIRTF"))
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testCorruptNativeLengthKeepsPreviewAndOuterText() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let source = "{\\object\\objemb{\\*\\objdata 0105000002000000ffffffff}"
      + "{\\result{\\pict\\pngblip \(hex(png))}}}"
    let result = try await parse(source, options: .init(extractImages: true))
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.images[0].location.part?.contains("/object[1]/preview") == true)
    XCTAssertTrue(result.warnings.contains { $0.code == .unsupportedElement })
    XCTAssertTrue(result.fullText.contains("After"))
  }

  func testLinkedObjectIsNotParsedEvenWhenNativeDataExists() async throws {
    let source = object(Data("Private linked content".utf8), className: "Text")
      .replacingOccurrences(of: "\\objemb", with: "\\objlink")
    let result = try await parse(source)
    XCTAssertFalse(result.fullText.contains("Private linked content"))
    XCTAssertTrue(result.fullText.contains("After"))
    XCTAssertTrue(result.warnings.contains {
      $0.code == .unsupportedElement && $0.location?.part?.contains("/object[1]") == true
    })
  }

  func testObjectByteAndRecursiveDepthLimitsRetainSurroundingContent() async throws {
    let limited = try await parse(object(Data(repeating: 65, count: 200), className: "Text"),
      options: .init(maximumExpandedBytes: 32))
    XCTAssertTrue(limited.warnings.contains { $0.code == .resourceLimitReached })
    XCTAssertTrue(limited.fullText.contains("After"))
    var nested = Data("Innermost marker".utf8)
    for _ in 0..<10 {
      nested = Data(("{\\rtf1 Before\\par " + object(nested, className: "Text")
        + " After\\par}").utf8)
    }
    let result = try await DocumentParser.parse(.data(nested, fileName: "nested.rtf"))
    XCTAssertFalse(result.fullText.contains("Innermost marker"))
    XCTAssertTrue(result.warnings.contains { $0.code == .resourceLimitReached })
    XCTAssertTrue(result.fullText.contains("After"))
    TestFixtures.assertTextConsistency(result)
  }

  func testObjectAndInlinePicturesShareImageLimit() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let source = object(png, className: "StaticDIB") + "{\\pict\\pngblip \(hex(png))}"
    let result = try await parse(source,
      options: .init(extractImages: true, maximumEmbeddedImages: 1))
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.warnings.contains { $0.code == .resourceLimitReached })
    XCTAssertTrue(result.fullText.contains("After"))
  }

  func testPreferredObjectPreviewFallsBackToPNGWithinImageLimit() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let source = "{\\object\\objemb{\\*\\objdata 00}{\\result"
      + "{\\*\\shppict{\\pict\\wmetafile8 00}}"
      + "{\\nonshppict{\\pict\\pngblip \(hex(png))}}}}"
    let result = try await parse(source,
      options: .init(extractImages: true, maximumEmbeddedImages: 1))
    XCTAssertEqual(result.images.count, 1)
    XCTAssertTrue(result.warnings.contains { $0.code == .extractionFailed })
    XCTAssertTrue(result.fullText.contains("After"))
    TestFixtures.assertTextConsistency(result)
  }

  func testScannerSharesObjectDataBudgetAcrossSiblings() async throws {
    // 각 objdata는 24 bytes지만 두 객체의 합계는 32 bytes를 넘는다.
    let tiny = Data(repeating: 0, count: 24)
    let source = "{\\object{\\*\\objdata \(hex(tiny))}}"
    let result = try await parse(source + source,
                                 options: .init(maximumExpandedBytes: 32))
    XCTAssertTrue(result.warnings.contains { $0.code == .resourceLimitReached })
    XCTAssertTrue(result.fullText.contains("After"))
    TestFixtures.assertTextConsistency(result)
  }

  func testBinaryObjectDataDoesNotTreatBracesAsRTFGroups() async throws {
    let native = Data("Native text with {braces} and \\slashes".utf8)
    let payload = nativeBytes(native, className: "Text")
    var source = Data("{\\rtf1 Before{\\object{\\*\\objdata\\bin\(payload.count) ".utf8)
    source.append(payload)
    source.append(Data("}}After}".utf8))
    let result = try await DocumentParser.parse(.data(source, fileName: "binary-object.rtf"))
    XCTAssertTrue(result.fullText.contains("Native text with {braces} and \\slashes"))
    XCTAssertTrue(result.fullText.contains("After"))
    XCTAssertTrue(result.warnings.isEmpty)
  }

  func testObjectParsingPropagatesCancellation() async throws {
    let task = Task {
      try await parse(object(Data("Native marker".utf8), className: "Text"))
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("취소한 RTF 작업이 성공 결과를 반환했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
  }

  private func object(_ native: Data, className: String, preview: Data? = nil) -> String {
    let bytes = nativeBytes(native, className: className)
    var source = "{\\object\\objemb{\\*\\objdata \(hex(bytes))}"
    if let preview { source += "{\\result{\\pict\\pngblip \(hex(preview))}}" }
    return source + "}"
  }

  private func nativeBytes(_ native: Data, className: String) -> Data {
    let name = Data((className + "\0").utf8)
    return word(0x501) + word(2) + word(name.count) + name
      + word(0) + word(0) + word(native.count) + native
  }

  private func word(_ value: Int) -> Data {
    Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
  }

  private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }

  private func parse(
    _ object: String, options: DocumentParserOptions = .init()
  ) async throws -> DocumentParseResult {
    let source = "{\\rtf1 Before\\par \(object) After\\par}"
    return try await DocumentParser.parse(.data(Data(source.utf8), fileName: "generated.rtf"),
                                          options: options)
  }
}

/// 작은 CFB regular stream을 메모리에서 생성한다. 기존 Office 테스트의 FAT 배치를 따른다.
private enum RTFObjectContainer {
  static func make(name: String, payload: Data) -> Data {
    let sectors = (payload.count + 511) / 512
    precondition(payload.count >= 4096 && sectors + 2 < 128)
    var data = Data(repeating: 0, count: (sectors + 3) * 512)
    func put(_ offset: Int, _ value: Int, bytes: Int = 4) {
      for byte in 0..<bytes {
        data[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8))
      }
    }
    data.replaceSubrange(0..<8, with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    for (offset, value) in [(24, 0x003E), (26, 3), (28, 0xFFFE), (30, 9), (32, 6)] {
      put(offset, value, bytes: 2)
    }
    for (offset, value) in [(44, 1), (56, 4096), (60, 0xFFFF_FFFE), (68, 0xFFFF_FFFE)] {
      put(offset, value)
    }
    for index in 0..<109 { put(76 + index * 4, 0xFFFF_FFFF) }
    put(76, 1)
    for (index, name) in ["Root Entry", name].enumerated() {
      let offset = 512 + index * 128
      for (unitIndex, unit) in (name + "\0").utf16.enumerated() {
        put(offset + unitIndex * 2, Int(unit), bytes: 2)
      }
      put(offset + 64, (name.utf16.count + 1) * 2, bytes: 2)
      data[offset + 66] = index == 0 ? 5 : 2
      data[offset + 67] = 1
      for position in [68, 72] { put(offset + position, 0xFFFF_FFFF) }
      put(offset + 76, index == 0 ? 1 : 0xFFFF_FFFF)
      put(offset + 116, index == 0 ? 0xFFFF_FFFE : 2)
      put(offset + 120, index == 0 ? 0 : payload.count)
    }
    for index in 0..<128 { put(1024 + index * 4, 0xFFFF_FFFF) }
    put(1024, 0xFFFF_FFFE)
    put(1028, 0xFFFF_FFFD)
    for index in 0..<sectors {
      put(1024 + (index + 2) * 4, index + 1 == sectors ? 0xFFFF_FFFE : index + 3)
    }
    data.replaceSubrange(1536..<1536 + payload.count, with: payload)
    return data
  }
}
