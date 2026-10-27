import CoreGraphics
import Foundation
import ImageIO
import Vision

/// 모든 형식에서 공통으로 사용하는 온디바이스 Vision OCR이다.
/// 한영 인식 결과를 좌상단 기준 좌표와 읽기 순서가 있는 블록으로 변환한다.
nonisolated enum DocumentOCR {
  /// parse·parseBatch가 만든 풀을 자식 작업에 전달한다. 전역으로 모든 문서의 세션을 공유하지 않는다.
  @TaskLocal static var sessions: DocumentOCRSessionPool?

  static func recognize(
    image: CGImage,
    orientation: CGImagePropertyOrientation,
    location: DocumentLocation = DocumentLocation()
  ) async throws -> [DocumentBlock] {
    try Task.checkCancellation()
    let pool = sessions ?? DocumentOCRSessionPool()
    return try await pool.perform(image: image, orientation: orientation) {
      try await blocks($0, image: image, orientation: orientation, location: location)
    }
  }

  /// 기존 Vision revision 3과 같은 한영·정확도·언어 보정 설정을 사용한다.
  static func makeRequest() -> RecognizeTextRequest {
    var request = RecognizeTextRequest(.revision3)
    // Swift Vision 기본값(1/32)과 VN 요청 기본값(0)이 달라 작은 글자 기준을 명시한다.
    request.minimumTextHeightFraction = 0
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = [.init(identifier: "ko-KR"), .init(identifier: "en-US")]
    request.automaticallyDetectsLanguage = true
    return request
  }

  /// Vision의 좌하단 원점을 좌상단으로 뒤집는다. 부분 그림의 페이지 좌표 변환은 호출 측이 담당한다.
  private static func blocks(
    _ source: [RecognizedTextObservation], image: CGImage,
    orientation: CGImagePropertyOrientation, location: DocumentLocation
  ) async throws -> [DocumentBlock] {
    let enhanced = try await DocumentNumericOCR.refine(
      image: image, orientation: orientation, observations: source)
    var blocks: [DocumentBlock] = source.enumerated().compactMap { order, observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      var located = location
      let bounds = observation.boundingBox.cgRect
      located.bounds = CGRect(
        x: bounds.minX,
        y: 1 - bounds.maxY,
        width: bounds.width,
        height: bounds.height
      )
      return DocumentBlock(
        kind: .imageOCR,
        text: enhanced[observation.uuid]?.text ?? candidate.string,
        readingOrder: order,
        location: located,
        ocrConfidence: enhanced[observation.uuid]?.confidence ?? candidate.confidence,
        ocrOriginalText: enhanced[observation.uuid] == nil ? nil : candidate.string
      )
    }
    blocks.sortInGeometricReadingOrder()
    return blocks
  }
}
