import Foundation
import CoreFoundation

// Main-thread adapter. The core owns transport cancellation; this layer owns
// engine attachment, queued channel publication and once-only read results.
final class NativeLifecycleBridge {
  private let core: NSObject?
  let ownerId = UUID().uuidString
  private(set) var isActive = false
  private var attached = true
  private var generation: Int64 = 0
  private var listenerToken: NSString?
  private var listenerEpoch = 0
  private var sink: ((NSDictionary) -> Void)?
  private var reads: [UUID: (NSDictionary, (NSDictionary) -> Void)] = [:]

  init(core: NSObject?) { self.core = core }

  func version() -> NSDictionary {
    let selectors = ["linkmeLifecycleVersion", "linkmeLifecycle:",
      "linkmeLifecycleRead:completion:", "linkmeLifecycleListen:", "linkmeLifecycleUnlisten:"]
    guard attached, let core, selectors.allSatisfy({ core.responds(to: NSSelectorFromString($0)) }),
      let version = core.perform(NSSelectorFromString(selectors[0]))?.takeUnretainedValue() as? NSNumber,
      version.intValue == 1 else { return ["contractVersion": 0] }
    return ["contractVersion": 1, "ownerId": ownerId]
  }

  private func header(_ args: NSDictionary) -> Int64? {
    guard args["ownerId"] as? String == ownerId,
      let version = args["contractVersion"] as? NSNumber,
      CFGetTypeID(version) != CFBooleanGetTypeID(), version.stringValue == "1",
      let number = args["clientGeneration"] as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(), let value = Int64(number.stringValue),
      value >= 0, value < 9_007_199_254_740_991 else { return nil }
    return value
  }

  private func error(_ args: NSDictionary, _ code: String) -> NSDictionary {
    var reply: [String: Any] = ["contractVersion": 1, "ok": false, "error": code]
    if let value = header(args) { reply["ownerId"] = ownerId; reply["clientGeneration"] = value }
    return reply as NSDictionary
  }

  private func valid(_ frame: NSDictionary, generation expected: Int64) -> Bool {
    header(frame) == expected && frame["ok"] as? Bool == true
  }

  func control(_ args: NSDictionary) -> NSDictionary {
    guard attached else { return error(args, "detached") }
    guard version()["contractVersion"] as? Int == 1, let core else { return error(args, "unsupported") }
    guard let requested = header(args), let action = args["action"] as? String else { return error(args, "invalid_args") }
    let reply = core.perform(NSSelectorFromString("linkmeLifecycle:"), with: args)?.takeUnretainedValue() as? NSDictionary
      ?? error(args, "native_error")
    guard header(reply) == requested else { return error(args, "native_error") }
    guard reply["ok"] as? Bool == true else {
      let code = reply["error"] as? String ?? "native_error"
      if code == "owner_changed" || code == "owner_conflict" { isActive = false; settleStaleReads() }
      return error(args, code)
    }
    generation = requested
    if action == "configure" { isActive = true; subscribeIfNeeded() }
    if action == "dispose" { isActive = false; listenerToken = nil; listenerEpoch += 1 }
    settleStaleReads()
    var acknowledgement: [String: Any] = ["contractVersion": 1, "ok": true,
      "ownerId": ownerId, "clientGeneration": requested]
    if reply["duplicate"] as? Bool == true { acknowledgement["duplicate"] = true }
    return acknowledgement as NSDictionary
  }

  func ownsContext() -> Bool {
    guard attached, isActive else { return false }
    let reply = control(["contractVersion": 1, "ownerId": ownerId,
      "clientGeneration": generation, "action": "setReady"])
    if reply["ok"] as? Bool == true { return true }
    isActive = false
    settleStaleReads()
    return false
  }

  func read(_ args: NSDictionary, completion: @escaping (NSDictionary) -> Void) {
    guard attached, isActive, let expected = header(args), expected == generation else {
      completion(error(args, "owner_changed")); return
    }
    guard ["getInitialLink", "claimDeferredIfAvailable"].contains(args["action"] as? String ?? "") else {
      completion(error(args, "invalid_args")); return
    }
    guard reads.count < 128, let core else { completion(error(args, "busy")); return }
    let id = UUID()
    reads[id] = (args, completion)
    let callback: @convention(block) (NSDictionary) -> Void = { [weak self] frame in
      DispatchQueue.main.async { [weak self] in
        guard let self, let pending = self.reads.removeValue(forKey: id) else { return }
        pending.1(self.attached && self.isActive && self.generation == expected && self.valid(frame, generation: expected)
          ? frame : self.error(args, "owner_changed"))
      }
    }
    core.perform(NSSelectorFromString("linkmeLifecycleRead:completion:"), with: args, with: callback)
  }

  func listen(_ sink: @escaping (NSDictionary) -> Void) {
    stopListening()
    self.sink = sink
    subscribeIfNeeded()
  }

  private func subscribeIfNeeded() {
    guard attached, sink != nil, listenerToken == nil,
      version()["contractVersion"] as? Int == 1, let core else { return }
    let epoch = listenerEpoch
    let callback: @convention(block) (NSDictionary) -> Void = { [weak self] frame in
      DispatchQueue.main.async { [weak self] in
        guard let self, self.attached, self.isActive, self.listenerEpoch == epoch,
          self.valid(frame, generation: self.generation) else { return }
        self.sink?(frame)
      }
    }
    listenerToken = core.perform(NSSelectorFromString("linkmeLifecycleListen:"), with: callback)?.takeUnretainedValue() as? NSString
  }

  func stopListening() {
    listenerEpoch += 1
    if let token = listenerToken { core?.perform(NSSelectorFromString("linkmeLifecycleUnlisten:"), with: token) }
    listenerToken = nil
    sink = nil
  }

  private func settleStaleReads() {
    let stale = reads.filter { !attached || !isActive || header($0.value.0) != generation }
    for (id, _) in stale { reads.removeValue(forKey: id) }
    for (_, pending) in stale { pending.1(error(pending.0, "owner_changed")) }
  }

  func detach() {
    guard attached else { return }
    attached = false
    if isActive {
      let args: NSDictionary = ["contractVersion": 1, "ownerId": ownerId,
        "clientGeneration": generation + 1, "action": "dispose"]
      core?.perform(NSSelectorFromString("linkmeLifecycle:"), with: args)
    }
    isActive = false
    stopListening()
    settleStaleReads()
  }
}
