# LinkMe Flutter SDK

Flutter plugin for LinkMe — deep linking and attribution.

- **Main Site**: [li-nk.me](https://li-nk.me)
- **Documentation**: [Flutter Setup](https://li-nk.me/resources/developer/setup/flutter)
- **Package**: [pub.dev](https://pub.dev/packages/flutter_linkme_sdk)

## Installation

```bash
flutter pub add flutter_linkme_sdk
```

Or declare it manually:

```yaml
dependencies:
  flutter_linkme_sdk: ^0.2.9
```

## Basic Usage

```dart
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';

final linkme = LinkMe();
await linkme.configure(const LinkMeConfig(
  appId: 'app_123',
  debug: true,
));

final initial = await linkme.getInitialLink();
linkme.onLink.listen((payload) => routeUser(payload));
```

## Manual deep-link setup (equivalent to React Native plugin)

If you are comparing to React Native Expo plugin config:

```json
{
  "hosts": ["links.yourco.com"],
  "associatedDomains": ["links.yourco.com"],
  "schemes": ["yourapp"]
}
```

configure Flutter native targets manually as:

- iOS (`Runner` target):
  - Associated Domains: `applinks:links.yourco.com`
  - `Info.plist` URL types (`CFBundleURLSchemes`): `yourapp`
- Android (`android/app/src/main/AndroidManifest.xml`):
  - HTTPS App Links intent filter using host `links.yourco.com`
  - Custom scheme intent filter using scheme `yourapp`

## API

| Method | Description |
| --- | --- |
| `configure(config)` | Initialize the SDK. |
| `getInitialLink()` | Get the payload that launched the app. |
| `onLink` (Stream) | Stream of payloads while the app is running. |
| `claimDeferredIfAvailable()` | Pasteboard (iOS) / Install Referrer (Android). |
| `track(event, {properties})` | Send analytics events. |
| `setUserId(userId)` | Associate a user ID. |
| `setAdvertisingConsent(granted)` | Toggle Ad ID inclusion. |
| `setReady()` | Signal readiness to process queued links. |
| `debugVisitUrl(url, {headers})` | Debug helper for testing link resolution. |

### Config fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `appId` | `String?` | — | App identifier. |
| `appKey` | `String?` | — | Optional read-only key. |
| `sendDeviceInfo` | `bool` | `true` | Include device metadata. |
| `includeVendorId` | `bool` | `true` | Include vendor identifier. |
| `includeAdvertisingId` | `bool` | `false` | Include Ad ID (after consent). |
| `debug` | `bool` | `false` | Enable verbose native logs. |

### Instance-based client

```dart
final client = LinkMeClient();
await client.configure(const LinkMeConfig(appId: 'app_123'));
```

Use `LinkMeClient` for dependency injection or test-friendly patterns. It mirrors the `LinkMe` API.

## Docs

- Hosted docs: https://li-nk.me/resources/developer/setup/flutter
- Android troubleshooting: See [Android Troubleshooting](https://li-nk.me/resources/developer/setup/android#troubleshooting)

## License

Apache-2.0
