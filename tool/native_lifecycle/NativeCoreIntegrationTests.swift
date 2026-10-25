import Foundation
import LinkMeKit
import XCTest
@testable import NativeLifecycleFixture

final class NativeCoreIntegrationTests: XCTestCase {
  private let core = LinkMe.shared
  private var bridge: NativeLifecycleBridge!
  override func setUp() { core.dispose(); bridge = NativeLifecycleBridge(core: core) }
  override func tearDown() { bridge.detach(); core.dispose(); bridge = nil }
  private func args(_ action: String, _ generation: Int = 1) -> NSDictionary {
    var values: [String: Any] = ["contractVersion": 1, "ownerId": bridge.ownerId,
      "clientGeneration": generation, "action": action]
    if action == "configure" {
      values.merge(["baseUrl": "http://127.0.0.1:9", "appId": "fixture-app", "appKey": "fixture-key",
        "sendDeviceInfo": false, "includeVendorId": false, "requestTimeoutMs": 100]) { _, new in new }
    }
    return values as NSDictionary
  }

  func testActualCoreSelectorsConfigurePublishReadAndDisposeWithoutNetwork() {
    XCTAssertEqual(bridge.version()["contractVersion"] as? Int, 1)
    let event = expectation(description: "scoped core event")
    bridge.listen { frame in
      XCTAssertEqual(frame["ownerId"] as? String, self.bridge.ownerId)
      XCTAssertEqual(frame["clientGeneration"] as? Int, 1)
      XCTAssertEqual((frame["payload"] as? NSDictionary)?["path"] as? String, "/fixture")
      event.fulfill()
    }
    XCTAssertEqual(bridge.control(args("configure"))["ok"] as? Bool, true)
    core._debugEmit(LinkPayload(path: "/fixture"))
    wait(for: [event], timeout: 2)
    let read = expectation(description: "scoped initial core payload")
    bridge.read(args("getInitialLink")) { frame in
      XCTAssertEqual((frame["payload"] as? NSDictionary)?["path"] as? String, "/fixture")
      read.fulfill()
    }
    wait(for: [read], timeout: 2)
    bridge.detach()
    let cleared = expectation(description: "core disposed")
    core.getInitialLink { payload in XCTAssertNil(payload); cleared.fulfill() }
    wait(for: [cleared], timeout: 2)
  }

  func testActualCoreDirectIdentityChangeWithdrawsWrapperOwnership() {
    XCTAssertEqual(bridge.control(args("configure"))["ok"] as? Bool, true)
    core.setUserId("direct-native")
    XCTAssertFalse(bridge.ownsContext())
    let rejected = expectation(description: "old wrapper read rejected")
    bridge.read(args("getInitialLink")) { frame in
      XCTAssertEqual(frame["error"] as? String, "owner_changed")
      XCTAssertNil(frame["payload"])
      rejected.fulfill()
    }
    wait(for: [rejected], timeout: 2)
    bridge.detach()
    // A fresh explicit wrapper generation can regain ownership; detach above
    // leaves the adapter terminal, so it cannot resurrect the singleton.
    XCTAssertEqual(bridge.control(args("configure", 2))["error"] as? String, "detached")
  }
}
