import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_linkme_sdk/src/models.dart';
import 'package:flutter_linkme_sdk/src/web_controller.dart';
import 'package:flutter_linkme_sdk/src/request_scope.dart';

class Environment implements LinkMeWebEnvironment {
  String href = 'https://page.example/';
  final changes = StreamController<void>.broadcast(sync: true);
  final opened = <String>[];
  final replaced = <String>[];
  int deviceReads = 0;
  bool blockOpen = false;
  @override
  String get currentHref => href;
  @override
  Uri get baseUri => Uri.parse(href);
  @override
  Stream<void> get locationChanges => changes.stream;
  @override
  void replaceUrl(String url) {
    replaced.add(url);
    href = url;
  }

  @override
  void openExternalUrl(String url) {
    if (blockOpen) throw StateError('Blocked');
    opened.add(url);
  }

  @override
  Map<String, dynamic> buildDevicePayload() {
    deviceReads += 1;
    return {'platform': 'web', 'locale': 'en-NZ'};
  }
}

class Client extends http.BaseClient {
  Client(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  final requests = <http.BaseRequest>[];
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond(request);
  }

  @override
  void close() {
    closed = true;
  }
}

http.StreamedResponse response(Object value, {int status = 200}) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), status);

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late Environment environment;
  late List<Client> clients;
  late LinkMeWebController controller;
  late Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  const config = LinkMeConfig(
    baseUrl: 'https://edge.example',
    appId: 'app-a',
    appKey: 'key-a',
    sendDeviceInfo: false,
  );
  setUp(() {
    environment = Environment();
    clients = [];
    handler = (_) async => response({
      'path': '/ready',
      'cid': 'cid-ready',
      'linkId': 'link-ready',
    });
    controller = LinkMeWebController(
      environment: environment,
      clientFactory: () {
        final client = Client((request) => handler(request));
        clients.add(client);
        return client;
      },
    );
  });
  tearDown(() async {
    await controller.dispose();
    await environment.changes.close();
  });

  test(
    'unconfigured or disposed calls cannot issue HTTP or collect optional metadata',
    () async {
      expect(await controller.getInitialLink(), isNull);
      expect(await controller.claimDeferredIfAvailable(), isNull);
      expect(await controller.debugVisitUrl('https://debug.example'), isNull);
      await controller.track('open');
      expect(clients, isEmpty);
      expect(environment.deviceReads, 0);
      await controller.configure(config);
      await controller.dispose();
      expect(await controller.getInitialLink(), isNull);
    },
  );

  test(
    'query/hash CID extraction, replay and configured scope preserve the legacy contract',
    () async {
      environment.href = 'https://page.example/welcome?cid=query-id&keep=yes';
      final received = <LinkMePayload>[];
      final subscription = controller.onLink.listen(received.add);
      await controller.configure(config);
      expect(
        clients.single.requests.single.url.queryParameters['cid'],
        'query-id',
      );
      expect(clients.single.requests.single.headers['x-app-id'], 'app-a');
      expect(environment.href, contains('keep=yes'));
      expect(environment.href, isNot(contains('cid=')));
      expect(received.single.isLinkMe, isTrue);
      expect((await controller.getInitialLink())?.path, '/ready');
      expect(clients.length, 1);
      expect(clients.single.closed, isTrue);
      environment.href = 'https://page.example/#/profile?cid=hash-id&tab=one';
      environment.changes.add(null);
      await flush();
      expect(
        clients.last.requests.single.url.queryParameters['cid'],
        'hash-id',
      );
      expect(environment.href, contains('tab=one'));
      environment.href = 'https://page.example/#cid=plain-id&keep=yes';
      environment.changes.add(null);
      await flush();
      expect(
        clients.last.requests.single.url.queryParameters['cid'],
        'plain-id',
      );
      expect(environment.href, contains('keep=yes'));
      environment.href = 'https://page.example/?cid=hash-id';
      environment.changes.add(null);
      await flush();
      expect(clients.length, 3);
      await subscription.cancel();
    },
  );

  test(
    'same-origin URL resolution and unknown-domain fallback retain campaign data',
    () async {
      environment.href =
          'https://edge.example/welcome/%E6%98%A5?utm_source=mail&ref=one';
      handler = (_) async =>
          response({'error': 'domain_not_found'}, status: 404);
      await controller.configure(config);
      final payload = await controller.getInitialLink();
      expect(payload?.path, '/welcome/%E6%98%A5');
      expect(payload?.isLinkMe, isFalse);
      expect(payload?.utm, {'utm_source': 'mail'});
      expect(payload?.params, {'ref': 'one'});
      expect(
        clients.single.requests.single.url.path,
        '/api/deeplink/resolve-url',
      );
      final request = clients.single.requests.single as http.Request;
      expect(jsonDecode(request.body)['url'], environment.href);
    },
  );

  test(
    'no-match, malformed JSON/payloads and HTTP/network errors return no link',
    () async {
      await controller.configure(config);
      for (final make
          in <Future<http.StreamedResponse> Function(http.BaseRequest)>[
            (_) async => response({}, status: 404),
            (_) async => response([]),
            (_) async => response({'unknown': true}),
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('invalid-json')),
              200,
            ),
            (_) async => throw StateError('offline'),
          ]) {
        handler = make;
        expect(await controller.claimDeferredIfAvailable(), isNull);
      }
      expect(clients.every((client) => client.closed), isTrue);
    },
  );

  test(
    'total deadline bounds headers and body reads even when transport ignores abort',
    () async {
      await controller.configure(config.copyWith(requestTimeoutMs: 25));
      handler = (_) => Completer<http.StreamedResponse>().future;
      expect(await controller.claimDeferredIfAvailable(), isNull);
      expect(clients.last.closed, isTrue);
      var aborted = false;
      final stream = StreamController<List<int>>();
      handler = (request) async {
        (request as http.Abortable).abortTrigger!.then((_) {
          aborted = true;
        });
        return http.StreamedResponse(stream.stream, 200);
      };
      expect(await controller.claimDeferredIfAvailable(), isNull);
      await flush();
      expect(aborted, isTrue);
      expect(clients.last.closed, isTrue);
      stream.add(utf8.encode('{"path":"/late"}'));
      await stream.close();
      expect(await controller.getInitialLink(), isNull);
    },
  );

  test(
    'reconfigure/identity/dispose/cancel settle stale responses without navigation',
    () async {
      for (final change in ['configure', 'identity', 'dispose', 'cancel']) {
        await controller.configure(config);
        final started = Completer<void>();
        final release = Completer<http.StreamedResponse>();
        handler = (_) {
          started.complete();
          return release.future;
        };
        final received = <LinkMePayload>[];
        final sub = controller.onLink.listen(received.add);
        final pending = controller.claimDeferredIfAvailable();
        await started.future;
        switch (change) {
          case 'configure':
            await controller.configure(config.copyWith(appId: 'app-b'));
          case 'identity':
            await controller.setUserId('new-user');
          case 'dispose':
            await controller.dispose();
          case 'cancel':
            await controller.cancelPendingRequests();
        }
        expect(await pending, isNull);
        expect(clients.last.closed, isTrue);
        release.complete(
          response({
            'path': '/old',
            'forceRedirectWeb': true,
            'webFallbackUrl': 'https://must-not-open.example',
          }),
        );
        await flush();
        expect(received, isEmpty);
        expect(environment.opened, isEmpty);
        await sub.cancel();
      }
    },
  );

  test(
    'old initial-link completion cannot overwrite the new app payload',
    () async {
      await controller.configure(config);
      final started = Completer<void>();
      final old = Completer<http.StreamedResponse>();
      handler = (_) {
        started.complete();
        return old.future;
      };
      environment.href = 'https://page.example/?cid=old';
      final pending = controller.getInitialLink();
      await started.future;
      environment.href = 'https://page.example/';
      await controller.configure(config.copyWith(appId: 'app-b'));
      handler = (_) async => response({'path': '/new', 'cid': 'new'});
      environment.href = 'https://page.example/?cid=new';
      expect((await controller.getInitialLink())?.path, '/new');
      old.complete(response({'path': '/old'}));
      expect(await pending, isNull);
      expect((await controller.getInitialLink())?.path, '/new');
    },
  );

  test(
    'app switch clears identity and drops unsent analytics before HTTP starts',
    () async {
      await controller.configure(config);
      await controller.setUserId('old-user');
      final pending = controller.track('old-event');
      await controller.configure(
        config.copyWith(appId: 'app-b', appKey: 'key-b'),
      );
      await pending;
      expect(clients, isEmpty);
      await controller.track('new-event', properties: {'amount': 4});
      final request = clients.single.requests.single as http.Request;
      expect(request.headers['x-app-id'], 'app-b');
      expect(request.headers['x-api-key'], 'key-b');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['type'], 'new-event');
      expect(body['detail'], '{"amount":4}');
      expect(body.containsKey('userId'), isFalse);
      expect(body.containsKey('cid'), isFalse);
      await controller.setUserId('new-user');
      await controller.track('identified');
      expect(
        jsonDecode(
          (clients.last.requests.single as http.Request).body,
        )['userId'],
        'new-user',
      );
      await controller.setUserId(null);
      await controller.track('anonymous');
      expect(
        jsonDecode(
          (clients.last.requests.single as http.Request).body,
        ).containsKey('userId'),
        isFalse,
      );
    },
  );

  test(
    'reentrant lifecycle changes stop later stream subscribers and the old return payload',
    () async {
      for (final change in ['configure', 'identity', 'dispose', 'cancel']) {
        await controller.configure(config);
        var first = 0;
        var later = 0;
        final one = controller.onLink.listen((_) {
          first += 1;
          switch (change) {
            case 'configure':
              unawaited(controller.configure(config.copyWith(appId: 'app-b')));
            case 'identity':
              unawaited(controller.setUserId('new-user'));
            case 'dispose':
              unawaited(controller.dispose());
            case 'cancel':
              unawaited(controller.cancelPendingRequests());
          }
        });
        final two = controller.onLink.listen((_) {
          later += 1;
        });
        expect(await controller.claimDeferredIfAvailable(), isNull);
        expect(first, 1);
        expect(later, 0);
        await one.cancel();
        await two.cancel();
      }
    },
  );

  test(
    'cancel and identity changes preserve navigation listening; dispose detaches it',
    () async {
      await controller.configure(config);
      await controller.cancelPendingRequests();
      await controller.setUserId('user');
      final received = <LinkMePayload>[];
      final sub = controller.onLink.listen(received.add);
      environment.href = 'https://page.example/?cid=after-cancel';
      environment.changes.add(null);
      await flush();
      expect(received.length, 1);
      await controller.dispose();
      environment.href = 'https://page.example/?cid=after-dispose';
      environment.changes.add(null);
      await flush();
      expect(clients.length, 1);
      await sub.cancel();
      await controller.configure(config);
      expect(clients.length, 2);
    },
  );

  test(
    'forced web and inferred metadata cannot become routing callbacks',
    () async {
      await controller.configure(config);
      final received = <LinkMePayload>[];
      final sub = controller.onLink.listen(received.add);
      handler = (_) async => response({
        'forceRedirectWeb': true,
        'webFallbackUrl': 'https://browser.example/landing',
      });
      expect(await controller.claimDeferredIfAvailable(), isNull);
      expect(environment.opened, ['https://browser.example/landing']);
      expect(received, isEmpty);
      handler = (_) async => response({
        'navigationAllowed': false,
        'claimId': 'inferred',
        'path': '/private',
        'forceRedirectWeb': true,
        'webFallbackUrl': 'https://must-not-open.example',
      });
      expect(await controller.claimDeferredIfAvailable(), isNull);
      expect(environment.opened.length, 1);
      expect(received, isEmpty);
      environment.blockOpen = true;
      handler = (_) async => response({
        'forceRedirectWeb': true,
        'webFallbackUrl': 'https://blocked.example',
      });
      expect(
        (await controller.claimDeferredIfAvailable())?.forceRedirectWeb,
        isTrue,
      );
      await sub.cancel();
    },
  );

  test(
    'optional device collection respects flag and debug visits are bounded and do not follow redirects',
    () async {
      await controller.configure(config.copyWith(sendDeviceInfo: true));
      await controller.claimDeferredIfAvailable();
      final request = clients.single.requests.single as http.Request;
      expect(jsonDecode(request.body)['device']['platform'], 'web');
      expect(environment.deviceReads, 1);
      handler = (_) async => response({}, status: 302);
      expect(
        await controller.debugVisitUrl(
          'https://debug.example/visit',
          headers: {'Host': 'demo.test'},
        ),
        302,
      );
      expect(clients.last.requests.single.followRedirects, isFalse);
      expect(clients.last.requests.single.headers['Host'], 'demo.test');
      await controller.configure(config.copyWith(requestTimeoutMs: 20));
      handler = (_) => Completer<http.StreamedResponse>().future;
      expect(
        await controller.debugVisitUrl('https://debug.example/stalled'),
        isNull,
      );
      expect(clients.last.closed, isTrue);
      await controller.setAdvertisingConsent(false);
      await controller.setReady();
      await controller.track('');
    },
  );

  test(
    'concurrent identity/configure cannot restore the previous app identity',
    () async {
      await controller.configure(config);
      final identity = controller.setUserId('old-user');
      final configuration = controller.configure(
        config.copyWith(appId: 'app-b'),
      );
      await Future.wait([identity, configuration]);
      await controller.track('new-event');
      final event = clients.single.requests.single as http.Request;
      expect(event.headers['x-app-id'], 'app-b');
      expect(
        (jsonDecode(event.body) as Map<String, dynamic>).containsKey('userId'),
        isFalse,
      );
    },
  );

  test(
    'cancel during configure preserves navigation without restarting cancelled auto resolution',
    () async {
      final configuring = controller.configure(config);
      await controller.cancelPendingRequests();
      await configuring;
      final received = <LinkMePayload>[];
      final sub = controller.onLink.listen(received.add);
      environment.href = 'https://page.example/?cid=next';
      environment.changes.add(null);
      await flush();
      expect(received.single.cid, 'cid-ready');
      await sub.cancel();
    },
  );

  test(
    '100 completion/cancellation/deadline outcomes settle once despite late replies',
    () async {
      final scope = RequestScope();
      final gates = List.generate(100, (_) => Completer<int>());
      final counts = List.filled(100, 0);
      final results = <Future<int?>>[];
      for (var index = 0; index < 100; index += 1) {
        final current = index;
        results.add(
          scope
              .run<int>(
                Duration(milliseconds: 1 + index % 4),
                (_) => gates[current].future,
              )
              .then((value) {
                counts[current] += 1;
                return value;
              }),
        );
        if (index % 3 == 0) gates[index].complete(index);
      }
      final timer = Timer(const Duration(milliseconds: 2), scope.cancelAll);
      await Future.wait(results);
      timer.cancel();
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete(7);
      }
      await flush();
      expect(counts, everyElement(1));
    },
  );

  test(
    'a paused subscriber cannot receive buffered events from the old app',
    () async {
      await controller.configure(config);
      final received = <LinkMePayload>[];
      final sub = controller.onLink.listen(received.add)..pause();
      handler = (_) async => response({'path': '/app-a'});
      await controller.claimDeferredIfAvailable();
      await controller.configure(config.copyWith(appId: 'app-b'));
      handler = (_) async => response({'path': '/app-b'});
      await controller.claimDeferredIfAvailable();
      sub.resume();
      await flush();
      expect(received.map((payload) => payload.path), ['/app-b']);
      await sub.cancel();
    },
  );

  test(
    'request cancellation snapshots pending work and isolates throwing cleanup',
    () async {
      final scope = RequestScope();
      final started = Completer<void>();
      final release = Completer<int>();
      Future<int?>? recovery;
      final pending = scope.run<int>(const Duration(seconds: 1), (token) {
        token.onClose(() {
          recovery = scope.run<int>(const Duration(seconds: 1), (_) async => 7);
          throw StateError('Bad cleanup');
        });
        started.complete();
        return release.future;
      });
      await started.future;
      scope.cancelAll();
      expect(await pending, isNull);
      expect(await recovery, 7);
      release.complete(4);
      await flush();
      expect(await pending, isNull);
    },
  );
}
