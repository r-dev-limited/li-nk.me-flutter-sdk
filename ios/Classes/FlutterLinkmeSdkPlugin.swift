import Flutter
import LinkMeKit
import UIKit

public class FlutterLinkmeSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var unsubscribe: (() -> Void)?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "flutter_linkme_sdk", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(
      name: "flutter_linkme_sdk/events", binaryMessenger: registrar.messenger())
    let instance = FlutterLinkmeSdkPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    registrar.addApplicationDelegate(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    unsubscribe?()
    unsubscribe = nil
    eventSink = nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "Invalid arguments", details: nil))
        return
      }
      let baseUrlString = args["baseUrl"] as? String ?? "https://li-nk.me"
      guard let baseUrl = URL(string: baseUrlString) else {
        result(FlutterError(code: "invalid_args", message: "Invalid baseUrl", details: nil))
        return
      }
      // Note: enablePasteboard is now controlled from the Portal (deprecated in SDK config)
      // The native iOS SDK automatically checks pasteboard on claimDeferredIfAvailable
      let config = LinkMe.Config(
        baseUrl: baseUrl,
        appId: args["appId"] as? String,
        appKey: args["appKey"] as? String,
        enablePasteboard: false, // Ignored - pasteboard is now portal-controlled
        sendDeviceInfo: args["sendDeviceInfo"] as? Bool ?? true,
        includeVendorId: args["includeVendorId"] as? Bool ?? true,
        includeAdvertisingId: args["includeAdvertisingId"] as? Bool ?? false,
        debug: args["debug"] as? Bool ?? false
      )
      LinkMe.shared.configure(config: config)
      result(nil)
    case "getInitialLink":
      LinkMe.shared.getInitialLink { payload in
        DispatchQueue.main.async {
          result(self.dictionary(from: payload))
        }
      }
    case "claimDeferredIfAvailable":
      LinkMe.shared.claimDeferredIfAvailable { payload in
        DispatchQueue.main.async {
          result(self.dictionary(from: payload))
        }
      }
    case "setUserId":
      guard let userId = (call.arguments as? [String: Any])?["userId"] as? String else {
        result(FlutterError(code: "invalid_args", message: "userId is required", details: nil))
        return
      }
      LinkMe.shared.setUserId(userId)
      result(nil)
    case "setAdvertisingConsent":
      let granted = (call.arguments as? [String: Any])?["granted"] as? Bool ?? false
      LinkMe.shared.setAdvertisingConsent(granted)
      result(nil)
    case "track":
      guard
        let args = call.arguments as? [String: Any],
        let event = args["event"] as? String,
        !event.isEmpty
      else {
        result(FlutterError(code: "invalid_args", message: "event is required", details: nil))
        return
      }
      let props = args["properties"] as? [String: Any]
      LinkMe.shared.track(event: event, props: props)
      result(nil)
    case "setReady":
      LinkMe.shared.setReady()
      result(nil)
    case "debugVisitUrl":
      guard
        let args = call.arguments as? [String: Any],
        let urlString = args["url"] as? String,
        let url = URL(string: urlString)
      else {
        result(
          FlutterError(code: "invalid_args", message: "url is required", details: nil))
        return
      }
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.timeoutInterval = 5
      request.cachePolicy = .reloadIgnoringLocalCacheData
      if let headers = args["headers"] as? [String: String] {
        headers.forEach { key, value in
          request.setValue(value, forHTTPHeaderField: key)
        }
      }
      let session = URLSession(
        configuration: .default,
        delegate: RedirectBlocker.shared,
        delegateQueue: nil
      )
      session.dataTask(with: request) { _, response, error in
        DispatchQueue.main.async {
          if let error {
            result(
              FlutterError(
                code: "debug_visit_failed", message: error.localizedDescription, details: nil))
            return
          }
          let status = (response as? HTTPURLResponse)?.statusCode ?? -1
          result(status)
        }
      }.resume()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    unsubscribe = LinkMe.shared.addListener { [weak self] payload in
      self?.emit(payload)
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    unsubscribe?()
    unsubscribe = nil
    eventSink = nil
    return nil
  }

  private func emit(_ payload: LinkPayload) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let map = self.dictionary(from: payload) ?? [:]
      self.eventSink?(map)
    }
  }

  private func dictionary(from payload: LinkPayload?) -> [String: Any]? {
    guard let payload else { return nil }
    var dict: [String: Any] = [:]
    if let linkId = payload.linkId { dict["linkId"] = linkId }
    if let path = payload.path { dict["path"] = path }
    if let params = payload.params { dict["params"] = params }
    if let utm = payload.utm { dict["utm"] = utm }
    if let custom = payload.custom { dict["custom"] = custom }
    return dict
  }
}

extension FlutterLinkmeSdkPlugin {
  public func application(
    _ application: UIApplication, continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    LinkMe.shared.handle(userActivity: userActivity)
    return true
  }

  public func application(
    _ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    LinkMe.shared.handle(url: url)
    return true
  }
}

// Prevent following redirects when performing debugVisitUrl so the original
// response code (e.g., 302) is surfaced to the Dart side.
private class RedirectBlocker: NSObject, URLSessionTaskDelegate {
  static let shared = RedirectBlocker()

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
