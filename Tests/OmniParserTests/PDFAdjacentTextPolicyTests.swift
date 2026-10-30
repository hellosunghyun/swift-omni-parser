import CoreGraphics
import Foundation
@testable import OmniParser
import Synchronization
import XCTest

/// OCR 결과 변환 경계만 검사한다. 실제 문자 인식·PDFKit 좌표의 재현 증거와 구분한다.
final class PDFAdjacentTextPolicyTests: XCTestCase {
  private final class Calls: Sendable {
    private let count = Mutex(0)
    func record() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
  }

  func testAdjacentNumericSubstringIsPreserved() async throws {
    let native = Self.native("ITEM 12", bounds: .init(x: 0.10, y: 0.10, width: 0.10, height: 0.04))
    let recognized = Self.ocr("2", bounds: .init(x: 0.204, y: 0.10, width: 0.02, height: 0.04))
    try assertPositiveGap(native, recognized)
    let output = try await run(native: [native], recognized: recognized)
    XCTAssertEqual(output.result.blocks.filter { $0.kind == .imageOCR }, [recognized])
  }

  func testAdjacentIdenticalTextIsPreserved() async throws {
    let native = Self.native("ITEM 12", bounds: .init(x: 0.10, y: 0.10, width: 0.10, height: 0.04))
    let recognized = Self.ocr("ITEM 12",
      bounds: .init(x: 0.204, y: 0.10, width: 0.10, height: 0.04))
    try assertPositiveGap(native, recognized)
    let output = try await run(native: [native], recognized: recognized)
    XCTAssertEqual(output.result.blocks.filter { $0.kind == .imageOCR }, [recognized])
  }

  func testActuallyOverlappingIdenticalTextIsSuppressed() async throws {
    let bounds = CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.04)
    let native = Self.native("ITEM 12", bounds: bounds)
    let output = try await run(native: [native], recognized: Self.ocr("ITEM 12", bounds: bounds))
    XCTAssertTrue(output.result.blocks.filter { $0.kind == .imageOCR }.isEmpty)
  }

  func testOCRLineAcrossNativeBlocksIsSuppressed() async throws {
    let native = [
      Self.native("HELLO", bounds: .init(x: 0.10, y: 0.10, width: 0.08, height: 0.04)),
      Self.native("WORLD", bounds: .init(x: 0.19, y: 0.10, width: 0.10, height: 0.04))
    ]
    let recognized = Self.ocr("HELLO WORLD",
      bounds: .init(x: 0.10, y: 0.10, width: 0.19, height: 0.04))
    let output = try await run(native: native, recognized: recognized)
    XCTAssertTrue(output.result.blocks.filter { $0.kind == .imageOCR }.isEmpty)
  }

  func testDifferentOCRLineAcrossNativeBlocksIsPreserved() async throws {
    let native = [
      Self.native("HELLO", bounds: .init(x: 0.10, y: 0.10, width: 0.08, height: 0.04)),
      Self.native("THERE", bounds: .init(x: 0.19, y: 0.10, width: 0.10, height: 0.04))
    ]
    let recognized = Self.ocr("HELLO WORLD",
      bounds: .init(x: 0.10, y: 0.10, width: 0.19, height: 0.04))
    let output = try await run(native: native, recognized: recognized)
    XCTAssertEqual(output.result.blocks.filter { $0.kind == .imageOCR }, [recognized])
  }

  func testRemovingMarginOnlyNativeBlockDoesNotCreateDuplicateText() async throws {
    let native = [
      Self.native("A", bounds: .init(x: 0.10, y: 0.10, width: 0.08, height: 0.04)),
      Self.native("X", bounds: .init(x: 0.18, y: 0.144, width: 0.01, height: 0.01)),
      Self.native("B", bounds: .init(x: 0.19, y: 0.10, width: 0.10, height: 0.04))
    ]
    let recognized = Self.ocr("AB", bounds: .init(x: 0.10, y: 0.10, width: 0.19, height: 0.04))
    let candidateBounds = try XCTUnwrap(recognized.location.bounds)
    XCTAssertTrue(try XCTUnwrap(native[0].location.bounds).intersects(candidateBounds))
    XCTAssertFalse(try XCTUnwrap(native[1].location.bounds).intersects(candidateBounds))
    XCTAssertTrue(try XCTUnwrap(native[2].location.bounds).intersects(candidateBounds))
    let output = try await run(native: native, recognized: recognized)
    // 집합 축소가 relatedText에 새로운 부분 문자열을 만들더라도 기존 OCR을 버리면 안 된다.
    XCTAssertEqual(output.result.blocks.filter { $0.kind == .imageOCR }, [recognized])
  }

  private func assertPositiveGap(_ native: DocumentBlock, _ recognized: DocumentBlock) throws {
    let left = try XCTUnwrap(native.location.bounds)
    let right = try XCTUnwrap(recognized.location.bounds)
    XCTAssertFalse(left.intersects(right))
    XCTAssertGreaterThan(right.minX - left.maxX, 0)
    XCTAssertLessThan(right.minX - left.maxX, 0.005)
  }

  private func run(native: [DocumentBlock], recognized: DocumentBlock) async throws
    -> DocumentPDFPreparedPage {
    let bytes = Data([255, 255, 255, 255])
    let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
    let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8,
      bitsPerPixel: 32, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let job = DocumentPDFImageJob(raster: DocumentPDFRaster(image: image),
      location: .init(part: "boundary/image", page: 1,
        bounds: .init(x: 0, y: 0, width: 1, height: 1)))
    // 논리 경계 전용 fixture다. raster nil + imageJobs 존재는 생산 prepare 상태를 재현하지 않는다.
    // 페이지 래스터가 없으므로 주입 함수 이외의 페이지 OCR fallback은 실행될 수 없다.
    let prepared = DocumentPDFPreparedPage(index: 0, result: .init(blocks: native),
      raster: nil, imageJobs: [job], extractImages: false)
    let calls = Calls()
    let output = try await DocumentPDFPageParser.recognize(prepared) { _, _, _ in
      calls.record()
      return [recognized]
    }
    XCTAssertEqual(calls.value, 1)
    XCTAssertEqual(Array(output.result.blocks.prefix(native.count)), native)
    XCTAssertTrue(output.result.warnings.isEmpty && output.result.images.isEmpty)
    XCTAssertTrue(output.raster == nil && output.imageJobs.isEmpty)
    return output
  }

  private static func native(_ text: String, bounds: CGRect) -> DocumentBlock {
    DocumentBlock(kind: .paragraph, text: text, readingOrder: 0,
      location: .init(page: 1, bounds: bounds))
  }

  private static func ocr(_ text: String, bounds: CGRect) -> DocumentBlock {
    DocumentBlock(kind: .imageOCR, text: text, readingOrder: 99,
      location: .init(part: "boundary/image", page: 1, bounds: bounds),
      ocrConfidence: 0.85, ocrOriginalText: "BOUNDARY SOURCE")
  }
}
