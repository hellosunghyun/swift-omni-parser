import CoreGraphics
import Foundation

nonisolated enum DocumentPDFImageOCRChunk {
  /// 동일 bounds는 같은 chunk에 넣지 않아 기존 성공 중복 제거·빈 결과 재시도를 유지한다.
  @concurrent static func recognize(
    jobs: [DocumentPDFImageJob], start: Int, pageIndex: Int, successfulRegions: [CGRect],
    recognizeImage: @escaping @Sendable (CGImage, DocumentLocation, CGRect) async throws
      -> [DocumentBlock]
  ) async throws -> [(DocumentPDFImageJob, Result<[DocumentBlock], Error>)] {
    let pool = DocumentPDFScheduling.pool
    var selected: [(DocumentPDFImageJob, UUID?)] = [(jobs[start], nil)]
    while selected.count < 3, start + selected.count < jobs.count, let pool {
      let job = jobs[start + selected.count]
      if selected.contains(where: { $0.0.location.bounds == job.location.bounds }) { break }
      if let bounds = job.location.bounds, !bounds.isNull, !bounds.isEmpty,
        successfulRegions.contains(bounds) { break }
      guard let lease = await pool.tryAcquire(
        estimatedBytes: DocumentPDFWorkingMemory.recognitionReserveBytes) else { break }
      selected.append((job, lease))
    }
    return try await withThrowingTaskGroup(
      of: (Int, Result<[DocumentBlock], Error>).self
    ) { group in
      for (offset, item) in selected.enumerated() {
        group.addTask {
          let outcome: Result<[DocumentBlock], Error>
          do {
            try Task.checkCancellation()
            var timing = DocumentPDFTiming.start()
            let blocks = try await recognizeImage(
              item.0.raster.image, item.0.location, item.0.location.bounds ?? .zero)
            DocumentPDFTiming.record(&timing, page: pageIndex + 1, stage: "image_ocr_vision")
            outcome = .success(blocks)
          } catch is CancellationError {
            if let lease = item.1 { await pool?.release(lease) }
            throw CancellationError()
          } catch {
            outcome = .failure(error)
          }
          if let lease = item.1 { await pool?.release(lease) }
          return (offset, outcome)
        }
      }
      var results: [Result<[DocumentBlock], Error>?] = Array(repeating: nil, count: selected.count)
      for try await (offset, result) in group { results[offset] = result }
      return selected.enumerated().map { ($0.element.0, results[$0.offset]!) }
    }
  }

}
