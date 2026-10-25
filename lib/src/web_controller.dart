import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../flutter_linkme_sdk_platform_interface.dart';
import 'models.dart';
import 'request_scope.dart';

abstract interface class LinkMeWebEnvironment {
  String get currentHref;
  Uri get baseUri;
  Stream<void> get locationChanges;
  void replaceUrl(String url);
  void openExternalUrl(String url);
  Map<String, dynamic> buildDevicePayload();
}

/// Shared by the browser adapter and controlled transport tests.
class LinkMeWebController extends FlutterLinkmeSdkPlatform {
  LinkMeWebController({
    required this.environment,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final LinkMeWebEnvironment environment;
  final http.Client Function() _clientFactory;
  final RequestScope _requests = RequestScope();
  int _generation = 0;
  int _configurationGeneration = 0;
  bool _active = false;

  StreamController<_Emission> _linkController =
      StreamController<_Emission>.broadcast(sync: true);
  LinkMeConfig _config = const LinkMeConfig();
  LinkMePayload? _lastPayload;
  String? _userId;
  final Map<String, LinkMePayload> _payloadsByCid = <String, LinkMePayload>{};

  StreamSubscription<void>? _navigation;

  @override
  Stream<LinkMePayload> get onLink => _linkController.stream
      .where((event) => _current(event.generation))
      .map((event) => event.payload);

  bool _current(int generation) => _active && _generation == generation;

  @override
  Future<void> configure(LinkMeConfig config) async {
    config.validate();
    final generation = ++_generation;
    final configurationGeneration = ++_configurationGeneration;
    _requests.cancelAll();
    _config = config;
    _active = true;
    _lastPayload = null;
    _userId = null;
    _payloadsByCid.clear();
    final previous = _navigation;
    _navigation = null;
    await previous?.cancel();
    if (!_active || _configurationGeneration != configurationGeneration) return;
    _navigation = environment.locationChanges.listen((_) {
      if (!_active || _configurationGeneration != configurationGeneration) {
        return;
      }
      unawaited(_resolveFromCurrentLocation(stripCid: true));
    });
    if (_current(generation)) await _resolveFromCurrentLocation(stripCid: true);
  }

  void _invalidateRequests() {
    _generation += 1;
    _requests.cancelAll();
  }

  @override
  Future<void> cancelPendingRequests() async {
    _invalidateRequests();
  }

  @override
  Future<void> dispose() async {
    _generation += 1;
    _configurationGeneration += 1;
    _requests.cancelAll();
    _active = false;
    _lastPayload = null;
    _userId = null;
    _payloadsByCid.clear();
    _config = const LinkMeConfig();
    final previous = _navigation;
    _navigation = null;
    final previousController = _linkController;
    _linkController = StreamController<_Emission>.broadcast(sync: true);
    // A listener may dispose while synchronous delivery is in progress. Close
    // after that frame and do not wait for a paused subscriber to consume done.
    scheduleMicrotask(() {
      unawaited(previousController.close());
    });
    await previous?.cancel();
  }

  @override
  Future<LinkMePayload?> getInitialLink() async {
    if (!_active) return null;
    if (_lastPayload != null) return _lastPayload;
    final generation = _generation;
    final payload = await _resolveFromCurrentLocation(stripCid: false);
    return _current(generation) ? payload : null;
  }

  @override
  Future<LinkMePayload?> claimDeferredIfAvailable() async {
    if (!_active) return null;
    final generation = _generation;
    final response = await _requestJson(
      generation,
      _apiUrl('/deferred/claim'),
      method: 'POST',
      headers: _buildHeaders(includeContentType: true),
      body: <String, dynamic>{
        'platform': 'web',
        if (_config.sendDeviceInfo) 'device': _buildDevicePayload(),
      },
    );

    if (!_current(generation) ||
        response == null ||
        response.status < 200 ||
        response.status >= 300) {
      return null;
    }
    final payload = LinkMePayload.tryFromJson(response.json);
    if (payload == null) return null;
    if (_handleForcedWebRedirect(payload)) return null;
    _emit(payload, generation);
    return _current(generation) ? payload : null;
  }

  @override
  Future<void> setUserId(String? userId) async {
    if (_userId != userId) _invalidateRequests();
    _userId = userId;
  }

  @override
  Future<void> setAdvertisingConsent(bool granted) async {
    // Web SDK does not require a dedicated consent flag endpoint.
    // Consent should be applied by controlling whether track() is called.
  }

  @override
  Future<void> track(String event, {Map<String, dynamic>? properties}) async {
    if (!_active || event.trim().isEmpty) {
      return;
    }

    await _requestJson(
      _generation,
      _apiUrl('/app-events'),
      method: 'POST',
      headers: _buildHeaders(includeContentType: true),
      body: <String, dynamic>{
        'type': event,
        'platform': 'web',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        if (_lastPayload?.cid != null) 'cid': _lastPayload!.cid,
        if (_lastPayload?.linkId != null) 'linkId': _lastPayload!.linkId,
        if (_userId != null && _userId!.isNotEmpty) 'userId': _userId,
        if (properties != null) 'detail': jsonEncode(properties),
      },
    );
  }

  @override
  Future<void> setReady() async {
    // No-op on web. Kept for API parity with native SDKs.
  }

  @override
  Future<int?> debugVisitUrl(String url, {Map<String, String>? headers}) async {
    if (!_active) return null;
    final generation = _generation;
    final result = await _requests.run<int>(
      Duration(milliseconds: _config.requestTimeoutMs),
      (cancellation) async {
        if (!_current(generation)) throw StateError('Configuration changed');
        final client = _clientFactory();
        cancellation.onClose(client.close);
        final request = http.AbortableRequest(
          'GET',
          Uri.parse(url),
          abortTrigger: cancellation.whenClosed,
        )..followRedirects = false;
        if (headers != null) request.headers.addAll(headers);
        return (await client.send(request)).statusCode;
      },
    );
    return _current(generation) ? result : null;
  }

  Future<LinkMePayload?> _resolveFromCurrentLocation({
    required bool stripCid,
  }) async {
    if (!_active) return null;
    final href = environment.currentHref;
    return _processUrl(href, stripCid: stripCid);
  }

  Future<LinkMePayload?> _processUrl(
    String rawUrl, {
    required bool stripCid,
  }) async {
    if (!_active) return null;
    final generation = _generation;
    final parsed = _parseUri(rawUrl);
    if (parsed == null) {
      return null;
    }

    final extracted = _extractCid(parsed);
    final cid = extracted.cid;
    if (cid != null && cid.isNotEmpty) {
      final cached = _payloadsByCid[cid];
      if (cached != null) {
        return cached;
      }
      final payload = await _resolveCid(cid, generation);
      if (!_current(generation)) return null;
      if (payload != null) {
        if (stripCid && extracted.sanitizedHref != null) {
          _replaceUrl(extracted.sanitizedHref!);
        }
        if (!_current(generation)) return null;
        if (_handleForcedWebRedirect(payload)) return null;
        _payloadsByCid[cid] = payload;
        _emit(payload, generation);
      }
      return _current(generation) ? payload : null;
    }

    if (_isSameOrigin(parsed)) {
      final payload = await _resolveUniversalLink(
        parsed.toString(),
        generation,
      );
      if (!_current(generation)) return null;
      if (payload != null) {
        if (_handleForcedWebRedirect(payload)) return null;
        _emit(payload, generation);
      }
      return _current(generation) ? payload : null;
    }

    return null;
  }

  Future<LinkMePayload?> _resolveCid(String cid, int generation) async {
    final response = await _requestJson(
      generation,
      _apiUrl('/deeplink?cid=${Uri.encodeQueryComponent(cid)}'),
      method: 'GET',
      headers: <String, String>{
        ..._buildHeaders(includeContentType: false),
        if (_config.sendDeviceInfo)
          'x-linkme-device': jsonEncode(_buildDevicePayload()),
      },
    );

    if (response == null || response.status < 200 || response.status >= 300) {
      return null;
    }
    final parsed = LinkMePayload.tryFromJson(response.json);
    if (parsed == null) return null;
    return LinkMePayload.fromJson(<String, dynamic>{
      ...response.json,
      if (response.json['cid'] == null) 'cid': cid,
      if (response.json['isLinkMe'] == null) 'isLinkMe': true,
    });
  }

  Future<LinkMePayload?> _resolveUniversalLink(
    String url,
    int generation,
  ) async {
    final response = await _requestJson(
      generation,
      _apiUrl('/deeplink/resolve-url'),
      method: 'POST',
      headers: _buildHeaders(includeContentType: true),
      body: <String, dynamic>{
        'url': url,
        if (_config.sendDeviceInfo) 'device': _buildDevicePayload(),
      },
    );

    if (response == null) {
      return null;
    }

    if (response.status < 200 || response.status >= 300) {
      final error = response.json['error'];
      if (error == 'domain_not_found') {
        final parsed = _parseUri(url);
        if (parsed != null) {
          return _buildBasicUniversalPayload(parsed);
        }
      }
      return null;
    }

    final parsed = LinkMePayload.tryFromJson(response.json);
    if (parsed == null) return null;
    return LinkMePayload.fromJson(<String, dynamic>{
      ...response.json,
      if (response.json['isLinkMe'] == null) 'isLinkMe': true,
    });
  }

  Map<String, String> _buildHeaders({required bool includeContentType}) {
    return <String, String>{
      'Accept': 'application/json',
      if (includeContentType) 'Content-Type': 'application/json',
      if ((_config.appId ?? '').isNotEmpty) 'x-app-id': _config.appId!,
      if ((_config.appKey ?? '').isNotEmpty) 'x-api-key': _config.appKey!,
    };
  }

  Map<String, dynamic> _buildDevicePayload() =>
      environment.buildDevicePayload();

  Uri? _parseUri(String url) {
    final direct = Uri.tryParse(url);
    if (direct != null && direct.hasScheme) {
      return direct;
    }
    try {
      return environment.baseUri.resolve(url);
    } catch (_) {
      return null;
    }
  }

  bool _isSameOrigin(Uri uri) {
    final base = _configuredBaseUri();
    if (base == null) {
      return false;
    }
    return uri.scheme == base.scheme &&
        uri.host == base.host &&
        (uri.hasPort ? uri.port : _defaultPort(uri.scheme)) ==
            (base.hasPort ? base.port : _defaultPort(base.scheme));
  }

  int _defaultPort(String scheme) {
    if (scheme == 'https') {
      return 443;
    }
    if (scheme == 'http') {
      return 80;
    }
    return 0;
  }

  Uri? _configuredBaseUri() {
    final base = (_config.baseUrl ?? 'https://li-nk.me').trim();
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return Uri.tryParse(normalized);
  }

  String _apiUrl(String path) {
    final base = _configuredBaseUri()?.toString() ?? 'https://li-nk.me';
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalized/api$path';
  }

  _CidExtraction _extractCid(Uri parsed) {
    String? cid = parsed.queryParameters['cid'];
    var sanitized = parsed;

    if (cid != null && cid.isNotEmpty) {
      final nextQuery = Map<String, String>.from(parsed.queryParameters)
        ..remove('cid');
      sanitized = parsed.replace(
        queryParameters: nextQuery.isEmpty ? null : nextQuery,
      );
      return _CidExtraction(cid: cid, sanitizedHref: sanitized.toString());
    }

    final hash = parsed.fragment;
    if (hash.isEmpty) {
      return const _CidExtraction();
    }

    try {
      final hashParts = hash.split('?');
      if (hashParts.length == 2) {
        final params = Uri.splitQueryString(hashParts[1]);
        final hashCid = params['cid'];
        if (hashCid != null && hashCid.isNotEmpty) {
          params.remove('cid');
          final remaining = Uri(
            queryParameters: params.isEmpty ? null : params,
          ).query;
          final sanitizedHash = remaining.isEmpty
              ? hashParts[0]
              : '${hashParts[0]}?$remaining';
          return _CidExtraction(
            cid: hashCid,
            sanitizedHref: parsed.replace(fragment: sanitizedHash).toString(),
          );
        }
      } else if (hash.startsWith('cid=')) {
        final params = Uri.splitQueryString(hash);
        final hashCid = params['cid'];
        if (hashCid != null && hashCid.isNotEmpty) {
          params.remove('cid');
          final sanitizedHash = Uri(
            queryParameters: params.isEmpty ? null : params,
          ).query;
          return _CidExtraction(
            cid: hashCid,
            sanitizedHref: parsed.replace(fragment: sanitizedHash).toString(),
          );
        }
      }
    } catch (_) {
      return const _CidExtraction();
    }
    return const _CidExtraction();
  }

  LinkMePayload _buildBasicUniversalPayload(Uri uri) {
    final params = <String, String>{};
    final utm = <String, String>{};
    const utmKeys = <String>{
      'utm_source',
      'utm_medium',
      'utm_campaign',
      'utm_term',
      'utm_content',
      'utm_id',
      'utm_source_platform',
      'utm_creative_format',
      'utm_marketing_tactic',
      'tags',
    };

    uri.queryParameters.forEach((key, value) {
      if (utmKeys.contains(key)) {
        utm[key] = value;
      } else {
        params[key] = value;
      }
    });

    return LinkMePayload(
      path: uri.path.isEmpty ? '/' : uri.path,
      url: uri.toString(),
      params: params.isEmpty ? null : params,
      utm: utm.isEmpty ? null : utm,
      isLinkMe: false,
    );
  }

  void _replaceUrl(String nextUrl) {
    try {
      environment.replaceUrl(nextUrl);
    } catch (_) {
      // Ignore replace failures in restrictive browsers.
    }
  }

  void _emit(LinkMePayload payload, int generation) {
    if (!_current(generation) || payload.navigationAllowed == false) return;
    _lastPayload = payload;
    if (!_linkController.isClosed) {
      _linkController.add(_Emission(generation, payload));
    }
  }

  bool _handleForcedWebRedirect(LinkMePayload payload) {
    if (payload.navigationAllowed == false) return true;
    if (payload.forceRedirectWeb != true) {
      return false;
    }
    final target = (payload.webFallbackUrl ?? '').trim();
    if (target.isEmpty) {
      return false;
    }
    try {
      environment.openExternalUrl(target);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<_JsonResponse?> _requestJson(
    int generation,
    String url, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) {
    return _requests.run<_JsonResponse>(
      Duration(milliseconds: _config.requestTimeoutMs),
      (cancellation) async {
        if (!_current(generation)) throw StateError('Configuration changed');
        final client = _clientFactory();
        cancellation.onClose(client.close);
        final request = http.AbortableRequest(
          method,
          Uri.parse(url),
          abortTrigger: cancellation.whenClosed,
        )..headers.addAll(headers);
        if (body != null) request.body = jsonEncode(body);
        final streamed = await client.send(request);
        final response = await http.Response.fromStream(streamed);
        final decoded = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body);
        return _JsonResponse(
          response.statusCode,
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
        );
      },
    );
  }
}

class _Emission {
  const _Emission(this.generation, this.payload);
  final int generation;
  final LinkMePayload payload;
}

class _JsonResponse {
  const _JsonResponse(this.status, this.json);

  final int status;
  final Map<String, dynamic> json;
}

class _CidExtraction {
  const _CidExtraction({this.cid, this.sanitizedHref});

  final String? cid;
  final String? sanitizedHref;
}
