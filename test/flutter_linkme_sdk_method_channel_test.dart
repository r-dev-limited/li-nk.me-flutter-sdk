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

  setUp(() {
    calls.clear();
    nextInitialIsForceWeb = false;
    nextDeferredIsForceWeb = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        lastCall = methodCall;
        calls.add(methodCall);
        switch (methodCall.method) {
          case 'configure':
            return null;
          case 'getInitialLink':
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
      },
    );
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

  test('getInitialLink opens browser for forceRedirectWeb payload', () async {
    nextInitialIsForceWeb = true;
    final payload = await platform.getInitialLink();
    expect(payload, isNull);

    final openCall = calls.where((c) => c.method == 'openExternalUrl').toList();
    expect(openCall.length, 1);
    expect(openCall.first.arguments, <String, dynamic>{
      'url': 'https://example.com/forced-initial',
    });
  });

  test('claimDeferredIfAvailable opens browser for forceRedirectWeb payload', () async {
    nextDeferredIsForceWeb = true;
    final payload = await platform.claimDeferredIfAvailable();
    expect(payload, isNull);

    final openCall = calls.where((c) => c.method == 'openExternalUrl').toList();
    expect(openCall.length, 1);
    expect(openCall.first.arguments, <String, dynamic>{
      'url': 'https://example.com/forced-deferred',
    });
  });

  test('debugVisitUrl forwards args and returns status', () async {
    final status = await platform.debugVisitUrl(
      'https://example.com/path',
      headers: const {'Host': 'demo.test'},
    );
    expect(status, 302);
    expect(lastCall?.method, 'debugVisitUrl');
    expect(lastCall?.arguments, {
      'url': 'https://example.com/path',
      'headers': {'Host': 'demo.test'}
    });
  });
}
