class LinkMeConfig {
  const LinkMeConfig({
    this.baseUrl,
    this.appId,
    this.appKey,
    @Deprecated(
      'Pasteboard is now controlled from the Portal. This parameter is ignored.',
    )
    this.enablePasteboard = false,
    this.sendDeviceInfo = true,
    this.includeVendorId = true,
    this.includeAdvertisingId = false,
    this.debug = false,
  });

  final String? baseUrl;
  final String? appId;
  final String? appKey;

  /// @deprecated Pasteboard is now controlled from the Portal (App Settings → iOS).
  /// The SDK automatically checks pasteboard on iOS. This parameter is ignored.
  final bool enablePasteboard;
  final bool sendDeviceInfo;
  final bool includeVendorId;
  final bool includeAdvertisingId;
  final bool debug;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'baseUrl': baseUrl ?? 'https://li-nk.me',
    if (appId != null) 'appId': appId,
    if (appKey != null) 'appKey': appKey,
    'enablePasteboard': enablePasteboard,
    'sendDeviceInfo': sendDeviceInfo,
    'includeVendorId': includeVendorId,
    'includeAdvertisingId': includeAdvertisingId,
    'debug': debug,
  };

  LinkMeConfig copyWith({
    String? baseUrl,
    String? appId,
    String? appKey,
    bool? enablePasteboard,
    bool? sendDeviceInfo,
    bool? includeVendorId,
    bool? includeAdvertisingId,
    bool? debug,
  }) {
    return LinkMeConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      appId: appId ?? this.appId,
      appKey: appKey ?? this.appKey,
      enablePasteboard: enablePasteboard ?? this.enablePasteboard,
      sendDeviceInfo: sendDeviceInfo ?? this.sendDeviceInfo,
      includeVendorId: includeVendorId ?? this.includeVendorId,
      includeAdvertisingId: includeAdvertisingId ?? this.includeAdvertisingId,
      debug: debug ?? this.debug,
    );
  }

  factory LinkMeConfig.fromJson(Map<String, dynamic> json) {
    return LinkMeConfig(
      baseUrl: (json['baseUrl'] as String?) ?? 'https://li-nk.me',
      appId: json['appId'] as String?,
      appKey: json['appKey'] as String?,
      enablePasteboard: (json['enablePasteboard'] as bool?) ?? false,
      sendDeviceInfo: (json['sendDeviceInfo'] as bool?) ?? true,
      includeVendorId: (json['includeVendorId'] as bool?) ?? true,
      includeAdvertisingId: (json['includeAdvertisingId'] as bool?) ?? false,
      debug: (json['debug'] as bool?) ?? false,
    );
  }
}

class LinkMePayload {
  const LinkMePayload({
    this.cid,
    this.linkId,
    this.path,
    this.params,
    this.utm,
    this.custom,
    this.url,
    this.isLinkMe,
    this.duplicate,
    this.forceRedirectWeb,
    this.webFallbackUrl,
  });

  final String? cid;
  final String? linkId;
  final String? path;
  final Map<String, String>? params;
  final Map<String, String>? utm;
  final Map<String, String>? custom;
  final String? url;
  final bool? isLinkMe;
  final bool? duplicate;
  final bool? forceRedirectWeb;
  final String? webFallbackUrl;

  bool get isEmpty =>
      cid == null &&
      linkId == null &&
      path == null &&
      params == null &&
      utm == null &&
      custom == null &&
      url == null &&
      isLinkMe == null &&
      duplicate == null &&
      forceRedirectWeb == null &&
      webFallbackUrl == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (cid != null) 'cid': cid,
    if (linkId != null) 'linkId': linkId,
    if (path != null) 'path': path,
    if (params != null) 'params': params,
    if (utm != null) 'utm': utm,
    if (custom != null) 'custom': custom,
    if (url != null) 'url': url,
    if (isLinkMe != null) 'isLinkMe': isLinkMe,
    if (duplicate != null) 'duplicate': duplicate,
    if (forceRedirectWeb != null) 'forceRedirectWeb': forceRedirectWeb,
    if (webFallbackUrl != null) 'webFallbackUrl': webFallbackUrl,
  };

  factory LinkMePayload.fromJson(Map<String, dynamic> json) {
    return LinkMePayload(
      cid: _string(json['cid']),
      linkId: _string(json['linkId']),
      path: _string(json['path']),
      params: _mapOfString(json['params']),
      utm: _mapOfString(json['utm']),
      custom: _mapOfString(json['custom']),
      url: _string(json['url']),
      isLinkMe: _bool(json['isLinkMe']),
      duplicate: _bool(json['duplicate']),
      forceRedirectWeb: _bool(json['forceRedirectWeb']),
      webFallbackUrl: _string(json['webFallbackUrl']),
    );
  }

  static LinkMePayload? tryFromJson(dynamic value) {
    if (value is! Map) return null;
    final json = <String, dynamic>{};
    value.forEach((dynamic key, dynamic item) {
      if (key is String) json[key] = item;
    });
    final payload = LinkMePayload.fromJson(json);
    return payload.isEmpty ? null : payload;
  }

  static String? _string(dynamic value) => value is String ? value : null;

  static bool? _bool(dynamic value) => value is bool ? value : null;

  static Map<String, String>? _mapOfString(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final result = <String, String>{};
      value.forEach((dynamic key, dynamic val) {
        if (key is String && val is String) result[key] = val;
      });
      return result.isEmpty ? null : result;
    }
    return null;
  }
}
