# Changelog

All notable changes to the LinkMe Flutter SDK.

## 0.3.3

- Align the iOS CocoaPods podspec with the published plugin version.
- Update installation documentation for the 0.3.3 release and LinkMeKit 0.2.15.

## 0.3.2

- Fixes macOS URL delivery by forwarding the imported `handleOpen(_:)` lifecycle callback to LinkMeKit.
- Adds a macOS native regression test for empty and handled URL batches.

## 0.3.1

- Releases the native bridge updates with LinkMeKit 0.2.15 and Android SDK 0.2.14.
- Aligns native forced-web handling so claims open the browser once and are not delivered to app routing.
- Migrates Flutter Web to `package:web` and supports JavaScript and WebAssembly builds.
- Allows `setUserId(null)` to clear event identity and removes duplicate Android deferred-claim networking.
- Adds strict payload parsing for `cid`/`duplicate` fields and rejects empty or non-object native responses.
- Forwards `cid` and `duplicate` from native payloads; reflection keeps the bridge compatible with older published native cores until their next release.
- Cleans up the Android event subscription when the Flutter engine detaches, preventing listener leaks across engine lifecycles.
- Adds a Flutter line-coverage gate (75% minimum) and expands method-channel/config/payload regression tests.

## 0.3.0

- Adds Flutter's standard Swift Package Manager layout for iOS and macOS.
- Adds the required `FlutterFramework` package dependency for Flutter 3.44+.
- Pins the native LinkMeKit dependency to iOS SDK 0.2.14.
- Moves the privacy manifest and native plugin sources into the SwiftPM source targets while retaining CocoaPods support.
- Raises the minimum Flutter version to 3.44.0 and Dart SDK to 3.12.0.

## 0.2.13

- Tightens iOS deferred pasteboard claim parsing to LinkMe hosts/token format only.
- Clears consumed pasteboard CIDs after successful deferred claim.
- Bumps iOS/macOS LinkMeKit dependency to 0.2.13.
- Bumps Android SDK dependency to 0.2.13.

## 0.2.12

- Adds Flutter web support with a first-party LinkMe web implementation.
- Ensures force-web payloads (`forceRedirectWeb=true` + `webFallbackUrl`) open the external browser automatically and are not forwarded to app routing callbacks.
- Bumps iOS/macOS LinkMeKit dependency to 0.2.12.
- Bumps Android SDK dependency to 0.2.12.

## 0.2.8

- Bumps iOS/macOS LinkMeKit dependency to 0.2.8.
- Bumps Android SDK dependency to 0.2.8.

## 0.2.7

- Adds `isLinkMe` and `url` to payloads to distinguish LinkMe-managed links from basic universal links.

## 0.2.5

- Relaxes pasteboard parsing to accept branded LinkMe domains and structured `linkme:cid=...` tokens.

## 0.2.4

- SDK alignment release across all platforms.

## 0.2.3

- Updates Android SDK to 0.2.3.

## 0.2.2

- Updates Android SDK to 0.2.2 (Install Referrer claims use `/api/install-referrer`).

## 0.2.1

- Adds deferred fingerprint testing helpers:
  - A `debug` flag on `LinkMeConfig` lets the native SDK emit extra instrumentation.
  - A new `debugVisitUrl` helper simulates a click to seed fingerprinted claims.

## 0.2.0

- Updated LinkMeKit to 0.2.0 (iOS/macOS) and Android SDK to 0.2.0.

## 0.1.0

- First public release on pub.dev.
- Wraps LinkMeKit 0.1.2 (iOS/macOS) and the Android SDK 0.1.2.
- Supports configure, event listeners, deferred claim, analytics tracking, and consent toggles.

## 0.0.1

- Internal scaffolding.
