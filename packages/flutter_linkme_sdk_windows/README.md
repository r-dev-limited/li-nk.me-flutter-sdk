# LinkMe for Windows

This opt-in Flutter plugin implements LinkMe's existing Dart API for Windows.
Add it alongside the app-facing SDK from pub.dev:

```yaml
dependencies:
  flutter_linkme_sdk: ^0.3.4
  flutter_linkme_sdk_windows: ^0.1.0
```

The Windows package keeps `flutter_linkme_sdk` as a hosted dependency and
supports the published 0.2.13 and 0.3.x APIs. Flutter registers it on Windows
only. Apps that pin the app-facing SDK to a path or Git source must resolve
that same source through a root `dependency_overrides` entry.

## Release verification

The `Verify hosted Flutter consumers` workflow checks a fresh Windows consumer
against the published Windows package and a fresh macOS consumer against the
hosted app-facing SDK. Run it after publishing a package version and before
updating downstream Git dependencies. The Windows runner also needs a real
protocol activation check; the Phoenix DEV walkthrough recorded in PR #2594
covered cold and warm activation, duplicate suppression, an unknown token,
and browser fallback.

The first `0.1.0` upload must be made manually from this directory with
`dart pub publish`; pub.dev only permits automated GitHub Actions publishing
for an existing package. Afterward, configure pub.dev automated publishing for
`r-dev-limited/li-nk.me-flutter-sdk` with the tag pattern
`flutter_linkme_sdk_windows-v{{version}}`. Future releases use matching tags,
such as `flutter_linkme_sdk_windows-v0.1.1`.

## Configure the runner and installer

In `windows/runner/main.cpp`, include
`<flutter_linkme_sdk_windows/flutter_linkme_sdk_windows_plugin_c_api.h>`. At the
start of `wWinMain`, before starting Flutter, call:

```cpp
switch (LinkMeStartWindowsInstance(L"Company.Product.Environment")) {
  case kLinkMeForwarded:
    return EXIT_SUCCESS;
  case kLinkMeActivationFailed:
    return EXIT_FAILURE;
  case kLinkMePrimary:
    break;
}
```

Pass general command-line arguments to Dart only when
`LinkMeHasWindowsProtocolArgument()` is false. Use a stable Windows instance
identity per installed app and environment. Open the app with one URI
argument. Run the browser and app as the same Windows user at the same
elevation. The primary queues up to 32 activations before Dart drains them.
Overlapping launches wait briefly for the receiver; a full queue or unavailable
receiver returns failure to the launching process. Windows controls whether a
browser click brings the running window to the foreground.

Register a dedicated URI scheme in the installer. For a per-user unpackaged
install, set the scheme under `HKCU\Software\Classes`, with an empty
`URL Protocol` string and the default `shell\open\command` set to
`"<absolute executable path>" "%1"`. The installer owns cleanup and upgrades.
For package-identity deployments, declare the protocol in the MSIX manifest.
Use separate schemes for development and production. The SDK does not
register itself or change browser defaults.

[Microsoft protocol activation guide](https://learn.microsoft.com/en-us/windows/apps/develop/launch/handle-uri-activation)

## Initialize and receive links

```dart
final linkMe = LinkMe();
await linkMe.configure(const LinkMeWindowsConfig(
  appId: String.fromEnvironment('LINKME_APP_ID'),
  appKey: String.fromEnvironment('LINKME_CLIENT_KEY'),
  scheme: 'company-product-dev',
));
final subscription = linkMe.onLink.listen(routePayload, onError: reportSafeCode);
await linkMe.setReady();
final initial = await linkMe.getInitialLink();
if (initial != null) routePayload(initial);
```

Import both `flutter_linkme_sdk.dart` and `flutter_linkme_sdk_windows.dart`.
Call `WidgetsFlutterBinding.ensureInitialized()` first. Configure once with an
app ID, read-capable publishable app credential and HTTPS API origin
(default `https://li-nk.me`). Configuration checks the native bridge. The
first activation checks credentials with the server.

`getInitialLink()` returns a cached result for the cold-start activation.
Subsequent activations are delivered in order on `onLink` after `setReady()`
and subscription. Up to 256 successful CIDs are remembered in process,
including the cold-start CID. A repeat for the same CID is suppressed, while
a new click can issue a new CID for the same link. No link is persisted on
disk by the SDK. Clicking the same button again can retry an unsuccessful claim
while the CID is valid.

The only supported activation envelope is
`<configured-scheme>://open?cid=<32 lowercase hex characters>`, with an optional
root slash before the query as used by some Windows browsers. The URI
supplies no navigation path or parameters. The SDK sends the CID in a JSON
body to authenticated `POST /api/deeplink/windows-claim` on the configured
origin, with redirects disabled. It accepts a matching, navigation-enabled
v1 payload from that endpoint. A forced-web payload opens an HTTPS fallback
in the default browser and produces no app payload. Validate application
routes and the signed-in user's access separately.

Failures use `PlatformException.code`, with no URL, credentials, response
body or link payload attached. Log only the code and delivery source. The SDK
does not collect device or advertising identifiers.

## Browser and attribution requirements

The Edge Windows handoff feature must be enabled for the exact HTTPS host,
LinkMe app and link. The Windows browser shows a user-clicked app button and a
web fallback. Browsers can prompt or block the custom protocol. Without an
installed handler, the user can continue in the browser. No broad HTTPS
association is registered. Windows Apps for Websites would require package
identity, a domain association file and separate browser validation.

The claim is direct browser-to-installed-app attribution. No installer,
Store referrer or other durable handoff carries the CID through installation.
`claimDeferredIfAvailable()` fails with
`deferred_attribution_unavailable` and sends no request. Reopening the original
HTTPS link after installation is a fresh direct activation.

This version returns explicit unsupported errors for custom analytics,
setting a non-null user ID, enabling advertising IDs and debug visits.
