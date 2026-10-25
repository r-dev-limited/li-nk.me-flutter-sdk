"""Exercise the actual shared Apple adapter without a Flutter engine or device."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--core-path", type=Path, help="Also exercise a local lifecycle-capable LinkMeKit checkout")
options = parser.parse_args()
relative = "flutter_linkme_sdk/Sources/flutter_linkme_sdk/NativeLifecycleBridge.swift"
ios = root / "ios" / relative
macos = root / "macos" / relative
assert ios.read_bytes() == macos.read_bytes(), "Apple lifecycle adapters have drifted"
with tempfile.TemporaryDirectory(prefix="linkme-native-lifecycle-") as directory:
    fixture = Path(directory)
    (fixture / "Sources/NativeLifecycleFixture").mkdir(parents=True)
    (fixture / "Tests/NativeLifecycleFixtureTests").mkdir(parents=True)
    shutil.copy2(ios, fixture / "Sources/NativeLifecycleFixture/NativeLifecycleBridge.swift")
    shutil.copy2(root / "tool/native_lifecycle/NativeLifecycleBridgeTests.swift",
                 fixture / "Tests/NativeLifecycleFixtureTests/NativeLifecycleBridgeTests.swift")
    dependencies = ""
    test_dependencies = '"NativeLifecycleFixture"'
    if options.core_path:
        core_path = options.core_path.resolve(strict=True)
        dependencies = f'.package(name: "LinkMeKit", path: {json.dumps(str(core_path))})'
        test_dependencies += ', .product(name: "LinkMeKit", package: "LinkMeKit")'
        shutil.copy2(root / "tool/native_lifecycle/NativeCoreIntegrationTests.swift",
                     fixture / "Tests/NativeLifecycleFixtureTests/NativeCoreIntegrationTests.swift")
    (fixture / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "NativeLifecycleFixture", platforms: [.macOS(.v10_15)],
  dependencies: [DEPENDENCIES],
  targets: [.target(name: "NativeLifecycleFixture"),
    .testTarget(name: "NativeLifecycleFixtureTests", dependencies: [TEST_DEPENDENCIES])])
'''.replace("TEST_DEPENDENCIES", test_dependencies).replace("DEPENDENCIES", dependencies))
    subprocess.run(["swift", "test", "--package-path", str(fixture)], check=True)
