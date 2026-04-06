# LinkMe Flutter SDK

Cross-platform deep linking, deferred deep linking, and attribution for Flutter apps.

[![pub.dev](https://img.shields.io/pub/v/flutter_linkme_sdk)](https://pub.dev/packages/flutter_linkme_sdk)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

- [Main Site](https://li-nk.me)
- [Setup Guide](https://help.li-nk.me/hc/link-me/en/developer-setup/flutter-setup-guide)
- [SDK Reference](https://help.li-nk.me/hc/link-me/en/sdks/flutter-sdk-reference)
- [Help Center](https://help.li-nk.me/hc/link-me/en)

## Quick start

### 1. Prerequisites

- A LinkMe app configured with your iOS bundle ID and Android package name
- API keys (`appId` and `appKey`) from **App Settings > API Keys**
- Flutter 3.22+

### 2. Install

```bash
flutter pub add flutter_linkme_sdk
```

Or add manually to `pubspec.yaml`:

```yaml
dependencies:
  flutter_linkme_sdk: ^0.2.13
```

### 3. Configure native platforms

**iOS** — In Xcode, enable Associated Domains on the `Runner` target:

```
applinks:links.yourco.com
```

Add a custom URL scheme in `Info.plist` (`CFBundleURLSchemes`): `yourapp`

**Android** — In `android/app/src/main/AndroidManifest.xml`, add intent filters:

```xml
<!-- HTTPS App Links -->
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="links.yourco.com" />
</intent-filter>

<!-- Custom scheme -->
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="yourapp" />
</intent-filter>
```

### 4. Initialize and handle links

```dart
import 'package:flutter/material.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LinkMe.shared.configure(
    const LinkMeConfig(
      appId: String.fromEnvironment('LINKME_APP_ID'),
      appKey: String.fromEnvironment('LINKME_APP_KEY'),
    ),
  );

  // Cold-start link
  final initial = await LinkMe.shared.getInitialLink();

  // Deferred deep link (first install)
  final deferred = initial ?? await LinkMe.shared.claimDeferredIfAvailable();

  runApp(App(initialPayload: initial, deferredPayload: deferred));
}

class App extends StatefulWidget {
  const App({super.key, this.initialPayload, this.deferredPayload});
  final LinkMePayload? initialPayload;
  final LinkMePayload? deferredPayload;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final StreamSubscription<LinkMePayload> _sub;

  @override
  void initState() {
    super.initState();
    // Live links while app is running
    _sub = LinkMe.shared.onLink.listen(routeUser);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: HomeScreen());
  }

  void routeUser(LinkMePayload payload) {
    // Navigate based on payload.path / payload.params
  }
}
```

## Deferred deep linking

| Platform | Primary | Fallback |
| --- | --- | --- |
| iOS | Pasteboard (`cid` token) | Fingerprint (`/api/deferred/claim`) |
| Android | Play Install Referrer (`/api/install-referrer`) | Fingerprint (`/api/deferred/claim`) |

Enable **Pasteboard for Deferred Links** in App Settings for deterministic iOS attribution.

### Forced web redirects

If a payload contains `forceRedirectWeb: true` and a non-empty `webFallbackUrl`, the SDK opens the external browser automatically and does not deliver that payload to `getInitialLink()`, `claimDeferredIfAvailable()`, or `onLink`.

## API reference

| Method | Description |
| --- | --- |
| `configure(config)` | Initialize the SDK |
| `getInitialLink()` | Get the payload that launched the app |
| `onLink` (Stream) | Stream of payloads while the app is running |
| `claimDeferredIfAvailable()` | Claim deferred deep link on first install |
| `track(event, {properties})` | Send analytics events |
| `setUserId(userId)` | Associate a user ID |
| `setAdvertisingConsent(granted)` | Toggle Ad ID inclusion |
| `setReady()` | Signal readiness to process queued links |
| `debugVisitUrl(url, {headers})` | Debug helper for testing link resolution |

### Config options

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `appId` | `String?` | — | App identifier |
| `appKey` | `String?` | — | Optional read-only key |
| `sendDeviceInfo` | `bool` | `true` | Include device metadata |
| `includeVendorId` | `bool` | `true` | Include vendor identifier |
| `includeAdvertisingId` | `bool` | `false` | Include Ad ID (requires consent) |
| `debug` | `bool` | `false` | Enable verbose native logs |

### Instance-based client

```dart
final client = LinkMeClient();
await client.configure(const LinkMeConfig(appId: 'app_123'));
```

Use `LinkMeClient` for dependency injection or test-friendly patterns. It mirrors the `LinkMe` API.

## Example app

The `example/` directory contains a runnable sample:

```bash
cd example
cp .env.example .env  # fill in your keys
flutter run
```

## Troubleshooting

- See the [Android Troubleshooting](https://help.li-nk.me/hc/link-me/en/developer-setup/android-setup-guide) guide for App Links verification issues.
- Enable `debug: true` in `LinkMeConfig` to see native logs for link resolution and deferred claims.

## License

Apache-2.0
