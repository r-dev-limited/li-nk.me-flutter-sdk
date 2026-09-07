import 'dart:async';

import 'package:flutter/services.dart';

import 'flutter_linkme_sdk_platform_interface.dart';
import 'src/models.dart';

class MethodChannelFlutterLinkmeSdk extends FlutterLinkmeSdkPlatform {
  static const MethodChannel _methodChannel = MethodChannel(
    'flutter_linkme_sdk',
  );
  static const EventChannel _eventChannel = EventChannel(
    'flutter_linkme_sdk/events',
  );

  Stream<LinkMePayload>? _cachedLinkStream;

  @override
  Stream<LinkMePayload> get onLink {
    _cachedLinkStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((dynamic event) => event != null)
        .map<LinkMePayload?>((dynamic event) {
          return LinkMePayload.tryFromJson(event);
        })
        .where((LinkMePayload? payload) => payload != null)
        .cast<LinkMePayload>();
    return _cachedLinkStream!;
  }

  @override
  Future<void> configure(LinkMeConfig config) {
    return _methodChannel.invokeMethod<void>('configure', config.toJson());
  }

  @override
  Future<LinkMePayload?> getInitialLink() async {
    final payload = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getInitialLink',
    );
    return LinkMePayload.tryFromJson(payload);
  }

  @override
  Future<LinkMePayload?> claimDeferredIfAvailable() async {
    final payload = await _methodChannel.invokeMapMethod<String, dynamic>(
      'claimDeferredIfAvailable',
    );
    return LinkMePayload.tryFromJson(payload);
  }

  @override
  Future<void> setUserId(String? userId) {
    return _methodChannel.invokeMethod<void>('setUserId', <String, dynamic>{
      'userId': userId,
    });
  }

  @override
  Future<void> setAdvertisingConsent(bool granted) {
    return _methodChannel.invokeMethod<void>(
      'setAdvertisingConsent',
      <String, dynamic>{'granted': granted},
    );
  }

  @override
  Future<void> track(String event, {Map<String, dynamic>? properties}) {
    final args = <String, dynamic>{'event': event};
    if (properties != null) args['properties'] = properties;
    return _methodChannel.invokeMethod<void>('track', args);
  }

  @override
  Future<void> setReady() {
    return _methodChannel.invokeMethod<void>('setReady');
  }

  @override
  Future<int?> debugVisitUrl(String url, {Map<String, String>? headers}) {
    final args = <String, dynamic>{'url': url};
    if (headers != null && headers.isNotEmpty) {
      args['headers'] = headers;
    }
    return _methodChannel.invokeMethod<int>('debugVisitUrl', args);
  }
}
