import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk_method_channel.dart';
import 'package:flutter_linkme_sdk/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelFlutterLinkmeSdk();
  const MethodChannel channel = MethodChannel('flutter_linkme_sdk');

  MethodCall? lastCall;
  final List<MethodCall> calls = <MethodCall>[];
  bool nextInitialIsForceWeb = false;
  bool nextDeferredIsForceWeb = false;
  bool nextInitialIsMalformed = false;

  setUp(() {
    calls.clear();
    nextInitialIsForceWeb = false;
    nextDeferredIsForceWeb = false;
    nextInitialIsMalformed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          lastCall = methodCall;
          calls.add(methodCall);
          switch (methodCall.method) {
            case 'configure':
              return null;
            case 'getInitialLink':
              if (nextInitialIsMalformed) return <String, dynamic>{};
              if (nextInitialIsForceWeb) {
                return <String, dynamic>{
                  'linkId': 'lnk_force_initial',
                  'forceRedirectWeb': true,
                  'webFallbackUrl': 'https://example.com/forced-initial',
                };
              }
              return <String, dynamic>{'path': '/foo'};
            case 'claimDeferredIfAvailable':
              if (nextDeferredIsForceWeb) {
                return <String, dynamic>{
                  'linkId': 'lnk_force_deferred',
                  'forceRedirectWeb': true,
                  'webFallbackUrl': 'https://example.com/forced-deferred',
                };
              }
              return <String, dynamic>{'path': '/bar'};
            case 'openExternalUrl':
              return null;
            case 'debugVisitUrl':
              return 302;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('configure forwards arguments', () async {
    const config = LinkMeConfig(baseUrl: 'https://example.com');
    await platform.configure(config);
    expect(lastCall?.method, 'configure');
    expect(lastCall?.arguments, config.toJson());
  });

  test('getInitialLink parses response', () async {
    final payload = await platform.getInitialLink();
    expect(payload?.path, '/foo');
  });

  test('ignores malformed or empty payloads', () async {
    nextInitialIsMalformed = true;
    final payload = await platform.getInitialLink();
    expect(payload, isNull);
  });

  test('getInitialLink parses the native forced redirect response', () async {
    nextInitialIsForceWeb = true;
    final payload = await platform.getInitialLink();
    expect(payload?.forceRedirectWeb, isTrue);

    final openCall = calls.where((c) => c.method == 'openExternalUrl').toList();
    expect(openCall, isEmpty);
  });

  test(
    'claimDeferredIfAvailable parses the native forced redirect response',
    () async {
      nextDeferredIsForceWeb = true;
      final payload = await platform.claimDeferredIfAvailable();
      expect(payload?.forceRedirectWeb, isTrue);

      final openCall = calls
          .where((c) => c.method == 'openExternalUrl')
          .toList();
      expect(openCall, isEmpty);
    },
  );

  test('debugVisitUrl forwards args and returns status', () async {
    final status = await platform.debugVisitUrl(
      'https://example.com/path',
      headers: const {'Host': 'demo.test'},
    );
    expect(status, 302);
    expect(lastCall?.method, 'debugVisitUrl');
    expect(lastCall?.arguments, {
      'url': 'https://example.com/path',
      'headers': {'Host': 'demo.test'},
    });
  });

  test('track, identity, consent, and readiness forward method calls', () async {
    await platform.track('purchase', properties: {'amount': 12});
    await platform.setUserId(null);
    await platform.setAdvertisingConsent(false);
    await platform.setReady();

    expect(calls.map((call) => call.method), [
      'track',
      'setUserId',
      'setAdvertisingConsent',
      'setReady',
    ]);
    expect(calls[0].arguments, {
      'event': 'purchase',
      'properties': {'amount': 12},
    });
    expect(calls[1].arguments, {'userId': null});
    expect(calls[2].arguments, {'granted': false});
    expect(calls[3].arguments, isNull);
  });

  test('onLink filters null and malformed event payloads', () async {
    const eventChannel = EventChannel('flutter_linkme_sdk/events');
    final events = <dynamic>[
      null,
      <String, dynamic>{},
      <String, dynamic>{'path': '/valid'},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          eventChannel,
          MockStreamHandler.inline(
            onListen: (dynamic _, MockStreamHandlerEventSink sink) async {
              for (final event in events) {
                if (event == null) {
                  sink.success(null);
                } else {
                  sink.success(event);
                }
              }
              sink.endOfStream();
            },
          ),
        );
    final received = <LinkMePayload>[];
    final subscription = platform.onLink.listen(received.add);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(received.map((payload) => payload.path), ['/valid']);
    await subscription.cancel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });
}
