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
    package = word(package.count) + package
    let result = try await parse(object(package, className: "Package"))
    XCTAssertTrue(result.fullText.contains("Packaged text marker"))
    XCTAssertFalse(result.fullText.contains("example.invalid"))
    XCTAssertFalse(result.fullText.contains("outside/temp"))
    XCTAssertTrue(result.warnings.isEmpty)
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
    for _ in 0..<10 { nested = Data(("{\\rtf1 " + object(nested, className: "Text") + "}").utf8) }
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

  private func object(_ native: Data, className: String, preview: Data? = nil) -> String {
    let name = Data((className + "\0").utf8)
    let bytes = word(0x501) + word(2) + word(name.count) + name
      + word(0) + word(0) + word(native.count) + native
    var source = "{\\object\\objemb{\\*\\objdata \(hex(bytes))}"
    if let preview { source += "{\\result{\\pict\\pngblip \(hex(preview))}}" }
    return source + "}"
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
