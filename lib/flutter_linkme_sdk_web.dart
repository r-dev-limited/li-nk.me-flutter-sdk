import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'flutter_linkme_sdk_platform_interface.dart';
import 'src/models.dart';

class FlutterLinkmeSdkWeb extends FlutterLinkmeSdkPlatform {
  FlutterLinkmeSdkWeb();

  static void registerWith(Registrar registrar) {
    FlutterLinkmeSdkPlatform.instance = FlutterLinkmeSdkWeb();
  }

  final StreamController<LinkMePayload> _linkController =
      StreamController<LinkMePayload>.broadcast();
  LinkMeConfig _config = const LinkMeConfig();
  LinkMePayload? _lastPayload;
  String? _userId;
  final Set<String> _seenCids = <String>{};

  StreamSubscription<html.Event>? _popStateSub;
  StreamSubscription<html.Event>? _hashChangeSub;

  @override
  Stream<LinkMePayload> get onLink => _linkController.stream;

  @override
  Future<void> configure(LinkMeConfig config) async {
    _config = config;
    await _popStateSub?.cancel();
    await _hashChangeSub?.cancel();

    _popStateSub = html.window.onPopState.listen((_) {
      unawaited(_resolveFromCurrentLocation(stripCid: true));
    });
    _hashChangeSub = html.window.onHashChange.listen((_) {
      unawaited(_resolveFromCurrentLocation(stripCid: true));
    });

    await _resolveFromCurrentLocation(stripCid: true);
  }

  @override
  Future<LinkMePayload?> getInitialLink() async {
    _lastPayload ??= await _resolveFromCurrentLocation(stripCid: false);
    return _lastPayload;
  }

  @override
  Future<LinkMePayload?> claimDeferredIfAvailable() async {
    final response = await _requestJson(
      _apiUrl('/deferred/claim'),
      method: 'POST',
      headers: _buildHeaders(includeContentType: true),
      body: <String, dynamic>{
        'platform': 'web',
        if (_config.sendDeviceInfo) 'device': _buildDevicePayload(),
      },
    );

    if (response == null || response.status < 200 || response.status >= 300) {
      return null;
    }
    final payload = LinkMePayload.fromJson(response.json);
    _emit(payload);
    return payload;
  }

  @override
  Future<void> setUserId(String? userId) async {
    _userId = userId;
  }

  @override
  Future<void> setAdvertisingConsent(bool granted) async {
    // Web SDK does not require a dedicated consent flag endpoint.
    // Consent should be applied by controlling whether track() is called.
  }

  @override
  Future<void> track(String event, {Map<String, dynamic>? properties}) async {
    if (event.trim().isEmpty) {
      return;
    }

    await _requestJson(
      _apiUrl('/app-events'),
      method: 'POST',
      headers: _buildHeaders(includeContentType: true),
      body: <String, dynamic>{
        'event': event,
        'platform': 'web',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        if (_userId != null && _userId!.isNotEmpty) 'userId': _userId,
        if (properties != null && properties.isNotEmpty) 'props': properties,
      },
    );
  }

  @override
  Future<void> setReady() async {
    // No-op on web. Kept for API parity with native SDKs.
  }

  @override
  Future<int?> debugVisitUrl(String url, {Map<String, String>? headers}) async {
    try {
      final request = await html.HttpRequest.request(
        url,
        method: 'GET',
        requestHeaders: headers,
      );
      return request.status;
    } catch (_) {
      return null;
    }
  }

  Future<LinkMePayload?> _resolveFromCurrentLocation({
    required bool stripCid,
  }) async {
    final href = html.window.location.href;
    return _processUrl(href, stripCid: stripCid);
  }

  Future<LinkMePayload?> _processUrl(
    String rawUrl, {
    required bool stripCid,
  }) async {
    final parsed = _parseUri(rawUrl);
    if (parsed == null) {
      return null;
    }

    final extracted = _extractCid(parsed);
    final cid = extracted.cid;
    if (cid != null && cid.isNotEmpty) {
      if (_seenCids.contains(cid) && _lastPayload != null) {
        return _lastPayload;
      }
      final payload = await _resolveCid(cid);
      if (payload != null) {
        _seenCids.add(cid);
        if (stripCid && extracted.sanitizedHref != null) {
          _replaceUrl(extracted.sanitizedHref!);
        }
        _emit(payload);
      }
      return payload;
    }

    if (_isSameOrigin(parsed)) {
      final payload = await _resolveUniversalLink(parsed.toString());
      if (payload != null) {
        _emit(payload);
      }
      return payload;
    }

    return null;
  }

  Future<LinkMePayload?> _resolveCid(String cid) async {
    final response = await _requestJson(
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
    final payload = LinkMePayload.fromJson(<String, dynamic>{
      ...response.json,
      if (response.json['cid'] == null) 'cid': cid,
      if (response.json['isLinkMe'] == null) 'isLinkMe': true,
    });
    return payload;
  }

  Future<LinkMePayload?> _resolveUniversalLink(String url) async {
    final response = await _requestJson(
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

  Map<String, dynamic> _buildDevicePayload() {
    final nav = html.window.navigator;
    final payload = <String, dynamic>{
      'platform': 'web',
      if (nav.userAgent.isNotEmpty) 'userAgent': nav.userAgent,
      if (nav.language.isNotEmpty) 'locale': nav.language,
      if (nav.languages != null && nav.languages!.isNotEmpty)
        'preferredLocales': nav.languages,
      'timezone': DateTime.now().timeZoneName,
      'screen': <String, dynamic>{
        'width': html.window.screen?.width,
        'height': html.window.screen?.height,
        'pixelRatio': html.window.devicePixelRatio,
      },
    };
    return payload;
  }

  Uri? _parseUri(String url) {
    final direct = Uri.tryParse(url);
    if (direct != null && direct.hasScheme) {
      return direct;
    }
    try {
      return Uri.base.resolve(url);
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
      html.window.history.replaceState(html.window.history.state, '', nextUrl);
    } catch (_) {
      // Ignore replace failures in restrictive browsers.
    }
  }

  void _emit(LinkMePayload payload) {
    _lastPayload = payload;
    if (!_linkController.isClosed) {
      _linkController.add(payload);
    }
  }

  Future<_JsonResponse?> _requestJson(
    String url, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = await html.HttpRequest.request(
        url,
        method: method,
        sendData: body == null ? null : jsonEncode(body),
        requestHeaders: headers,
      );
      final responseText = request.responseText;
      final decoded = responseText == null || responseText.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(responseText);
      final status = request.status ?? 0;
      if (decoded is Map<String, dynamic>) {
        return _JsonResponse(status, decoded);
      }
      return _JsonResponse(status, <String, dynamic>{});
    } catch (_) {
      return null;
    }
  }
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
