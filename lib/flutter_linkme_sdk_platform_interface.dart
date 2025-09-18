import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_linkme_sdk_method_channel.dart';
import 'src/models.dart';

abstract class FlutterLinkmeSdkPlatform extends PlatformInterface {
  FlutterLinkmeSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterLinkmeSdkPlatform _instance = MethodChannelFlutterLinkmeSdk();

  static FlutterLinkmeSdkPlatform get instance => _instance;

  static set instance(FlutterLinkmeSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<LinkMePayload> get onLink {
    throw UnimplementedError('onLink has not been implemented.');
  }

  Future<void> configure(LinkMeConfig config) {
    throw UnimplementedError('configure() has not been implemented.');
  }

  Future<LinkMePayload?> getInitialLink() {
    throw UnimplementedError('getInitialLink() has not been implemented.');
  }

  Future<LinkMePayload?> claimDeferredIfAvailable() {
    throw UnimplementedError(
      'claimDeferredIfAvailable() has not been implemented.',
    );
  }

  Future<void> setUserId(String? userId) {
    throw UnimplementedError('setUserId() has not been implemented.');
  }

  Future<void> setAdvertisingConsent(bool granted) {
    throw UnimplementedError(
      'setAdvertisingConsent() has not been implemented.',
    );
  }

  Future<void> track(String event, {Map<String, dynamic>? properties}) {
    throw UnimplementedError('track() has not been implemented.');
  }

  Future<void> setReady() {
    throw UnimplementedError('setReady() has not been implemented.');
  }
}
