import Foundation
@testable import OmniParser
import XCTest

/// WebKit을 시작하기 전에 거부해야 하는 능동 콘텐츠·참조·할당 경계를 검증한다.
final class VectorSafetyTests: XCTestCase {
  func testStaticSVGAndLocalPaintReferenceRemainUsable() throws {
    let body = "<defs><linearGradient id='paint'><stop offset='0' stop-color='red'/>"
      + "</linearGradient></defs><rect width='1' height='1' fill='url(#paint)'/>"
    let size = try DocumentVectorSVG.validate(svg(body), maximumPixels: 1)
    XCTAssertEqual(size.width, 1)
    XCTAssertEqual(size.height, 1)
  }

  func testActiveContentAndExternalImageReferencesAreRejected() {
    let bodies = [
      "<script>alert(1)</script>", "<foreignObject><div>content</div></foreignObject>",
      "<image href='https://example.invalid/private.png'/>",
      "<image href='file:///private/image.png'/>",
      "<image href='data:image/svg+xml;base64,PHN2Zy8+'/>",
      "<rect onclick='alert(1)' width='1' height='1'/>"
    ]
    for body in bodies { assertRejected(svg(body), error: .malformedDocument) }
  }

  func testDocumentTypeAndEntityDeclarationsAreRejected() {
    let declaration = "<!DOCTYPE svg [<!ENTITY secret SYSTEM 'file:///private/data'>]>"
    assertRejected(declaration + svg("<text>&secret;</text>"), error: .malformedDocument)
    assertRejected("<!DOCTYPE svg>" + svg(""), error: .malformedDocument)
  }

  func testCSSExternalReferencesCannotBypassAttributeChecks() {
    for reference in ["url(https://example.invalid/image)", "url(file:///private/image)",
                      "url(data:image/png;base64,AA==)"] {
      assertRejected(svg("<rect width='1' height='1' fill='\(reference)'/>"),
                     error: .malformedDocument)
    }
  }

  func testDuplicateIdentifiersAndCyclicPaintReferencesAreRejected() {
    let bodies = [
      "<rect id='same'/><rect id='same'/>",
      "<defs><pattern id='a'><rect fill='url(#a)'/></pattern></defs>",
      "<defs><pattern id='a'><rect fill='url(#b)'/></pattern>"
        + "<pattern id='b'><rect fill='url(#a)'/></pattern></defs>"
    ]
    for body in bodies { assertRejected(svg(body), error: .malformedDocument) }
  }

  func testEmbeddedBitmapMetadataCannotExceedPixelBudget() {
    // BMP 헤더만 거대한 크기로 선언한다. 실제 거대 래스터를 생성하지 않는다.
    let image = bitmap(width: 16_384, height: 16_384).base64EncodedString()
    assertRejected(svg("<image href='data:image/bmp;base64,\(image)'/>"),
                   error: .inputTooLarge)
  }

  func testEmbeddedBitmapPixelsShareOneBudget() throws {
    let image = bitmap(width: 1, height: 1).base64EncodedString()
    let element = "<image href='data:image/bmp;base64,\(image)'/>"
    XCTAssertNoThrow(try DocumentVectorSVG.validate(svg(element), maximumPixels: 1))
    assertRejected(svg(element + element), error: .inputTooLarge)
  }

  func testMalformedNativeRecordsAreRejectedBeforeJavaScript() {
    var wmf = RTFVectorFixtures.wmf()
    wmf.replaceSubrange(40..<44, with: dword(0))
    var emf = RTFVectorFixtures.emf()
    emf.replaceSubrange(92..<96, with: dword(7))
    for data in [wmf, emf] {
      guard let kind = DocumentMetafileGuard.kind(data) else {
        XCTFail("손상된 레코드의 원래 컨테이너 형식을 잃었습니다.")
        continue
      }
      XCTAssertThrowsError(try DocumentMetafileGuard.validate(data, kind: kind,
                                                            maximumPixels: 1_000_000)) {
        XCTAssertEqual($0 as? DocumentParsingError, .malformedDocument)
      }
    }
  }

  func testNativePointCountAndInputBytesAreBounded() throws {
    var emf = Data(RTFVectorFixtures.emf().prefix(88))
    emf.replaceSubrange(48..<52, with: dword(116))
    emf.replaceSubrange(52..<56, with: dword(2))
    // POLYBEZIER record에는 좌표가 없는데 2^32-1개 점을 선언한다.
    let points = dword(2) + dword(28) + Data(repeating: 0, count: 16)
    emf.append(points + dword(Int(UInt32.max)))
    XCTAssertThrowsError(try DocumentMetafileGuard.validate(emf, kind: .emf,
                                                          maximumPixels: 1_000_000)) {
      XCTAssertEqual($0 as? DocumentParsingError, .malformedDocument)
    }
    let oversized = Data(repeating: 0, count: 8 * 1024 * 1024 + 1)
    XCTAssertThrowsError(try DocumentMetafileGuard.validate(oversized, kind: .wmf(0),
                                                          maximumPixels: 1_000_000)) {
      XCTAssertEqual($0 as? DocumentParsingError, .inputTooLarge)
    }
  }

  func testUnknownWMFRecordPreservesImageAndReportsPartialSupport() async throws {
    var data = RTFVectorFixtures.wmf()
    // 유효한 EOF 앞에 모르는 함수를 추가하고 컨테이너 길이도 갱신한다.
    data.insert(contentsOf: dword(3) + Data([0xFF, 0x7F]), at: data.count - 6)
    data.replaceSubrange(28..<32, with: dword((data.count - 22) / 2))
    let output = try await DocumentVectorRenderer.renderDetailed(data, maximumPixels: 2_000_000)
    let result = try XCTUnwrap(output)
    XCTAssertTrue(result.hasUnsupportedElements)
    XCTAssertGreaterThan(result.image.width, 0)
    XCTAssertGreaterThan(result.image.height, 0)
    let source = RTFVectorFixtures.rtf(data, format: "wmetafile8")
    let offset = try XCTUnwrap(source.range(of: Data("{\\pict".utf8))).lowerBound
    try await assertPartialParse(source, part: "rtf/byte[\(offset)]/image[1]")
  }

  func testUnimplementedEMFRecordPreservesImageAndReportsPartialSupport() async throws {
    var data = RTFVectorFixtures.emf()
    // 알려진 EMR_FLATTENPATH는 upstream에서 logger만 실행하는 stub다.
    let count = try XCTUnwrap(DocumentBinaryReader(data: data).uint32(52))
    data.insert(contentsOf: dword(65) + dword(8), at: data.count - 20)
    data.replaceSubrange(48..<52, with: dword(data.count))
    data.replaceSubrange(52..<56, with: dword(count + 1))
    let output = try await DocumentVectorRenderer.renderDetailed(data, maximumPixels: 2_000_000)
    let result = try XCTUnwrap(output)
    XCTAssertTrue(result.hasUnsupportedElements)
    XCTAssertGreaterThan(result.image.width, 0)
    XCTAssertGreaterThan(result.image.height, 0)
    let source = RTFVectorFixtures.rtfNativeObject(data)
    let offset = try XCTUnwrap(source.range(of: Data("{\\object".utf8))).lowerBound
    try await assertPartialParse(source, part: "rtf/byte[\(offset)]/object[1]/metafile")
  }

  private func assertPartialParse(_ source: Data, part: String) async throws {
    let result = try await DocumentParser.parse(.data(source, fileName: "partial-vector.rtf"),
                                                options: .init(extractImages: true))
    XCTAssertEqual(result.images.count, 1, "미지원 레코드 앞에서 그린 이미지를 보존해야 합니다.")
    XCTAssertEqual(result.images.first?.location.part, part, "그림의 원본 위치를 유지해야 합니다.")
    XCTAssertTrue(result.warnings.contains {
      $0.code == .unsupportedElement && $0.location?.part == part
    }, "부분 렌더링 경고에 그림과 같은 원본 위치를 포함해야 합니다.")
    XCTAssertTrue(result.fullText.contains("After"), "그림 뒤의 본문을 보존해야 합니다.")
    TestFixtures.assertTextConsistency(result)
  }

  private func assertRejected(
    _ source: String, error: DocumentParsingError,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try DocumentVectorSVG.validate(source, maximumPixels: 1),
                         file: file, line: line) {
      XCTAssertEqual($0 as? DocumentParsingError, error, file: file, line: line)
    }
  }

  private func svg(_ body: String) -> String {
    "<svg xmlns='http://www.w3.org/2000/svg' width='1' height='1'>\(body)</svg>"
  }

  private func bitmap(width: Int, height: Int) -> Data {
    var data = Data([0x42, 0x4D]) + dword(58) + dword(0) + dword(54)
    data.append(dword(40) + dword(width) + dword(height))
    data.append(contentsOf: [1, 0, 24, 0])
    data.append(dword(0) + dword(0) + Data(repeating: 0, count: 16))
    data.append(contentsOf: [0, 0, 255, 0])
    return data
  }

  private func dword(_ value: Int) -> Data {
    Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
  }
}
