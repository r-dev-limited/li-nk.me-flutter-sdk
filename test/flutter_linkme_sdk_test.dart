import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  bool cancellationCalled = false;
  bool disposalCalled = false;
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
  Future<void> cancelPendingRequests() async {
    cancellationCalled = true;
  }

  @override
  Future<void> dispose() async {
    disposalCalled = true;
    await _events.close();
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
  test('metadata-only attribution retains its navigation prohibition', () {
    final payload = LinkMePayload.tryFromJson({
      'navigationAllowed': false,
      'claimId': 'inferred',
    });
    expect(payload, isNotNull);
    expect(payload!.navigationAllowed, isFalse);
    expect(payload.toJson()['navigationAllowed'], isFalse);
    expect(LinkMePayload.tryFromJson({'navigationAllowed': false}), isNull);
    expect(
      LinkMePayload.tryFromJson({
        'navigationAllowed': 'false',
        'path': '/must-not-route',
      }),
      isNull,
    );
  });

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
    await linkMe.setUserId(null);
    await linkMe.setAdvertisingConsent(true);
    await linkMe.track('open', properties: {'foo': 'bar'});
    await linkMe.setReady();
    await linkMe.cancelPendingRequests();
    await linkMe.debugVisitUrl(
      'https://example.com/hello',
      headers: {'Host': 'demo.test'},
    );

    expect(mockPlatform.configureCalled, isTrue);
    expect(mockPlatform.lastConfig?.baseUrl, config.baseUrl);
    expect(mockPlatform.lastUserId, isNull);
    expect(mockPlatform.lastConsent, isTrue);
    expect(mockPlatform.lastEventName, 'open');
    expect(mockPlatform.lastEventProps, {'foo': 'bar'});
    expect(mockPlatform.setReadyCalled, isTrue);
    expect(mockPlatform.cancellationCalled, isTrue);
    expect(mockPlatform.lastVisitUrl, 'https://example.com/hello');
    expect(mockPlatform.lastVisitHeaders, {'Host': 'demo.test'});
  });

  test(
    'client lifecycle facade delegates and validates before reaching a platform',
    () async {
      final platform = MockFlutterLinkmeSdkPlatform();
      final client = LinkMeClient(platform: platform);
      await client.configure(const LinkMeConfig());
      await client.cancelPendingRequests();
      await client.dispose();
      expect(platform.cancellationCalled, isTrue);
      expect(platform.disposalCalled, isTrue);
      expect(
        () => client.configure(const LinkMeConfig(requestTimeoutMs: 0)),
        throwsArgumentError,
      );
    },
  );

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

  test('Payload parser rejects empty objects and non-string fields', () {
    expect(LinkMePayload.tryFromJson(<String, dynamic>{}), isNull);
    final payload = LinkMePayload.tryFromJson(<String, dynamic>{
      'linkId': 'link_1',
      'path': 42,
      'duplicate': true,
      'params': <String, dynamic>{'ok': 'value', 'count': 3},
    });
    expect(payload?.linkId, 'link_1');
    expect(payload?.path, isNull);
    expect(payload?.duplicate, isTrue);
    expect(payload?.params, {'ok': 'value'});
  });

  test('Payload parser accepts the shared v1 golden fixture', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/link-payload.valid.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final payload = LinkMePayload.tryFromJson(fixture);
    expect(payload?.cid, 'cid-golden-001');
    expect(payload?.linkId, 'link-golden-001');
    expect(payload?.path, '/welcome/春');
    expect(payload?.params?['quote'], 'He said "go"');
    expect(payload?.custom?['control'], 'line\nfeed');
    expect(payload?.duplicate, isFalse);
  });

  test('Claim policy metadata round-trips through native/web payload maps', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/link-payload.claim-policy-v2.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final payload = LinkMePayload.tryFromJson(fixture)!;
    expect(payload.claimId, fixture['claimId']);
    expect(payload.claimMethod, 'direct_cid');
    expect(payload.matchConfidence, 'high');
    expect(payload.attributionStatus, 'deterministic');
    expect(payload.claimPolicyVersion, 2);
    expect(payload.contractVersion, 1);
    expect(
      LinkMePayload.fromJson(payload.toJson()).claimId,
      fixture['claimId'],
    );
  });

  test('Config round-trips defaults and explicit privacy flags', () {
    const config = LinkMeConfig(
      baseUrl: 'https://edge.example',
      appId: 'app-1',
      appKey: 'key-1',
      sendDeviceInfo: false,
      includeVendorId: false,
      includeAdvertisingId: true,
      debug: true,
    );
    final restored = LinkMeConfig.fromJson(config.toJson());
    expect(restored.baseUrl, config.baseUrl);
    expect(restored.appId, config.appId);
    expect(restored.appKey, config.appKey);
    expect(restored.sendDeviceInfo, isFalse);
    expect(restored.includeVendorId, isFalse);
    expect(restored.includeAdvertisingId, isTrue);
    expect(restored.debug, isTrue);
    expect(restored.requestTimeoutMs, 15000);
    expect(config.copyWith(requestTimeoutMs: 25).requestTimeoutMs, 25);
    expect(
      LinkMeConfig.fromJson(
        config.copyWith(requestTimeoutMs: 25).toJson(),
      ).requestTimeoutMs,
      25,
    );
    for (final timeout in [0, -1, 2147483648]) {
      expect(
        () => LinkMeConfig(requestTimeoutMs: timeout).toJson(),
        throwsArgumentError,
      );
    }
  });

  test('Config copyWith changes one field while preserving the rest', () {
    const config = LinkMeConfig(
      baseUrl: 'https://edge.example',
      appId: 'app-1',
      sendDeviceInfo: false,
    );
    final next = config.copyWith(
      baseUrl: 'https://edge-2.example',
      debug: true,
    );
    expect(next.baseUrl, 'https://edge-2.example');
    expect(next.appId, 'app-1');
    expect(next.sendDeviceInfo, isFalse);
    expect(next.debug, isTrue);
  });

  test('Payload serialization omits absent fields and preserves maps', () {
    const payload = LinkMePayload(
      cid: 'cid-1',
      params: <String, String>{'ref': 'golden'},
      forceRedirectWeb: false,
    );
    expect(payload.toJson(), {
      'cid': 'cid-1',
      'params': {'ref': 'golden'},
      'forceRedirectWeb': false,
    });
  });

  test('Payload parser ignores non-string map entries and unknown fields', () {
    final payload = LinkMePayload.fromJson(<String, dynamic>{
      'cid': 'cid-1',
      'params': <dynamic, dynamic>{'ok': 'yes', 3: 'ignored', 'count': 4},
      'unknown': 'ignored',
    });
    expect(payload.cid, 'cid-1');
    expect(payload.params, {'ok': 'yes'});
  });
}
