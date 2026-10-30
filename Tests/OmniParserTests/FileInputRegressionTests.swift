import CoreGraphics
import Darwin
import Foundation
import ImageIO
@testable import OmniParser
import XCTest

final class FileInputRegressionTests: XCTestCase {
  func testURLSnapshotSurvivesSourceTruncationAndReplacement() async throws {
    let original = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let options = DocumentParserOptions(extractImages: true, performOCR: true)
    let expected = try await DocumentParser.parse(.data(original, fileName: "snapshot.png"),
                                                  options: options)
    XCTAssertFalse(expected.fullText.isEmpty)
    XCTAssertEqual(expected.images.count, 1)
    let directory = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let before = try Self.snapshotDirectories()
    for replace in [false, true] {
      let source = directory.appendingPathComponent(replace ? "replace.png" : "truncate.png")
      try original.write(to: source)
      let replacement = replace ? Data("replaced source".utf8) : Data()
      let result = try await DocumentParser.parse(.url(source), options: options) { event in
        guard event.phase == .extracting else { return }
        do {
          if replace {
            try replacement.write(to: source, options: .atomic)
          } else {
            let handle = try FileHandle(forWritingTo: source)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
          }
          XCTAssertEqual(try Self.snapshotDirectories(), before)
        } catch { XCTFail("소유한 원본 파일 변경에 실패했습니다: \(error)") }
      }
      XCTAssertEqual(try Data(contentsOf: source), replacement)
      XCTAssertNotEqual(replacement, original)
      try assertEquivalent(result, expected)
      XCTAssertEqual(try Self.snapshotDirectories(), before)
    }
  }

  func testSymbolicLinkURLPreservesTextInput() async throws {
    let directory = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = Data("한영 파일 입력 Research input 2026".utf8)
    let source = directory.appendingPathComponent("original.txt")
    let link = directory.appendingPathComponent("linked.txt")
    try bytes.write(to: source)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    let before = try Self.snapshotDirectories()
    let actual = try await DocumentParser.parse(.url(link))
    let expected = try await DocumentParser.parse(.data(bytes, fileName: "linked.txt"))
    XCTAssertEqual(actual, expected)
    XCTAssertEqual(try Self.snapshotDirectories(), before)
  }

  func testURLWithNULDoesNotReadValidPathPrefix() async throws {
    let directory = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("good.txt")
    let bytes = Data("valid prefix must remain private".utf8)
    try bytes.write(to: source)
    guard let invalid = URL(string: source.absoluteString + "%00suffix"),
      invalid.isFileURL else {
      throw XCTSkip("Foundation이 NUL이 인코딩된 파일 URL을 표현하지 못합니다.")
    }
    XCTAssertTrue(invalid.path(percentEncoded: true).contains("%00"))
    let before = try Self.snapshotDirectories()
    do {
      _ = try await DocumentParser.parse(.url(invalid))
      XCTFail("NUL 앞의 정상 경로를 읽었습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .unreadableInput) }
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    XCTAssertEqual(try Self.snapshotDirectories(), before)
    let literal = directory.appendingPathComponent("literal%00.txt")
    try bytes.write(to: literal)
    XCTAssertFalse(literal.path(percentEncoded: true).contains("%00"))
    let parsed = try await DocumentParser.parse(.url(literal))
    let expected = try await DocumentParser.parse(.data(bytes, fileName: "literal%00.txt"))
    XCTAssertEqual(parsed, expected)
  }

  func testImmutableSourceUsesCopyWithoutLeavingSnapshots() async throws {
    let directory = try Self.makeDirectory()
    let source = directory.appendingPathComponent("immutable.txt")
    var locked = false
    defer {
      if locked {
        XCTAssertEqual(source.path.withCString { Darwin.chflags($0, 0) }, 0,
                       "소유한 fixture의 잠금 플래그를 복구하지 못했습니다.")
      }
      try? FileManager.default.removeItem(at: directory)
    }
    let bytes = Data("잠긴 원본도 읽습니다. Immutable source 2026".utf8)
    try bytes.write(to: source)
    let result = source.path.withCString { Darwin.chflags($0, UInt32(UF_IMMUTABLE)) }
    guard result == 0 else {
      let failure = errno
      throw XCTSkip("환경이 immutable 플래그를 허용하지 않습니다: errno \(failure), "
        + String(cString: strerror(failure)))
    }
    locked = true
    let before = try Self.snapshotDirectories()
    let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
    XCTAssertEqual(attributes[.immutable] as? Bool, true)
    let actual = try await DocumentParser.parse(.url(source))
    let expected = try await DocumentParser.parse(.data(bytes, fileName: "immutable.txt"))
    XCTAssertEqual(actual, expected)
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    let after = try FileManager.default.attributesOfItem(atPath: source.path)
    XCTAssertEqual(after[.immutable] as? Bool, true)
    XCTAssertEqual(try Self.snapshotDirectories(), before)
  }

  func testMappingPolicyAcceptsOnlySafeProtectionValues() {
    XCTAssertTrue(DocumentInputReader.permitsMapping(nil))
    XCTAssertTrue(DocumentInputReader.permitsMapping(FileProtectionType.none.rawValue))
    XCTAssertTrue(DocumentInputReader.permitsMapping(
      FileProtectionType.completeUntilFirstUserAuthentication.rawValue))
    for value in [FileProtectionType.complete.rawValue,
                  FileProtectionType.completeUnlessOpen.rawValue,
                  "NSFileProtectionCompleteWhenUserInactive", "unknown", ""] {
      XCTAssertFalse(DocumentInputReader.permitsMapping(value), value)
    }
    let nonStrings: [Any] = [123, Data(), ["NSFileProtectionNone"]]
    for value in nonStrings {
      XCTAssertFalse(DocumentInputReader.permitsMapping(value))
    }
  }

  func testURLLimitAndFailuresLeaveNoSnapshots() async throws {
    let directory = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("input.txt")
    try Data("too large".utf8).write(to: source)
    let malformed = directory.appendingPathComponent("broken.pdf")
    try Data([0, 1, 2]).write(to: malformed)
    let missing = directory.appendingPathComponent("missing.txt")
    let before = try Self.snapshotDirectories()
    for (url, options, expected) in [
      (source, DocumentParserOptions(maximumInputBytes: 1), DocumentParsingError.inputTooLarge),
      (malformed, DocumentParserOptions(), .unsupportedFormat),
      (missing, DocumentParserOptions(), .unreadableInput)
    ] {
      do {
        _ = try await DocumentParser.parse(.url(url), options: options)
        XCTFail("실패해야 하는 URL을 허용했습니다.")
      } catch { XCTAssertEqual(error as? DocumentParsingError, expected) }
      XCTAssertEqual(try Self.snapshotDirectories(), before)
    }
  }

  func testURLCancellationBeforeReadingLeavesSourceAndSnapshotsUnchanged() async throws {
    let directory = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("cancel-before-read.txt")
    let bytes = Data("입력 읽기 전 취소 Cancel before read".utf8)
    try bytes.write(to: source)
    let before = try Self.snapshotDirectories()
    let progress = TestProgress()
    let task = Task {
      try await DocumentParser.parse(.url(source)) { event in
        progress.append(event)
        if event.phase == .identifying { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    do {
      _ = try await task.value
      XCTFail("URL 읽기 전 취소를 무시했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
    XCTAssertEqual(progress.values.map(\.phase), [.identifying, .cancelled])
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    XCTAssertEqual(try Self.snapshotDirectories(), before)
  }

  func testURLCancellationAfterReadingLeavesNoSnapshots() async throws {
    let directory = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("cancel.txt")
    try Data("cancel after snapshot".utf8).write(to: source)
    let before = try Self.snapshotDirectories()
    let progress = TestProgress()
    let task = Task {
      try await DocumentParser.parse(.url(source)) { event in
        progress.append(event)
        if event.phase == .extracting { withUnsafeCurrentTask { $0?.cancel() } }
      }
    }
    do {
      _ = try await task.value
      XCTFail("URL 읽기 뒤 취소를 무시했습니다.")
    } catch { XCTAssertEqual(error as? DocumentParsingError, .cancelled) }
    XCTAssertEqual(progress.values.last?.phase, .cancelled)
    XCTAssertFalse(progress.values.contains { $0.phase == .completed })
    XCTAssertEqual(try Self.snapshotDirectories(), before)
  }

  private static func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OmniParserFileInputTests-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
  }

  private static func snapshotDirectories() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(
      atPath: FileManager.default.temporaryDirectory.path).filter {
        $0.hasPrefix(DocumentInputReader.temporaryPrefix)
      })
  }

  private func assertEquivalent(_ actual: DocumentParseResult,
                                _ expected: DocumentParseResult) throws {
    XCTAssertEqual(actual.format, expected.format)
    XCTAssertTrue(actual.fullText == expected.fullText)
    XCTAssertEqual(actual.blocks, expected.blocks)
    XCTAssertEqual(actual.warnings, expected.warnings)
    XCTAssertEqual(actual.images.count, expected.images.count)
    for (image, reference) in zip(actual.images, expected.images) {
      XCTAssertEqual(image.id, reference.id)
      XCTAssertEqual(image.location, reference.location)
      XCTAssertEqual(image.orientation, reference.orientation)
      XCTAssertEqual(image.sourceDescription, reference.sourceDescription)
      XCTAssertEqual(try rasterFingerprint(image.pngData),
                     try rasterFingerprint(reference.pngData))
    }
    TestFixtures.assertTextConsistency(actual)
  }

  private func rasterFingerprint(_ data: Data) throws -> String {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    var pixels = Data(count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { storage in
      let context = try XCTUnwrap(CGContext(data: storage.baseAddress,
        width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue))
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    var fingerprint = Data("\(image.width)x\(image.height):".utf8)
    fingerprint.append(pixels)
    return TestFixtures.hash(fingerprint)
  }
}
