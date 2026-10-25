@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk_web.dart';
import 'package:flutter_linkme_sdk/src/models.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

const fixture = String.fromEnvironment('LINKME_FIXTURE_URL');
Future<Map<String, dynamic>> state() async =>
    jsonDecode((await http.get(Uri.parse('$fixture/state'))).body)
        as Map<String, dynamic>;
Future<void> waitForAbort(String cid) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!(await state())['aborted'].contains(cid)) {
    if (DateTime.now().isAfter(deadline)) fail('Browser did not abort $cid');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void setLocation(String query) {
  final url = Uri.parse(
    web.window.location.href,
  ).replace(query: query, fragment: '');
  web.window.history.replaceState(web.window.history.state, '', url.toString());
}

void main() {
  late FlutterLinkmeSdkWeb sdk;
  late String original;
  setUp(() async {
    if (fixture.isEmpty) {
      fail('Run node tool/test_web_lifecycle.mjs to provide the owned fixture');
    }
    original = web.window.location.href;
    setLocation('');
    await http.post(Uri.parse('$fixture/state/reset'));
    sdk = FlutterLinkmeSdkWeb();
  });
  tearDown(() async {
    await sdk.dispose();
    web.window.history.replaceState(web.window.history.state, '', original);
  });
  LinkMeConfig config({int timeout = 15000, String app = 'flutter-a'}) =>
      LinkMeConfig(
        baseUrl: fixture,
        appId: app,
        appKey: 'client-key',
        requestTimeoutMs: timeout,
        sendDeviceInfo: false,
      );

  test(
    'real browser CORS resolution strips CID and sends scoped event context',
    () async {
      setLocation('cid=alpha&keep=yes');
      final received = <LinkMePayload>[];
      final sub = sdk.onLink.listen(received.add);
      await sdk.configure(config());
      expect(received.single.path, '/route/alpha');
      expect(web.window.location.search, contains('keep=yes'));
      expect(web.window.location.search, isNot(contains('cid=')));
      await sdk.track('open', properties: {'amount': 4});
      final requests = (await state())['requests'] as List<dynamic>;
      expect(requests[0]['headers']['x-app-id'], 'flutter-a');
      final event = jsonDecode(
        requests.singleWhere(
              (dynamic row) => row['path'] == '/api/app-events',
            )['body']
            as String,
      );
      expect(event['cid'], 'alpha');
      expect(event['linkId'], 'link-alpha');
      await sub.cancel();
    },
  );

  test(
    'default optional browser metadata is serialized through real CORS headers',
    () async {
      setLocation('cid=device');
      await sdk.configure(config().copyWith(sendDeviceInfo: true));
      final requests = (await state())['requests'] as List<dynamic>;
      final device =
          jsonDecode(requests.single['headers']['x-linkme-device'] as String)
              as Map<String, dynamic>;
      expect(device['platform'], 'web');
      expect(device['userAgent'], isNotEmpty);
      expect(device['screen']['width'], greaterThan(0));
      expect((await sdk.getInitialLink())?.cid, 'device');
    },
  );

  test(
    'real browser deadline aborts stalled headers and bodies, then recovers',
    () async {
      for (final cid in ['stalled-headers', 'stalled-body']) {
        setLocation('cid=$cid');
        await sdk.configure(config(timeout: 150));
        await waitForAbort(cid);
      }
      final received = <LinkMePayload>[];
      final sub = sdk.onLink.listen(received.add);
      setLocation('cid=recovered');
      await sdk.configure(config());
      expect(received.single.path, '/route/recovered');
      expect(
        (await state())['aborted'],
        containsAll(['stalled-headers', 'stalled-body']),
      );
      await sub.cancel();
    },
  );

  test(
    'app switch aborts an actual body read and sends no old identity in the new scope',
    () async {
      await sdk.configure(config());
      await sdk.setUserId('old-user');
      setLocation('cid=stalled-body');
      final old = sdk.getInitialLink();
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!((await state())['requests'] as List<dynamic>).any(
        (dynamic row) => row['cid'] == 'stalled-body',
      )) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Old browser request did not start');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      setLocation('');
      await sdk.configure(config(app: 'flutter-b'));
      expect(await old, isNull);
      await waitForAbort('stalled-body');
      await sdk.track('new-event');
      final requests = (await state())['requests'] as List<dynamic>;
      final event = requests.singleWhere(
        (dynamic row) => row['path'] == '/api/app-events',
      );
      expect(event['headers']['x-app-id'], 'flutter-b');
      expect(
        (jsonDecode(event['body'] as String) as Map<String, dynamic>)
            .containsKey('userId'),
        isFalse,
      );
    },
  );

  test(
    'inferred metadata cannot route or navigate despite supplied destination fields',
    () async {
      await sdk.configure(config());
      final before = web.window.location.href;
      final received = <LinkMePayload>[];
      final sub = sdk.onLink.listen(received.add);
      expect(await sdk.claimDeferredIfAvailable(), isNull);
      expect(received, isEmpty);
      expect(web.window.location.href, before);
      await sub.cancel();
    },
  );

  test(
    'dispose detaches browser navigation and reconfigure requires new stream subscribers',
    () async {
      await sdk.configure(config());
      final old = <LinkMePayload>[];
      final sub = sdk.onLink.listen(old.add);
      await sdk.dispose();
      setLocation('cid=after-dispose');
      web.window.dispatchEvent(web.PopStateEvent('popstate'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect((await state())['requests'], isEmpty);
      final fresh = <LinkMePayload>[];
      final next = sdk.onLink.listen(fresh.add);
      await sdk.configure(config());
      expect(old, isEmpty);
      expect(fresh.single.cid, 'after-dispose');
      await sub.cancel();
      await next.cancel();
    },
  );
}
