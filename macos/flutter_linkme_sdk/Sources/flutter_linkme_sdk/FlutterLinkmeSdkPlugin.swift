import Cocoa
import FlutterMacOS
import LinkMeKit

public class FlutterLinkmeSdkPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var unsubscribe: (() -> Void)?
  private var handledForcedTargets = Set<String>()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "flutter_linkme_sdk", binaryMessenger: registrar.messenger)
    let eventChannel = FlutterEventChannel(
      name: "flutter_linkme_sdk/events", binaryMessenger: registrar.messenger)
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
      let config = LinkMe.Config(
        baseUrl: baseUrl,
        appId: args["appId"] as? String,
        appKey: args["appKey"] as? String,
        enablePasteboard: args["enablePasteboard"] as? Bool ?? false,
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
          if let payload, self.handleForcedWebRedirect(payload) {
            result(nil)
          } else {
            result(self.dictionary(from: payload))
          }
        }
      }
    case "claimDeferredIfAvailable":
      LinkMe.shared.claimDeferredIfAvailable { payload in
        DispatchQueue.main.async {
          if let payload, self.handleForcedWebRedirect(payload) {
            result(nil)
          } else {
            result(self.dictionary(from: payload))
          }
        }
      }
    case "setUserId":
      guard let args = call.arguments as? [String: Any], args.keys.contains("userId") else {
        result(FlutterError(code: "invalid_args", message: "userId is required (or null to clear)", details: nil))
        return
      }
      let userId = args["userId"] as? String
      if let userId = args["userId"] as? String,
         userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result(FlutterError(code: "invalid_args", message: "userId must not be blank", details: nil))
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
      if let headers = args["headers"] as? [String: String] {
        headers.forEach { key, value in
          request.setValue(value, forHTTPHeaderField: key)
        }
      }
      URLSession.shared.dataTask(with: request) { _, response, error in
        if let error {
          result(
            FlutterError(
              code: "debug_visit_failed", message: error.localizedDescription, details: nil))
          return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        result(status)
      }.resume()
    case "openExternalUrl":
      guard
        let args = call.arguments as? [String: Any],
        let raw = args["url"] as? String,
        !raw.isEmpty,
        let url = URL(string: raw)
      else {
        result(
          FlutterError(code: "invalid_args", message: "url is required", details: nil))
        return
      }
      let success = NSWorkspace.shared.open(url)
      if success {
        result(nil)
      } else {
        result(
          FlutterError(
            code: "open_url_failed",
            message: "Unable to open external URL",
            details: raw
          ))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    unsubscribe?()
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

  /// Receives URL opens forwarded by Flutter's macOS application delegate.
  /// Swift imports the `handleOpenURLs:` Objective-C selector as `handleOpen(_:)`.
  public func handleOpen(_ urls: [URL]) -> Bool {
    guard !urls.isEmpty else { return false }
    urls.forEach { LinkMe.shared.handle(url: $0) }
    return true
  }

  private func emit(_ payload: LinkPayload) {
    if handleForcedWebRedirect(payload) { return }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let map = self.dictionary(from: payload) ?? [:]
      self.eventSink?(map)
    }
  }

  private func dictionary(from payload: LinkPayload?) -> [String: Any]? {
    guard let payload else { return nil }
    var dict: [String: Any] = [:]
    // Read optional attribution fields reflectively so the bridge remains
    // source/binary compatible across native artifact versions.
    if let cid: String = payload.optionalField("cid") { dict["cid"] = cid }
    if let linkId = payload.linkId { dict["linkId"] = linkId }
    if let path = payload.path { dict["path"] = path }
    if let params = payload.params { dict["params"] = params }
    if let utm = payload.utm { dict["utm"] = utm }
    if let custom = payload.custom { dict["custom"] = custom }
    if let url = payload.url { dict["url"] = url }
    if let isLinkMe = payload.isLinkMe { dict["isLinkMe"] = isLinkMe }
    if let duplicate: Bool = payload.optionalField("duplicate") { dict["duplicate"] = duplicate }
    if let forceRedirectWeb = payload.forceRedirectWeb { dict["forceRedirectWeb"] = forceRedirectWeb }
    if let webFallbackUrl = payload.webFallbackUrl { dict["webFallbackUrl"] = webFallbackUrl }
    return dict
  }

  private func handleForcedWebRedirect(_ payload: LinkPayload) -> Bool {
    guard payload.forceRedirectWeb == true,
          let target = payload.webFallbackUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
          !target.isEmpty,
          let url = URL(string: target) else { return false }
    if handledForcedTargets.contains(target) { return true }
    let opened = NSWorkspace.shared.open(url)
    if opened { handledForcedTargets.insert(target) }
    return opened
  }
}

private extension LinkPayload {
  func optionalField<T>(_ name: String) -> T? {
    Mirror(reflecting: self).children.first(where: { $0.label == name })?.value as? T
  }
}
