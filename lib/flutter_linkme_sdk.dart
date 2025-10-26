import 'dart:async';

import 'flutter_linkme_sdk_platform_interface.dart';
import 'src/models.dart';

export 'src/models.dart';

class LinkMe {
  LinkMe({FlutterLinkmeSdkPlatform? platform})
    : _platform = platform ?? FlutterLinkmeSdkPlatform.instance;

  final FlutterLinkmeSdkPlatform _platform;

  Stream<LinkMePayload> get onLink => _platform.onLink;

  Future<void> configure(LinkMeConfig config) {
    return _platform.configure(config);
  }

  Future<LinkMePayload?> getInitialLink() {
    return _platform.getInitialLink();
  }

  Future<LinkMePayload?> claimDeferredIfAvailable() {
    return _platform.claimDeferredIfAvailable();
  }

  Future<void> setUserId(String? userId) {
    return _platform.setUserId(userId);
  }

  Future<void> setAdvertisingConsent(bool granted) {
    return _platform.setAdvertisingConsent(granted);
  }

  Future<void> track(String event, {Map<String, dynamic>? properties}) {
    return _platform.track(event, properties: properties);
  }

  Future<void> setReady() {
    return _platform.setReady();
  }
}

/// Instance-based client for DI/testing, mirroring Node SDK style
class LinkMeClient {
  LinkMeClient({FlutterLinkmeSdkPlatform? platform})
    : _platform = platform ?? FlutterLinkmeSdkPlatform.instance;

  final FlutterLinkmeSdkPlatform _platform;

  Stream<LinkMePayload> get onLink => _platform.onLink;

  Future<void> configure(LinkMeConfig config) {
    return _platform.configure(config);
  }

  Future<LinkMePayload?> getInitialLink() {
    return _platform.getInitialLink();
  }

  Future<LinkMePayload?> claimDeferredIfAvailable() {
    return _platform.claimDeferredIfAvailable();
  }

  Future<void> setUserId(String? userId) {
    return _platform.setUserId(userId);
  }

  Future<void> setAdvertisingConsent(bool granted) {
    return _platform.setAdvertisingConsent(granted);
  }

  Future<void> track(String event, {Map<String, dynamic>? properties}) {
    return _platform.track(event, properties: properties);
  }

  Future<void> setReady() {
    return _platform.setReady();
  }
}
