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
- Flutter 3.44+ (Swift Package Manager is enabled by default)

### 2. Install

```bash
flutter pub add flutter_linkme_sdk
```

Or add manually to `pubspec.yaml`:

```yaml
dependencies:
  flutter_linkme_sdk: ^0.3.4
```

### 3. Configure native platforms

**iOS** — Set the Runner deployment target to iOS 14 or newer, then enable Associated Domains on the `Runner` target:

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

**macOS** — The plugin uses Swift Package Manager and registers Flutter's
`FlutterAppLifecycleDelegate` hook. LinkMeKit 0.2.16 handles custom-scheme URLs
on macOS through `handleOpenURLs(_:)`; keep the generated Flutter SPM
integration enabled for the `macos` target and configure the app's URL Types.

### 4. Initialize and handle links

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';

final linkMe = LinkMe();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await linkMe.configure(
    const LinkMeConfig(
      appId: String.fromEnvironment('LINKME_APP_ID'),
      appKey: String.fromEnvironment('LINKME_APP_KEY'),
    ),
  );

  // Cold-start link
  final initial = await linkMe.getInitialLink();

  // Deferred deep link (first install)
  final deferred = initial ?? await linkMe.claimDeferredIfAvailable();

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
    _sub = linkMe.onLink.listen(routeUser);
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

### Swift Package Manager

Flutter discovers the plugin's Swift packages from `ios/flutter_linkme_sdk/Package.swift` and
`macos/flutter_linkme_sdk/Package.swift`. Flutter 3.44+ generates the `FlutterFramework`
package sibling automatically, and the plugin resolves LinkMeKit 0.2.16 from its repository-root
Swift package. SwiftPM is the recommended integration for `flutter_linkme_sdk` 0.3.4. The bundled
example enables it explicitly in its `pubspec.yaml`, so local global Flutter settings
cannot silently switch the native dependency resolver to CocoaPods.

Projects that intentionally disable SwiftPM can use the plugin's CocoaPods integration once the
LinkMeKit 0.2.16 spec is available on trunk. Until then, CocoaPods users can consume the iOS SDK
0.2.16 directly from its Git tag as documented in the [iOS SDK README](https://github.com/r-dev-limited/li-nk.me-ios-sdk/tree/v0.2.16).

### Forced web redirects

If a payload contains `forceRedirectWeb: true` and a non-empty `webFallbackUrl`, the SDK opens the external browser automatically and does not deliver that payload to `getInitialLink()`, `claimDeferredIfAvailable()`, or `onLink`.

`setUserId(null)` clears identity on Web, React Native, Android 0.2.14, and
LinkMeKit 0.2.16 through the Flutter bridges. Keep those native versions aligned
when relying on Flutter native logout clearing.

## API reference

| Method | Description |
| --- | --- |
| `configure(config)` | Initialize the SDK |
| `getInitialLink()` | Get the payload that launched the app |
| `onLink` (Stream) | Stream of payloads while the app is running |
| `claimDeferredIfAvailable()` | Claim deferred deep link on first install |
| `track(event, {properties})` | Send analytics events |
| `setUserId(userId)` | Associate a user ID; pass `null` to clear it |
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

Flutter 3.44's SwiftPM generator derives a local package identity from the
parent directory name. Because this checkout is nested under `sdks/flutter`,
the repository integration command stages a package-name consumer before
building iOS/macOS:

```bash
cd ../..
IOS_DEVICE="iPhone 17 Pro" npm run test:flutter
```

Published applications use `flutter_linkme_sdk` from pub.dev and do not need
this staging step.

## Troubleshooting

- See the [Android Troubleshooting](https://help.li-nk.me/hc/link-me/en/developer-setup/android-setup-guide) guide for App Links verification issues.
- Enable `debug: true` in `LinkMeConfig` to see native logs for link resolution and deferred claims.

## License

Apache-2.0

## Claim metadata (unreleased)

Updated Edge claims can include `claimId`, `claimMethod`, `matchConfidence`,
`attributionStatus`, `contractVersion`, and `claimPolicyVersion`. These optional
fields are preserved in the payload. Treat `fingerprint_exact` / `inferred` as
heuristic attribution, not a verified install or authenticated identity.
Replaying a CID returns its saved outcome; `duplicate` is a deprecated legacy
projection and must not suppress a new link navigation based on shared IP/UA.

Supply your app ID for deferred matching. New apps have fingerprint fallback
disabled; enable inferred attribution explicitly in app settings if appropriate.
Enabled matching requires a unique exact IP/UA candidate within 30 minutes.
Explicit CID and Play referrer claims use the deterministic 72-hour token window,
subject to link expiry and current app/link/domain policy.

Native metadata forwarding also requires updated native core artifacts; this worktree has not published or selected those releases.


Fingerprint matches return campaign/claim metadata with `navigationAllowed: false`.
They withhold the CID, link ID, path, custom data, query parameters and destination
URLs. The SDK suppresses app-routing callbacks and automatic browser launches for
these responses. Web callers can inspect returned metadata explicitly; native
routing APIs may return no link. A claim receipt is not a redeemable link token.
An independently supplied valid CID/referrer can still authorize navigation with
`navigationAllowed: true`; it retains the original claim receipt and attribution
classification rather than generating another claim.

## Tracking credentials and acceptance (unreleased Edge)

Configure an app ID and a key with `can_ingest` for client telemetry. In Portal,
select **Client analytics and link reading**; it cannot manage links, settings,
or keys, and cannot read private management/visitor diagnostics. A read-only key cannot ingest events. Both event routes require validated
credentials even when link resolution permits optional keys.

The existing `track` API uses the legacy `/api/app-events` route. Its return does
not prove delivery, durable webhook acknowledgement, or a verified conversion.
The SDK currently has no durable telemetry queue and does not promise event-ID
retry semantics. New Edge stores legacy events with app scope; an omitted event
ID receives a server ID, so calling `track` again creates another event. Optional
`userId` is a caller-provided pseudonym, not authenticated identity.

For explicit persistence receipts and safe HTTP retries, `/api/app-events/v1`
accepts a versioned envelope with a stable `eventId`, `occurredAt`, SDK/version,
platform, consent and structured properties. Reuse the same event ID and content
on retry; a successful receipt is 202, changed content is 409. The route requires
`can_ingest`, bounds the body to 32 KiB, and rate-limits by app. Claim events are
server-owned. This SDK has not yet adopted the versioned sender/queue contract.

## Web request lifecycle (unreleased)

Flutter Web accepts `LinkMeConfig(requestTimeoutMs: 15000)`. The complete HTTP
fetch/body operation has a 15-second default deadline; positive integer overrides
up to 2147483647 ms are accepted. Invalid values raise `ArgumentError` before
configuration changes. The default browser client receives an abort signal and
is closed on completion, timeout or cancellation. A late response cannot publish
into a newer app configuration even if an injected transport ignores abort.

`cancelPendingRequests()` invalidates current Web work; later requests and browser
navigation listening remain usable. Reconfigure resets payload, CID cache and user
identity. Changing identity cancels pending results. `dispose()` clears state,
detaches navigation listeners and closes the old routing stream. The client can
be configured again; obtain `onLink` again and subscribe to its new stream.
Default facades share one platform instance, so cancellation/disposal apply to
that instance.

Web routing listeners receive results in subscription order at publication.
Reentrant lifecycle changes stop remaining old delivery, and buffered events in a
paused subscription are checked again before delivery. Listeners survive
reconfigure without automatic replay; `getInitialLink()` reads the current saved
payload explicitly. Forced-web and denied-navigation metadata do not emit an app
route. No automatic retry or durable analytics queue is added, and cancellation
cannot retract a server mutation already accepted.

**Native Dart integration remains open.** The native plugins now expose optional
lifecycle V1 channel methods with engine ownership, generation checks, bounded
pending reads and disposal on detach. The public Dart facade does not yet discover
or call these methods: its native `cancelPendingRequests()` and `dispose()` still
raise `UnsupportedError`, and its deadline field is not forwarded by the legacy
path. Existing published core pins remain unchanged. A source consumer build
establishes compilation, not full native lifecycle support.

On macOS, `python3 tool/test_native_lifecycle.py` exercises the actual shared Apple
adapter through Objective-C fixture selectors and checks iOS/macOS source parity.
Adding `--core-path /path/to/li-nk.me-ios-sdk` exercises a local lifecycle-capable
Swift core without network requests. Android adapter tests and lint run from
`example/android` with `./gradlew :flutter_linkme_sdk:testDebugUnitTest
:flutter_linkme_sdk:lintDebug`. These tests cover the native adapter, not a real
Flutter engine or the public Dart lifecycle state machine.

Run `flutter test --coverage`, `dart run tool/check_lcov.dart` and `flutter analyze`
for VM/analysis gates. `node tool/test_web_lifecycle.mjs` and the same command with
`--wasm` run Chrome against an owned loopback HTTP fixture (Node 18+ and Chrome
required). They verify real aborts, CORS, scope reset, optional metadata headers,
stream disposal and inferred navigation denial in both compilation modes. The
workflow installs Node 24 and runs both browser commands. Full browser-to-Edge /
database/webhook and native wrapper qualification remain separate gates.
