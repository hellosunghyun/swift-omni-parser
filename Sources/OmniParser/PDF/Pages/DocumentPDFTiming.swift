import Foundation

/// 성능 분석을 명시적으로 켠 경우에만 본문과 경로 없이 단계별 시간을 기록한다.
nonisolated enum DocumentPDFTiming {
  private static let enabled = ProcessInfo.processInfo.environment["OMNIPARSER_PDF_TIMING"] == "1"

  static func start() -> UInt64 {
    enabled ? DispatchTime.now().uptimeNanoseconds : 0
  }

  static func record(_ start: inout UInt64, page: Int, stage: String) {
    guard enabled else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    let line = "{\"page\":\(page),\"stage\":\"\(stage)\",\"start_ns\":\(start),"
      + "\"end_ns\":\(now),\"elapsed_ns\":\(now - start)}\n"
    FileHandle.standardError.write(Data(line.utf8))
    start = DispatchTime.now().uptimeNanoseconds
  }
}
