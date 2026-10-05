import Foundation

final class UsageTransport: NSObject, UsageSending, URLSessionDataDelegate, @unchecked Sendable {
  private let endpoint: URL?
  private let queue = DispatchQueue(label: "com.mateusnroll.humstead.usage-http")
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var completion: (@Sendable () -> Void)?
  private var deadline: DispatchWorkItem?
  private var received = 0
  init(configuration: UsageConfiguration?) { endpoint = configuration?.endpoint }
  func send(_ data: Data, completion: @escaping @Sendable () -> Void) {
    queue.sync {
      guard let endpoint, task == nil, data.count <= 16384 else {
        completion()
        return
      }
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      configuration.urlCredentialStorage = nil
      configuration.urlCache = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.timeoutIntervalForRequest = 5
      configuration.timeoutIntervalForResource = 5
      let delegates = OperationQueue()
      delegates.maxConcurrentOperationCount = 1
      delegates.underlyingQueue = queue
      let session = URLSession(
        configuration: configuration, delegate: self, delegateQueue: delegates)
      var request = URLRequest(url: endpoint)
      request.httpMethod = "POST"
      request.httpBody = data
      request.setValue("Humstead", forHTTPHeaderField: "User-Agent")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      let task = session.dataTask(with: request)
      self.session = session
      self.task = task
      self.completion = completion
      received = 0
      let timeout = DispatchWorkItem { [weak self, weak task] in
        guard let self, let task, self.task === task else { return }
        finish()
      }
      deadline = timeout
      queue.asyncAfter(deadline: .now() + 5, execute: timeout)
      task.resume()
    }
  }
  func cancel() { queue.sync { finish() } }
  private func finish() {
    let completed = completion
    completion = nil
    deadline?.cancel()
    deadline = nil
    task?.cancel()
    task = nil
    session?.invalidateAndCancel()
    session = nil
    completed?()
  }
  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard task === dataTask, let response = response as? HTTPURLResponse,
      (200...299).contains(response.statusCode), response.expectedContentLength <= 16384
    else {
      completionHandler(.cancel)
      if task === dataTask { finish() }
      return
    }
    completionHandler(.allow)
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard task === dataTask else { return }
    received += data.count
    if received > 16384 { finish() }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if self.task === task { finish() }
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
    if self.task === task { finish() }
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler:
      @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
  }
}
