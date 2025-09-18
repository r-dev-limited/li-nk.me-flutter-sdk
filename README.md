# flutter_linkme_sdk

Flutter bindings for the LinkMe mobile deep link SDK. The plugin embeds the
native Android (`LinkMe.kt`) and iOS (`LinkMeKit.swift`) implementations and
exposes a single Dart API that mirrors the platform capabilities.

## Features
- Configure the SDK with your LinkMe environment (base URL, app credentials).
- Fetch the initial deep link payload that launched the app.
- Listen for subsequent links while the app is running.
- Claim deferred deep links (Install Referrer on Android, probabilistic on iOS).
- Update advertising consent and optional analytics tracking information.

## Usage
```dart
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';

final linkMe = LinkMe();

Future<void> bootstrap() async {
  await linkMe.configure(
    const LinkMeConfig(
      baseUrl: 'https://li-nk.me',
      appId: 'demo-app',
      appKey: 'LKDEMO-0001-TESTKEY',
      includeAdvertisingId: false,
    ),
  );

  final initial = await linkMe.getInitialLink();
  if (initial != null) {
    routeFromPayload(initial);
  }

  linkMe.onLink.listen(routeFromPayload);
}

Future<void> onConsentAccepted() async {
  await linkMe.setAdvertisingConsent(true);
  await linkMe.setReady();
}
```

## Android integration
- Add HTTPS App Links/custom scheme intent filters to your launcher activity.
- No additional Activity wiring is required; the plugin forwards
  `onCreate`/`onNewIntent` intents to the native SDK automatically.

## iOS integration
- Declare the appropriate Associated Domains and URL schemes in Xcode.
- The plugin forwards `application(_:continue:)` and
  `application(_:open:options:)` to the native LinkMe SDK.
- Call `setReady()` once your consent state is finalised to resume link
  resolution.

## Deferred deep linking
```dart
final deferred = await linkMe.claimDeferredIfAvailable();
if (deferred != null) {
  routeFromPayload(deferred);
}
```

## Analytics
```dart
await linkMe.setUserId(userId);
await linkMe.track('open', properties: {'screen': 'home'});
```

See the repository root `docs/help/docs/setup` for platform-specific setup
notes covering Associated Domains, App Links and consent disclosures.
