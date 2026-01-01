## 0.2.7

* Adds `isLinkMe` and `url` to payloads to distinguish LinkMe-managed links from basic universal links.

## 0.2.1

* Adds deferred fingerprint testing helpers:
  * A `debug` flag on `LinkMeConfig` lets the native SDK emit extra instrumentation.
  * A new `debugVisitUrl` helper simulates a click to seed fingerprinted claims.

## 0.2.4

* Updates iOS SDK, React Native SDK, and Android SDK to `0.2.4`.

## 0.2.5

* Relaxes pasteboard parsing to accept branded LinkMe domains and structured `linkme:cid=...` tokens.

## 0.2.2

* Updates Android SDK to `0.2.2` (Install Referrer claims use `/api/install-referrer`).

## 0.2.3

* Updates Android SDK to `0.2.3`.

## 0.2.0

* Updated LinkMeKit to `0.2.0` (iOS/macOS) and Android SDK to `0.2.0`.

## 0.1.0

* First public release on pub.dev.
* Wraps LinkMeKit `0.1.2` (iOS/macOS) and the Android SDK `0.1.2`.
* Supports configure, event listeners, deferred claim, analytics tracking, and consent toggles.

## 0.0.1

* Internal scaffolding.
