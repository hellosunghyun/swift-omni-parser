import CoreGraphics
import Foundation
@testable import OmniParser
import XCTest

final class VectorLifecycleTests: XCTestCase {
  @MainActor private final class State { var completed = false }

  func testCancellationAfterWebKitStartedAllowsNextRender() async throws {
    let began = expectation(description: "WebKit 작업 시작")
    let state = await MainActor.run { State() }
    let nodes = (0..<5_000).map {
      "<rect x='\($0 % 512)' y='\($0 / 512)' width='1' height='1' fill='red'/>"
    }.joined()
    let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='512' height='512'>\(nodes)</svg>"
    let task = Task { @MainActor in
      began.fulfill()
      defer { state.completed = true }
      return try await DocumentVectorWebView.render(svg, size: CGSize(width: 512, height: 512))
    }
    await fulfillment(of: [began], timeout: 5)
    // MainActor 장벽 뒤에는 start의 동기 loadHTMLString 호출이 끝난 상태다.
    await MainActor.run {}
    try await Task.sleep(for: .milliseconds(10))
    let pending = await MainActor.run { !state.completed }
    XCTAssertTrue(pending, "취소 전에 WebKit 작업이 이미 종료돼 검증 조건이 성립하지 않았습니다.")
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("진행 중 WebKit 작업의 취소가 전파되지 않았습니다.")
    } catch { XCTAssertTrue(error is CancellationError) }
    let next = try await DocumentVectorRenderer.render(RTFVectorFixtures.emf(),
                                                       maximumPixels: 2_000_000)
    XCTAssertNotNil(next)
  }
}
