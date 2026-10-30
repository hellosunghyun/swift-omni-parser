import CoreGraphics
import Foundation

/// RTF 등에 포함된 WMF·EMF만 로컬 JS와 분리된 WebKit 문서로 래스터화한다.
/// 형식 판별·텍스트 추출과 독립적이며, 앱의 window나 view controller에 붙이지 않는다.
nonisolated enum DocumentVectorRenderer {
  struct Rendered {
    let image: CGImage
    let hasUnsupportedElements: Bool
  }

  private static let gate = DocumentVectorGate()

  static func matches(_ data: Data) -> Bool { DocumentMetafileGuard.kind(data) != nil }

  @concurrent static func render(_ data: Data, maximumPixels: Int) async throws -> CGImage? {
    try await renderDetailed(data, maximumPixels: maximumPixels)?.image
  }

  @concurrent static func renderDetailed(
    _ data: Data, maximumPixels: Int
  ) async throws -> Rendered? {
    guard let kind = DocumentMetafileGuard.kind(data) else { return nil }
    try DocumentMetafileGuard.validate(data, kind: kind, maximumPixels: maximumPixels)
    try await gate.acquire()
    do {
      try Task.checkCancellation()
      let converted = try DocumentVectorScript.convertDetailed(data)
      let size = try autoreleasepool {
        try DocumentVectorSVG.validate(converted.svg, maximumPixels: maximumPixels)
      }
      let image = try await DocumentVectorWebView.render(converted.svg, size: size)
      try Task.checkCancellation()
      await gate.release()
      return Rendered(image: image, hasUnsupportedElements: converted.hasUnsupportedElements)
    } catch {
      await gate.release()
      throw error
    }
  }
}

/// JSContext와 WebKit 작업을 합쳐 하나만 유지한다. 대기 중 취소도 슬롯을 소비하지 않는다.
private actor DocumentVectorGate {
  private var busy = false
  private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []

  func acquire() async throws {
    try Task.checkCancellation()
    if !busy { busy = true; return }
    let identifier = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiting.append((identifier, continuation))
      }
    } onCancel: {
      Task { await self.cancel(identifier) }
    }
  }

  func release() {
    if waiting.isEmpty { busy = false } else { waiting.removeFirst().1.resume() }
  }

  private func cancel(_ identifier: UUID) {
    guard let index = waiting.firstIndex(where: { $0.0 == identifier }) else { return }
    waiting.remove(at: index).1.resume(throwing: CancellationError())
  }
}
