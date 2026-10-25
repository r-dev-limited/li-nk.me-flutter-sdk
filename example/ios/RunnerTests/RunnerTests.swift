import Flutter
import LinkMeKit
import XCTest

@testable import flutter_linkme_sdk

class RunnerTests: XCTestCase {
  func testConfigureAndClearIdentity() {
    let plugin = FlutterLinkmeSdkPlugin()
    let configured = expectation(description: "native SDK configured")
    plugin.handle(FlutterMethodCall(methodName: "configure", arguments: [
      "baseUrl": "http://127.0.0.1:9",
      "sendDeviceInfo": false,
      "includeVendorId": false,
    ])) { result in
      XCTAssertNil(result)
      configured.fulfill()
    }
    let cleared = expectation(description: "identity cleared")
    plugin.handle(FlutterMethodCall(methodName: "setUserId", arguments: ["userId": NSNull()])) { result in
      XCTAssertNil(result)
      cleared.fulfill()
    }
    wait(for: [configured, cleared], timeout: 2)
  }

  func testRejectsInvalidMethodArguments() {
    let plugin = FlutterLinkmeSdkPlugin()
    for method in ["configure", "setUserId", "track", "debugVisitUrl"] {
      let rejected = expectation(description: "\(method) rejects missing arguments")
      plugin.handle(FlutterMethodCall(methodName: method, arguments: nil)) { result in
        XCTAssertEqual((result as? FlutterError)?.code, "invalid_args")
        rejected.fulfill()
      }
      wait(for: [rejected], timeout: 2)
    }
  }

  func testLinkEventsPreserveNativeAttributionFields() {
    let plugin = FlutterLinkmeSdkPlugin()
    let delivered = expectation(description: "native payload delivered to Flutter")
    XCTAssertNil(plugin.onListen(withArguments: nil) { event in
      let payload = event as? [String: Any]
      XCTAssertEqual(payload?["cid"] as? String, "cid-bridge-test")
      XCTAssertEqual(payload?["linkId"] as? String, "link-bridge-test")
      XCTAssertEqual(payload?["duplicate"] as? Bool, true)
      delivered.fulfill()
    })
    LinkMe.shared._debugEmit(LinkPayload(
      linkId: "link-bridge-test", cid: "cid-bridge-test", duplicate: true
    ))
    wait(for: [delivered], timeout: 2)
    XCTAssertNil(plugin.onCancel(withArguments: nil))
  }
}
