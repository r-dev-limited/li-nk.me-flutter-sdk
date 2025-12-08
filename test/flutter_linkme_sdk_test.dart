import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk_platform_interface.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterLinkmeSdkPlatform
    with MockPlatformInterfaceMixin
    implements FlutterLinkmeSdkPlatform {
  final StreamController<LinkMePayload> _events =
      StreamController<LinkMePayload>.broadcast();

  bool configureCalled = false;
  bool setReadyCalled = false;
  LinkMeConfig? lastConfig;
  LinkMePayload? initialPayload;
  LinkMePayload? deferredPayload;
  String? lastEventName;
  Map<String, dynamic>? lastEventProps;
  String? lastUserId;
  bool? lastConsent;
  String? lastVisitUrl;
  Map<String, String>? lastVisitHeaders;
  int debugVisitResponse = 204;

  @override
  Stream<LinkMePayload> get onLink => _events.stream;

  @override
  Future<void> configure(LinkMeConfig config) async {
    configureCalled = true;
    lastConfig = config;
  }

  @override
  Future<LinkMePayload?> getInitialLink() async => initialPayload;

  @override
  Future<LinkMePayload?> claimDeferredIfAvailable() async => deferredPayload;

  @override
  Future<void> setUserId(String? userId) async {
    lastUserId = userId;
  }

  @override
  Future<void> setAdvertisingConsent(bool granted) async {
    lastConsent = granted;
  }

  @override
  Future<void> track(String event, {Map<String, dynamic>? properties}) async {
    lastEventName = event;
    lastEventProps = properties;
  }

  @override
  Future<void> setReady() async {
    setReadyCalled = true;
  }

  @override
  Future<int?> debugVisitUrl(String url, {Map<String, String>? headers}) async {
    lastVisitUrl = url;
    lastVisitHeaders = headers;
    return debugVisitResponse;
  }

  void emit(LinkMePayload payload) {
    _events.add(payload);
  }
}

void main() {
  final FlutterLinkmeSdkPlatform initialPlatform =
      FlutterLinkmeSdkPlatform.instance;

  tearDown(() {
    FlutterLinkmeSdkPlatform.instance = initialPlatform;
  });

  test('$MethodChannelFlutterLinkmeSdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterLinkmeSdk>());
  });

  test('LinkMe delegates to platform', () async {
    final mockPlatform = MockFlutterLinkmeSdkPlatform();
    FlutterLinkmeSdkPlatform.instance = mockPlatform;
    final linkMe = LinkMe();
    const config = LinkMeConfig(baseUrl: 'https://example.com');

    await linkMe.configure(config);
    await linkMe.setUserId('user-123');
    await linkMe.setAdvertisingConsent(true);
    await linkMe.track('open', properties: {'foo': 'bar'});
    await linkMe.setReady();
    await linkMe.debugVisitUrl('https://example.com/hello', headers: {'Host': 'demo.test'});

    expect(mockPlatform.configureCalled, isTrue);
    expect(mockPlatform.lastConfig?.baseUrl, config.baseUrl);
    expect(mockPlatform.lastUserId, 'user-123');
    expect(mockPlatform.lastConsent, isTrue);
    expect(mockPlatform.lastEventName, 'open');
    expect(mockPlatform.lastEventProps, {'foo': 'bar'});
    expect(mockPlatform.setReadyCalled, isTrue);
    expect(mockPlatform.lastVisitUrl, 'https://example.com/hello');
    expect(mockPlatform.lastVisitHeaders, {'Host': 'demo.test'});
  });

  test('Streams payloads', () async {
    final mockPlatform = MockFlutterLinkmeSdkPlatform();
    FlutterLinkmeSdkPlatform.instance = mockPlatform;
    final linkMe = LinkMe();

    final payload = LinkMePayload(path: '/home');
    final events = <LinkMePayload>[];
    final sub = linkMe.onLink.listen(events.add);
    mockPlatform.emit(payload);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(events, [payload]);
    await sub.cancel();
  });
}
