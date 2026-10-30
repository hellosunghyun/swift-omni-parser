import Darwin
import Dispatch
import Foundation

/// URL 입력을 읽는 동안만 파일 제공자와 조정하고, 파싱 중에는 독립된 바이트를 유지한다.
/// 복제 가능한 파일은 비공개 COW 스냅샷을 읽어 큰 입력의 힙 복사를 피한다.
nonisolated enum DocumentInputReader {
  static let temporaryPrefix = "OmniParserInput-"

  @concurrent static func read(_ url: URL, maximumBytes: Int) async throws -> Data {
    try Task.checkCancellation()
    return try await withThrowingTaskGroup(of: Data.self) { group in
      group.addTask(executorPreference: DocumentInputReadExecutor.shared) {
        try readSynchronously(url, maximumBytes: maximumBytes)
      }
      guard let data = try await group.next() else { throw DocumentParsingError.unreadableInput }
      try Task.checkCancellation()
      return data
    }
  }

  private static func readSynchronously(_ url: URL, maximumBytes: Int) throws -> Data {
    guard url.isFileURL else { throw DocumentParsingError.unsupportedFormat }
    guard !url.path.utf8.contains(0), !url.path(percentEncoded: true).contains("%00") else {
      throw DocumentParsingError.unreadableInput
    }
    try Task.checkCancellation()
    let allowsSnapshot = isRegularFile(url)
    var outcome: Result<Data, Error>?
    var coordinationError: NSError?
    let coordinator = NSFileCoordinator(filePresenter: nil)
    coordinator.coordinate(readingItemAt: url, options: .withoutChanges,
      error: &coordinationError) { coordinatedURL in
      outcome = Result {
        try readCoordinated(coordinatedURL, maximumBytes: maximumBytes,
          allowsSnapshot: allowsSnapshot)
      }
    }
    try Task.checkCancellation()
    if let coordinationError { throw coordinationError }
    guard let outcome else { throw DocumentParsingError.unreadableInput }
    return try outcome.get()
  }

  /// 알 수 없는 보호 등급은 매핑하지 않는다. 속성이 없는 경우에는 Foundation이 판단한다.
  static func permitsMapping(_ protection: Any?) -> Bool {
    guard let protection else { return true }
    guard let value = protection as? String else { return false }
    return value == "NSFileProtectionNone"
      || value == "NSFileProtectionCompleteUntilFirstUserAuthentication"
  }

  private static func readCoordinated(
    _ url: URL, maximumBytes: Int, allowsSnapshot: Bool
  ) throws -> Data {
    guard !url.path.utf8.contains(0), !url.path(percentEncoded: true).contains("%00") else {
      throw DocumentParsingError.unreadableInput
    }
    try Task.checkCancellation()
    let descriptor = try openFile(url)
    defer { Darwin.close(descriptor) }
    let size = try checkedSize(descriptor, maximumBytes: maximumBytes)
    // 잠금·append 등의 플래그를 복제해 임시 파일 정리가 막히지 않게 한다.
    var info = stat()
    let hasNoFlags = fstat(descriptor, &info) == 0 && info.st_flags == 0
    // 링크 자체는 복제하지 않는다. 링크가 가리키는 기존 입력은 제한된 복사로 계속 지원한다.
    let protectionKey = FileAttributeKey(rawValue: "NSFileProtectionKey")
    if allowsSnapshot, hasNoFlags, isRegularFile(url),
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      permitsMapping(attributes[protectionKey]),
      let data = try snapshot(descriptor, maximumBytes: maximumBytes,
        protectionKey: protectionKey) {
      return data
    }
    return try copy(descriptor, size: size, maximumBytes: maximumBytes)
  }

  private static func isRegularFile(_ url: URL) -> Bool {
    var info = stat()
    let status = url.withUnsafeFileSystemRepresentation { path in
      path.map { lstat($0, &info) } ?? -1
    }
    return status == 0 && info.st_mode & S_IFMT == S_IFREG
  }

  /// 직접 생성에 성공한 0700 디렉터리만 소유하며, 원본 파일의 속성은 변경하지 않는다.
  private static func snapshot(
    _ source: Int32, maximumBytes: Int, protectionKey: FileAttributeKey
  ) throws -> Data? {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      temporaryPrefix + UUID().uuidString, isDirectory: true)
    let created = directory.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.mkdir($0, mode_t(0o700)) } ?? -1
    }
    guard created == 0 else { return nil }
    do {
      let data = try snapshotData(source, directory: directory, maximumBytes: maximumBytes,
        protectionKey: protectionKey)
      // 성공이나 fallback을 반환하기 전에 정리 실패도 호출자에게 보고한다.
      try removeSnapshot(directory)
      return data
    } catch {
      try? removeSnapshot(directory)
      throw error
    }
  }

  private static func snapshotData(
    _ source: Int32, directory: URL, maximumBytes: Int, protectionKey: FileAttributeKey
  ) throws -> Data? {
    let url = directory.appendingPathComponent("input")
    // 경로가 교체되어도 이미 크기·종류를 확인한 같은 파일 디스크립터에서 복제한다.
    let cloned = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.fclonefileat(source, AT_FDCWD, $0, 0) } ?? -1
    }
    guard cloned == 0 else { return nil }
    try Task.checkCancellation()
    // 속성도 복제하며, 보호 등급을 낮추는 별도 속성 변경은 하지 않는다.
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      permitsMapping(attributes[protectionKey])
    else { return nil }
    let descriptor: Int32
    do { descriptor = try openFile(url) } catch { return nil }
    defer { Darwin.close(descriptor) }
    _ = try checkedSize(descriptor, maximumBytes: maximumBytes)
    // 매핑은 요청이며 실제 사용 여부는 Foundation이 판단한다.
    guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
    guard data.count <= maximumBytes else { throw DocumentParsingError.inputTooLarge }
    _ = try checkedSize(descriptor, maximumBytes: maximumBytes)
    // unlink 후에도 Data의 매핑은 유지되며, 원본 쓰기·truncate와 독립적이다.
    return data
  }

  /// 생성에 성공한 디렉터리 안의 복제본만 처리하며, 원본·보호 속성은 건드리지 않는다.
  private static func removeSnapshot(_ directory: URL) throws {
    let url = directory.appendingPathComponent("input")
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW) } ?? -1
    }
    if descriptor >= 0 {
      defer { Darwin.close(descriptor) }
      var info = stat()
      guard fstat(descriptor, &info) == 0 else { throw DocumentParsingError.unreadableInput }
      // 원본 플래그가 검사 후 바뀌어 복제되더라도, 자체 일반 파일의 삭제 방해 비트만 푼다.
      let blocked = UInt32(UF_IMMUTABLE | UF_APPEND | SF_IMMUTABLE | SF_APPEND | SF_NOUNLINK)
      if info.st_mode & S_IFMT == S_IFREG, info.st_flags & blocked != 0,
        fchflags(descriptor, info.st_flags & ~blocked) != 0 {
        throw DocumentParsingError.unreadableInput
      }
    }
    let removed = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.unlink($0) } ?? -1
    }
    guard removed == 0 || errno == ENOENT else { throw DocumentParsingError.unreadableInput }
    let cleared = directory.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.rmdir($0) } ?? -1
    }
    guard cleared == 0 else { throw DocumentParsingError.unreadableInput }
  }

  private static func openFile(_ url: URL) throws -> Int32 {
    // fstat로 일반 파일을 확인하기 전에 FIFO 등의 open에서 기다리지 않게 한다.
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NONBLOCK) } ?? -1
    }
    guard descriptor >= 0 else { throw DocumentParsingError.unreadableInput }
    return descriptor
  }

  private static func checkedSize(_ descriptor: Int32, maximumBytes: Int) throws -> Int {
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
      info.st_size >= 0
    else { throw DocumentParsingError.unreadableInput }
    guard info.st_size <= maximumBytes else { throw DocumentParsingError.inputTooLarge }
    return Int(info.st_size)
  }

  /// 메타데이터 조회 후 입력이 커져도 64KiB 단위로 읽고 누적 크기를 확인한다.
  private static func copy(_ descriptor: Int32, size: Int, maximumBytes: Int) throws -> Data {
    var data = Data()
    data.reserveCapacity(size)
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
      try Task.checkCancellation()
      let count = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(descriptor, bytes.baseAddress, bytes.count)
      }
      if count < 0 {
        if errno == EINTR { continue }
        throw DocumentParsingError.unreadableInput
      }
      if count == 0 { break }
      guard count <= maximumBytes - data.count else { throw DocumentParsingError.inputTooLarge }
      data.append(contentsOf: buffer.prefix(count))
    }
    _ = try checkedSize(descriptor, maximumBytes: maximumBytes)
    return data
  }
}

/// 동기 파일 조정은 기본 QoS 큐에서 수행하되 Swift 작업의 취소 컨텍스트는 유지한다.
nonisolated private final class DocumentInputReadExecutor: TaskExecutor {
  static let shared = DocumentInputReadExecutor()
  private let queue = DispatchQueue(label: "DocumentParsing.Input.Read", qos: .default,
    attributes: .concurrent, autoreleaseFrequency: .workItem)

  func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    queue.async(qos: .default, flags: .enforceQoS) {
      job.runSynchronously(on: self.asUnownedTaskExecutor())
    }
  }
}
