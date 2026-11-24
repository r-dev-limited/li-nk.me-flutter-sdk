import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';
import 'package:flutter_linkme_sdk_windows/flutter_linkme_sdk_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('me.link/flutter_linkme_sdk_windows');
  final messenger = binding.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  test(
    'browser root slash preserves the token without accepting a route',
    () async {
      const cid = '0123456789abcdef0123456789abcdef';
      const config = LinkMeWindowsConfig(
        baseUrl: 'https://api.example.test',
        appId: 'fixture-app',
        appKey: 'fixture-client',
        scheme: 'staff-fixture',
      );
      var claims = 0;

      Future<LinkMePayload?> open(String activation) => http.runWithClient(
        () async {
          messenger.setMockMethodCallHandler(channel, (call) async {
            return switch (call.method) {
              'isAvailable' => true,
              'getInitialUri' => activation,
              _ => throw MissingPluginException(),
            };
          });
          final linkMe = LinkMe(platform: FlutterLinkmeSdkWindows());
          await linkMe.configure(config);
          return linkMe.getInitialLink();
        },
        () => MockClient((request) async {
          claims++;
          expect(
            request.url.toString(),
            'https://api.example.test/api/deeplink/windows-claim',
          );
          expect(jsonDecode(request.body), {'cid': cid});
          return http.Response(
            jsonEncode({
              'contractVersion': 1,
              'navigationAllowed': true,
              'cid': cid,
              'linkId': 'fixture-link',
              'path': '/staff',
              'forceRedirectWeb': false,
            }),
            200,
          );
        }),
      );

      expect((await open('staff-fixture://open/?cid=$cid'))?.path, '/staff');
      await expectLater(
        open('staff-fixture://open/?cid=$cid&path=/injected'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'invalid_activation',
          ),
        ),
      );
      expect(claims, 1);
    },
  );
}
