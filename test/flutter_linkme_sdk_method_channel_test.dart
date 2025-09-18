import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk_method_channel.dart';
import 'package:flutter_linkme_sdk/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelFlutterLinkmeSdk();
  const MethodChannel channel = MethodChannel('flutter_linkme_sdk');

  MethodCall? lastCall;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        lastCall = methodCall;
        switch (methodCall.method) {
          case 'configure':
            return null;
          case 'getInitialLink':
            return <String, dynamic>{'path': '/foo'};
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
}
