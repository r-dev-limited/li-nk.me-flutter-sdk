import Cocoa
import XCTest


@testable import flutter_linkme_sdk

class RunnerTests: XCTestCase {

  func testHandleOpenForwardsNonEmptyBatches() {
    let plugin = FlutterLinkmeSdkPlugin()

    XCTAssertFalse(plugin.handleOpen([]))
    XCTAssertTrue(plugin.handleOpen([URL(string: "myapp://welcome?cid=abc12345")!]))
  }

}
