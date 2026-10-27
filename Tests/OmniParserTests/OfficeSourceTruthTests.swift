import Foundation
@testable import OmniParser
import XCTest

final class OfficeSourceTruthTests: XCTestCase {
  func testRepeatedLegacyPicturesPreserveEachOCRLocation() async throws {
    let png = try Data(contentsOf: TestFixtures.url("LegacyImage.png"))
    let data = LegacyPictureContainer.make(png)
    for extractImages in [false, true] {
      let result = try await DocumentLegacyOfficeSupplement.extract(
        data: data, format: .ppt,
        base: DocumentParseResult(format: .ppt, blocks: [], warnings: []),
        options: .init(extractImages: extractImages, performOCR: true), inspectedImages: 0)
      let recognized = result.blocks.filter { $0.kind == .imageOCR }
      let parts = Set(recognized.compactMap(\.location.part))
      XCTAssertEqual(parts.count, 2, "서로 다른 그림의 같은 문구도 각 위치에 남아야 합니다.")
      for part in parts {
        XCTAssertTrue(recognized.filter { $0.location.part == part }
          .map(\.text).joined(separator: " ").contains("IMAGE OCR MARKER"))
      }
      XCTAssertEqual(result.images.count, extractImages ? 2 : 0)
      XCTAssertEqual(Set(result.images.map(\.id)).count, result.images.count)
      XCTAssertFalse(result.warnings.contains { $0.code == .imageOCRFailed })
      TestFixtures.assertTextConsistency(result)
    }
  }

  func testChartCachesDoNotReplaceWorksheetCells() async throws {
    let root = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures")
    let result = try await DocumentParser.parse(
      .url(root.appendingPathComponent("RealWorld/xls/real-xls-03-testEXCEL-charts.xls")))
    let cells = result.blocks.filter { $0.kind == .tableCell }
    let keys = cells.map { cell in
      "\(cell.location.part ?? "")/\(cell.location.row ?? 0)/\(cell.location.column ?? 0)"
    }
    XCTAssertTrue(keys.count == Set(keys).count, "워크시트의 셀 주소는 중복되면 안 됩니다.")
    for (row, expected) in [(1, "Test Excel Spreasheet"), (2, "foo"), (3, "bar")] {
      let matches = cells.filter { $0.location.part == "Sheet1" && $0.location.row == row
        && $0.location.column == 1 }
      XCTAssertTrue(matches.count == 1 && matches.first?.text == expected,
        "A열 값은 차트 캐시가 아닌 원본 셀과 같아야 합니다.")
    }
  }
}

/// 실제 OfficeArt PNG 레코드 두 개를 정상 CFB 스트림에 넣는다. 외부 문서나 바이너리를 추가하지 않는다.
private enum LegacyPictureContainer {
  static func make(_ png: Data) -> Data {
    var picture = Data([0, 0, 0x1E, 0xF0])
    let length = png.count + 17
    picture.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: length >> ($0 * 8)) })
    picture.append(Data(repeating: 0, count: 17))
    picture.append(png)
    let pictures = picture + picture
    let sectors = (pictures.count + 511) / 512
    precondition(sectors + 2 < 128 && pictures.count >= 4096)
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
    func entry(_ index: Int, _ name: String, type: UInt8, first: Int, size: Int) {
      let offset = 512 + index * 128
      for (index, unit) in (name + "\0").utf16.enumerated() {
        put(offset + index * 2, Int(unit), bytes: 2)
      }
      put(offset + 64, (name.utf16.count + 1) * 2, bytes: 2)
      data[offset + 66] = type
      data[offset + 67] = 1
      put(offset + 68, 0xFFFF_FFFF)
      put(offset + 72, 0xFFFF_FFFF)
      put(offset + 76, index == 0 ? 1 : 0xFFFF_FFFF)
      put(offset + 116, first)
      put(offset + 120, size)
    }
    entry(0, "Root Entry", type: 5, first: 0xFFFF_FFFE, size: 0)
    entry(1, "Pictures", type: 2, first: 2, size: pictures.count)
    for index in 0..<128 { put(1024 + index * 4, 0xFFFF_FFFF) }
    put(1024, 0xFFFF_FFFE)
    put(1028, 0xFFFF_FFFD)
    for index in 0..<sectors {
      put(1024 + (index + 2) * 4, index + 1 == sectors ? 0xFFFF_FFFE : index + 3)
    }
    data.replaceSubrange(1536..<1536 + pictures.count, with: pictures)
    return data
  }
}
