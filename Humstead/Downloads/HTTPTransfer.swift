import Foundation

struct HTTPResult: Sendable {
  let data: Data
  let status: Int
  let etag: String?
  let file: URL?
}

struct DownloadOrigin: Sendable {
  let url: URL
  init(_ url: URL, testing: Bool = false) throws {
    guard url.scheme == "https" || (testing && url.scheme == "http" && url.host == "127.0.0.1"),
      url.host != nil, url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil, ["", "/"].contains(url.path)
    else { throw DownloadError.invalidCatalog }
    self.url = url
  }
}

enum TransferError: Error {
  case status(Int)
  case invalidResponse, tooLarge, insufficientSpace
}

final class HTTPTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.mateusnroll.humstead.transfer")
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var continuation: CheckedContinuation<HTTPResult, any Error>?
  private var cancelled = false
  private var completed = false
  private var handle: FileHandle?
  private var ownsFile = false
  private var destination: URL?
  private var data = Data()
  private var received = 0
  private var limit = 0
  private var status = 0
  private var etag: String?
  private var capacity: @Sendable (URL) throws -> Int64 = availableCapacity
  private var progress: @Sendable (Int) -> Void = { _ in }

  static func request(
    origin: DownloadOrigin, path: String, limit: Int, timeout: Double = 30,
    etag: String? = nil, destination: URL? = nil,
    capacity: @escaping @Sendable (URL) throws -> Int64 = availableCapacity,
    progress: @escaping @Sendable (Int) -> Void = { _ in }
  ) async throws -> HTTPResult {
    let owner = HTTPTransfer()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        owner.queue.async {
          owner.continuation = continuation
          owner.destination = destination
          owner.limit = limit
          owner.capacity = capacity
          owner.progress = progress
          if owner.cancelled {
            owner.finish(.failure(CancellationError()))
            return
          }
          do {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            let audioPath =
              parts.count == 2 && parts[0] == "audio"
              && parts[1].count == 68
              && parts[1].prefix(64).allSatisfy { "0123456789abcdef".contains($0) }
              && [".m4a", ".caf"].contains(String(parts[1].suffix(4)))
            guard limit > 0, ["catalog/v1.json", "control/v1.json"].contains(path) || audioPath
            else { throw TransferError.invalidResponse }
            if let destination {
              guard
                try capacity(destination.deletingLastPathComponent()) >= Int64(limit) + 2_000_000
              else { throw TransferError.insufficientSpace }
              try Data().write(to: destination, options: .withoutOverwriting)
              owner.ownsFile = true
              owner.handle = try FileHandle(forWritingTo: destination)
            }
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = destination == nil ? timeout : 600
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1
            delegateQueue.underlyingQueue = owner.queue
            owner.session = URLSession(
              configuration: config, delegate: owner, delegateQueue: delegateQueue)
            var request = URLRequest(url: origin.url.appendingPathComponent(path))
            request.setValue("Humstead", forHTTPHeaderField: "User-Agent")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            owner.task = owner.session?.dataTask(with: request)
            owner.task?.resume()
          } catch { owner.finish(.failure(error)) }
        }
      }
    } onCancel: {
      owner.queue.async {
        owner.cancelled = true
        if owner.continuation != nil { owner.finish(.failure(CancellationError())) }
      }
    }
  }
  static func availableCapacity(_ url: URL) throws -> Int64 {
    let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values.volumeAvailableCapacityForImportantUsage ?? 0
  }
}

extension HTTPTransfer {
  private func finish(_ result: Result<HTTPResult, any Error>) {
    guard !completed else { return }
    completed = true
    task?.cancel()
    task = nil
    session?.invalidateAndCancel()
    session = nil
    do { try handle?.close() } catch {
      if case .success = result {
        handle = nil
        if ownsFile, let destination { try? FileManager.default.removeItem(at: destination) }
        continuation?.resume(throwing: error)
        continuation = nil
        return
      }
    }
    handle = nil
    if case .failure = result, ownsFile, let destination {
      try? FileManager.default.removeItem(at: destination)
    }
    continuation?.resume(with: result)
    continuation = nil
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard !completed, let response = response as? HTTPURLResponse else {
      completionHandler(.cancel)
      finish(.failure(TransferError.invalidResponse))
      return
    }
    status = response.statusCode
    etag = response.value(forHTTPHeaderField: "ETag")
    guard status == 200 || (status == 304 && destination == nil) else {
      completionHandler(.cancel)
      finish(.failure(TransferError.status(status)))
      return
    }
    let length = response.expectedContentLength
    guard length <= limit, destination == nil || length == -1 || length == limit else {
      completionHandler(.cancel)
      finish(.failure(TransferError.tooLarge))
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
    guard !completed else { return }
    do {
      guard chunk.count <= limit - received else { throw TransferError.tooLarge }
      if let destination {
        guard
          try capacity(destination.deletingLastPathComponent()) >= Int64(limit - received)
            + 2_000_000
        else { throw TransferError.insufficientSpace }
        try handle?.write(contentsOf: chunk)
      } else {
        data.append(chunk)
      }
      received += chunk.count
      progress(received)
    } catch { finish(.failure(error)) }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    guard !completed else { return }
    if let error {
      finish(.failure(error))
      return
    }
    guard destination == nil || received == limit else {
      finish(.failure(TransferError.invalidResponse))
      return
    }
    finish(.success(HTTPResult(data: data, status: status, etag: etag, file: destination)))
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
    finish(.failure(TransferError.invalidResponse))
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
      completionHandler(.performDefaultHandling, nil)
    } else {
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }
}
