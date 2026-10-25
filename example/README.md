# flutter_linkme_sdk_example

Demonstrates how to use the flutter_linkme_sdk plugin.

Use Flutter 3.47.1 (Dart 3.13+) for this example. The SDK itself continues to
support Flutter 3.44+. The example targets iOS 15+ and macOS 12+, matching
Flutter 3.47. Swift Package Manager is enabled in the example pubspec.

## Deep-link setup in this example

This example includes both HTTPS App Links / Universal Links and a custom scheme:

- Android: `android/app/src/main/AndroidManifest.xml`
  - HTTPS host intent filter (`android:autoVerify="true"`)
  - Custom scheme intent filter
- iOS: `ios/Runner`
  - Associated Domains entitlement (`Runner.entitlements`)
  - URL scheme in `Info.plist` (`CFBundleURLSchemes`)

### Override defaults

Android host + scheme can be overridden at build time:

- `LINKME_APP_LINKS_HOST` (default: `e0qcsxfc.li-nk.me`)
- `LINKME_URL_SCHEME` (default: `me.link.example`)

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
