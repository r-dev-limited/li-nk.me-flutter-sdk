import Foundation
import XCTest
@testable import NativeLifecycleFixture

final class FixtureCore: NSObject {
  var commands: [NSDictionary] = []
  var reads: [(NSDictionary) -> Void] = []
  var listener: ((NSDictionary) -> Void)?
  var removals = 0
  var rejectOwnership = false
  var overrideReply: NSDictionary?
  @objc func linkmeLifecycleVersion() -> NSNumber { 1 }
  @objc(linkmeLifecycle:) func control(_ args: NSDictionary) -> NSDictionary {
    commands.append(args)
    if let overrideReply { return overrideReply }
    if rejectOwnership { return ["contractVersion": 1, "ownerId": args["ownerId"]!,
      "clientGeneration": args["clientGeneration"]!, "ok": false, "error": "owner_changed"] }
    return ["contractVersion": 1, "ownerId": args["ownerId"]!,
      "clientGeneration": args["clientGeneration"]!, "ok": true]
  }
  @objc(linkmeLifecycleRead:completion:) func read(_ args: NSDictionary, completion: @escaping (NSDictionary) -> Void) {
    reads.append(completion)
  }
  @objc(linkmeLifecycleListen:) func listen(_ callback: @escaping (NSDictionary) -> Void) -> NSString {
    listener = callback
    return "subscription"
  }
  @objc(linkmeLifecycleUnlisten:) func unlisten(_ token: NSString) { removals += 1; listener = nil }
}

final class NativeLifecycleBridgeTests: XCTestCase {
  private var core: FixtureCore!
  private var bridge: NativeLifecycleBridge!
  override func setUp() { core = FixtureCore(); bridge = NativeLifecycleBridge(core: core) }
  override func tearDown() { bridge.detach(); bridge = nil; core = nil }
  private func args(_ action: String, _ generation: Int64 = 1) -> NSDictionary {
    ["contractVersion": 1, "ownerId": bridge.ownerId, "clientGeneration": generation, "action": action]
  }
  private func frame(_ generation: Int64 = 1) -> NSDictionary {
    ["contractVersion": 1, "ownerId": bridge.ownerId, "clientGeneration": generation,
      "ok": true, "payload": ["path": "/ready"]]
  }
  private func flush() {
    let done = expectation(description: "main callback fence")
    DispatchQueue.main.async { done.fulfill() }
    wait(for: [done], timeout: 2)
  }

  func testDiscoveryRejectsOldCoresAndHeadersValidateBeforeMutation() {
    XCTAssertEqual(NativeLifecycleBridge(core: NSObject()).version()["contractVersion"] as? Int, 0)
    XCTAssertEqual(bridge.version()["contractVersion"] as? Int, 1)
    for bad in [["ownerId": "foreign"], ["clientGeneration": true],
      ["clientGeneration": 1.5], ["clientGeneration": Int64(9_007_199_254_740_991)]] as [[String: Any]] {
      let command = args("configure").mutableCopy() as! NSMutableDictionary
      bad.forEach { command[$0.key] = $0.value }
      XCTAssertEqual(bridge.control(command)["error"] as? String, "invalid_args")
    }
    XCTAssertTrue(core.commands.isEmpty)
  }

  func testQueuedReadCannotCrossCancellationAndLateDuplicateCompletesOnce() {
    _ = bridge.control(args("configure"))
    var results: [NSDictionary] = []
    bridge.read(args("getInitialLink")) { results.append($0) }
    core.reads[0](frame())
    _ = bridge.control(args("cancelPendingRequests", 2))
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results[0]["error"] as? String, "owner_changed")
    XCTAssertNil(results[0]["payload"])
    core.reads[0](frame()); core.reads[0](frame()); flush()
    XCTAssertEqual(results.count, 1)
    bridge.read(args("getInitialLink", 2)) { results.append($0) }
    core.reads[1](frame(2)); flush()
    XCTAssertEqual(results.count, 2)
    XCTAssertEqual(results[1]["ok"] as? Bool, true)
  }

  func testListenerChecksGenerationAndRemovedSubscriptionBeforeFinalPublication() {
    var frames: [NSDictionary] = []
    bridge.listen { frames.append($0) }
    _ = bridge.control(args("configure"))
    let old = core.listener!
    old(frame())
    _ = bridge.control(args("cancelPendingRequests", 2)); flush()
    XCTAssertTrue(frames.isEmpty)
    old(frame(2))
    bridge.listen { frames.append($0) }; flush()
    XCTAssertTrue(frames.isEmpty)
    core.listener!(frame(2)); flush()
    XCTAssertEqual(frames.count, 1)
    bridge.stopListening(); bridge.stopListening()
    XCTAssertEqual(core.removals, 2)
  }

  func testDetachDisposesItsOwnerAndSettlesPendingWithoutLatePublication() {
    _ = bridge.control(args("configure"))
    var results: [NSDictionary] = []
    bridge.read(args("getInitialLink")) { results.append($0) }
    bridge.detach(); bridge.detach()
    XCTAssertEqual(core.commands.compactMap { $0["action"] as? String }, ["configure", "dispose"])
    XCTAssertEqual(core.commands.last?["clientGeneration"] as? Int, 2)
    XCTAssertEqual(core.commands.last?["ownerId"] as? String, bridge.ownerId)
    XCTAssertEqual(results.count, 1)
    core.reads[0](frame()); flush()
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(bridge.control(args("configure", 3))["error"] as? String, "detached")
    let inactive = FixtureCore()
    NativeLifecycleBridge(core: inactive).detach()
    XCTAssertTrue(inactive.commands.isEmpty)
  }

  func testPendingReadsAreBoundedAndDisposeAllowsReconfigure() {
    _ = bridge.control(args("configure"))
    var results: [NSDictionary] = []
    for _ in 0..<129 { bridge.read(args("getInitialLink")) { results.append($0) } }
    XCTAssertEqual(core.reads.count, 128)
    XCTAssertEqual(results[0]["error"] as? String, "busy")
    _ = bridge.control(args("dispose", 2))
    XCTAssertEqual(results.count, 129)
    XCTAssertFalse(bridge.isActive)
    _ = bridge.control(args("configure", 3))
    XCTAssertTrue(bridge.isActive)
    bridge.read(args("getInitialLink", 3)) { results.append($0) }
    core.reads.last!(frame(3)); flush()
    XCTAssertEqual(results.last?["ok"] as? Bool, true)
  }

  func testDirectCoreOwnershipChangePreventsHandoffAndPreservesForeignContext() {
    _ = bridge.control(args("configure"))
    XCTAssertTrue(bridge.ownsContext())
    var results: [NSDictionary] = []
    bridge.read(args("getInitialLink")) { results.append($0) }
    core.rejectOwnership = true
    XCTAssertFalse(bridge.ownsContext())
    XCTAssertEqual(results.first?["error"] as? String, "owner_changed")
    bridge.detach()
    XCTAssertFalse(core.commands.contains { $0["action"] as? String == "dispose" })
  }

  func testMalformedCoreAcknowledgementCannotDiscloseForeignPayloadAndReadActionValidates() {
    core.overrideReply = ["contractVersion": 1, "ownerId": "foreign", "clientGeneration": 1,
      "ok": true, "payload": ["path": "/foreign"]]
    let rejected = bridge.control(args("configure"))
    XCTAssertEqual(rejected["error"] as? String, "native_error")
    XCTAssertNil(rejected["payload"])
    XCTAssertEqual(rejected["ownerId"] as? String, bridge.ownerId)
    XCTAssertFalse(bridge.isActive)
    core.overrideReply = nil
    _ = bridge.control(args("configure"))
    var result: NSDictionary?
    bridge.read(args("track")) { result = $0 }
    XCTAssertEqual(result?["error"] as? String, "invalid_args")
    XCTAssertTrue(core.reads.isEmpty)
  }
}
