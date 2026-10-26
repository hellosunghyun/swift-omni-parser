import Foundation
import OmniParser
import XCTest

final class OfficeSourceTruthTests: XCTestCase {
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
