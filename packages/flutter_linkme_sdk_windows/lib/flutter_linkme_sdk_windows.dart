import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk_platform_interface.dart';
import 'package:http/http.dart' as http;

/// The scheme registered by the Windows installer, for this app/environment.
class LinkMeWindowsConfig extends LinkMeConfig {
  const LinkMeWindowsConfig({
    required this.scheme,
    required String appId,
    required String appKey,
    super.baseUrl,
  }) : super(
         appId: appId,
         appKey: appKey,
         sendDeviceInfo: false,
         includeVendorId: false,
       );

  final String scheme;
}

class FlutterLinkmeSdkWindows extends FlutterLinkmeSdkPlatform {
  static void registerWith() {
    FlutterLinkmeSdkPlatform.instance = FlutterLinkmeSdkWindows();
  }

  static const _channel = MethodChannel('me.link/flutter_linkme_sdk_windows');
  static final _schemePattern = RegExp(r'^[a-z][a-z0-9+.-]{1,63}$');
  static final _cidPattern = RegExp(r'^[0-9a-f]{32}$');
  static final _headerPattern = RegExp(r'^[!-~]+$');
  static const _timeout = Duration(seconds: 10);
  static const _rememberedCids = 256;
  static const _maxResponseBytes = 128 * 1024;

  late final StreamController<LinkMePayload> _links =
      StreamController<LinkMePayload>.broadcast(onListen: _requestDrain);
  final Set<String> _deliveredCids = {};
  LinkMeWindowsConfig? _config;
  late Uri _base;
  Future<LinkMePayload?>? _initial;
  LinkMePayload? _pendingDelivery;
  bool _ready = false;
  bool _draining = false;
  bool _drainRequested = false;

  @override
  Stream<LinkMePayload> get onLink => _links.stream;

  @override
  Future<void> configure(LinkMeConfig config) async {
    if (config is! LinkMeWindowsConfig) {
      throw _error('windows_config_required');
    }
    final base = _httpsUri(config.baseUrl ?? 'https://li-nk.me');
    if (base == null ||
        base.hasQuery ||
        base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/') ||
        !_schemePattern.hasMatch(config.scheme) ||
        const {'http', 'https', 'file', 'mailto'}.contains(config.scheme) ||
        !_headerPattern.hasMatch(config.appId ?? '') ||
        !_headerPattern.hasMatch(config.appKey ?? '')) {
      throw _error('invalid_configuration');
    }
    if (_config == null && await _native<bool>('isAvailable') != true) {
      throw _error('activation_unavailable');
    }
    final previous = _config;
    if (previous != null) {
      if (previous.appId == config.appId &&
          previous.appKey == config.appKey &&
          previous.scheme == config.scheme &&
          _base == base) {
        return;
      }
      throw _error('already_configured');
    }

    _base = base;
    _config = config;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'activationsAvailable') _requestDrain();
    });
  }

  @override
  Future<LinkMePayload?> getInitialLink() {
    _requireConfig();
    return _initial ??= _readInitial();
  }

  Future<LinkMePayload?> _readInitial() async {
    final uri = await _native<String>('getInitialUri');
    return uri == null ? null : _claim(uri);
  }

  @override
  Future<void> setReady() async {
    _requireConfig();
    // Reserve the cold-start claim before touching the live queue, even when
    // the application calls setReady before it reads getInitialLink.
    unawaited(getInitialLink().then<void>((_) {}, onError: (Object _) {}));
    _ready = true;
    _requestDrain();
  }

  void _requestDrain() {
    _drainRequested = true;
    if (!_ready || !_links.hasListener || _draining) return;
    _draining = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      try {
        await getInitialLink();
      } on PlatformException {
        // The cold-start error belongs to getInitialLink.
      }
      while (_drainRequested && _links.hasListener) {
        _drainRequested = false;
        if (_pendingDelivery case final payload?) {
          _links.add(payload);
          _pendingDelivery = null;
        }
        while (_links.hasListener) {
          final uri = await _native<String>('takeNextUri');
          if (uri == null) break;
          try {
            final payload = await _claim(uri);
            if (payload == null) continue;
            if (_links.hasListener) {
              _links.add(payload);
            } else {
              _pendingDelivery = payload;
            }
          } on PlatformException catch (error) {
            if (_links.hasListener) _links.addError(error);
          }
        }
      }
    } on PlatformException catch (error) {
      if (_links.hasListener) _links.addError(error);
    } finally {
      _draining = false;
      if (_drainRequested && _links.hasListener) _requestDrain();
    }
  }

  Future<LinkMePayload?> _claim(String raw) async {
    final scheme = _requireConfig().scheme;
    final prefix = '$scheme://open?cid=';
    // Require an exact envelope, with one opaque CID and no route, browser URL,
    // credentials, fragment or caller-provided navigation data.
    if (!raw.startsWith(prefix) ||
        raw.length != prefix.length + 32 ||
        !_cidPattern.hasMatch(raw.substring(prefix.length))) {
      throw _error('invalid_activation');
    }
    final cid = raw.substring(prefix.length);
    if (_deliveredCids.contains(cid)) return null;
    final response = await _request(
      _base.replace(path: '/api/deeplink/windows-claim'),
      {'cid': cid},
    );
    if (response.statusCode != 200) throw _responseError(response.statusCode);

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw _error('invalid_payload');
    }
    if (json is! Map<String, dynamic> ||
        json['cid'] != cid ||
        json['navigationAllowed'] != true ||
        json['contractVersion'] != 1 ||
        json['linkId'] is! String ||
        (json['linkId'] as String).isEmpty ||
        json['forceRedirectWeb'] is! bool) {
      throw _error('invalid_payload');
    }
    final path = json['path'];
    if (path != null && !_isAppPath(path)) throw _error('invalid_payload');

    final fallback = json['webFallbackUrl'];
    if (fallback != null && fallback is! String) {
      throw _error('invalid_payload');
    }
    final payload = LinkMePayload.fromJson({
      'cid': cid,
      'linkId': json['linkId'],
      'path': path,
      'params': _stringMap(json['params']),
      'utm': _stringMap(json['utm']),
      'custom': _stringMap(json['custom']),
      'isLinkMe': true,
      'duplicate': json['duplicate'] == true,
      'forceRedirectWeb': json['forceRedirectWeb'],
      'webFallbackUrl': fallback,
    });
    if (json['forceRedirectWeb'] == true) {
      final url = fallback is String ? _httpsUri(fallback) : null;
      if (url == null) throw _error('invalid_web_fallback');
      if (await _native<bool>('openBrowser', url.toString()) != true) {
        throw _error('browser_open_failed');
      }
    }

    _deliveredCids.add(cid);
    if (_deliveredCids.length > _rememberedCids) {
      _deliveredCids.remove(_deliveredCids.first);
    }
    return json['forceRedirectWeb'] == true ? null : payload;
  }

  @override
  Future<LinkMePayload?> claimDeferredIfAvailable() async {
    throw _error('deferred_attribution_unavailable');
  }

  @override
  Future<void> setUserId(String? userId) async {
    _requireConfig();
    if (userId != null) throw _error('identity_unavailable');
  }

  @override
  Future<void> setAdvertisingConsent(bool granted) async {
    _requireConfig();
    if (granted) throw _error('advertising_id_unavailable');
  }

  @override
  Future<void> track(String event, {Map<String, dynamic>? properties}) async {
    _requireConfig();
    throw _error('tracking_unavailable');
  }

  @override
  Future<int?> debugVisitUrl(String url, {Map<String, String>? headers}) async {
    throw _error('debug_visit_unavailable');
  }

  Future<http.Response> _request(Uri url, Map<String, String> body) async {
    final config = _requireConfig();
    final request = http.Request('POST', url)
      ..followRedirects = false
      ..headers.addAll({
        'accept': 'application/json',
        'content-type': 'application/json',
        'x-app-id': config.appId!,
        'x-api-key': config.appKey!,
      })
      ..body = jsonEncode(body);
    final client = http.Client();
    try {
      return await (() async {
        final response = await client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > _maxResponseBytes) {
            throw _error('invalid_response');
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(bytes, response.statusCode);
      })().timeout(_timeout);
    } on TimeoutException {
      throw _error('request_timeout');
    } on PlatformException {
      rethrow;
    } catch (_) {
      throw _error('request_failed');
    } finally {
      client.close();
    }
  }

  LinkMeWindowsConfig _requireConfig() =>
      _config ?? (throw _error('not_configured'));

  static Future<T?> _native<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      throw _error('activation_unavailable');
    }
  }

  static Uri? _httpsUri(String value) {
    if (value.contains(r'\') || value.contains(RegExp(r'[\x00-\x20\x7f]'))) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.authority.contains('@')) {
      return null;
    }
    return uri;
  }

  static Map<String, String>? _stringMap(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic>) throw _error('invalid_payload');
    return {
      for (final entry in value.entries)
        if (entry.value case final String string) entry.key: string,
    };
  }

  static bool _isAppPath(Object path) {
    if (path is! String || !path.startsWith('/')) return false;
    try {
      final decoded = Uri.decodeComponent(path);
      return !decoded.startsWith('//') &&
          !decoded.contains(r'\') &&
          !decoded.contains(RegExp(r'[\x00-\x20\x7f]'));
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  static PlatformException _responseError(int status) =>
      _error(switch (status) {
        401 || 403 => 'unauthorized',
        404 || 410 => 'link_unavailable',
        429 => 'rate_limited',
        >= 300 && < 400 => 'unexpected_redirect',
        _ => 'request_rejected',
      });

  static PlatformException _error(String code) => PlatformException(code: code);
}
