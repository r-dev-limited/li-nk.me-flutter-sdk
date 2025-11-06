class LinkMeConfig {
  const LinkMeConfig({
    this.baseUrl,
    this.appId,
    this.appKey,
    this.enablePasteboard = false,
    this.sendDeviceInfo = true,
    this.includeVendorId = true,
    this.includeAdvertisingId = false,
  });

  final String? baseUrl;
  final String? appId;
  final String? appKey;
  final bool enablePasteboard;
  final bool sendDeviceInfo;
  final bool includeVendorId;
  final bool includeAdvertisingId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'baseUrl': baseUrl ?? 'https://li-nk.me',
    if (appId != null) 'appId': appId,
    if (appKey != null) 'appKey': appKey,
    'enablePasteboard': enablePasteboard,
    'sendDeviceInfo': sendDeviceInfo,
    'includeVendorId': includeVendorId,
    'includeAdvertisingId': includeAdvertisingId,
  };

  LinkMeConfig copyWith({
    String? baseUrl,
    String? appId,
    String? appKey,
    bool? enablePasteboard,
    bool? sendDeviceInfo,
    bool? includeVendorId,
    bool? includeAdvertisingId,
  }) {
    return LinkMeConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      appId: appId ?? this.appId,
      appKey: appKey ?? this.appKey,
      enablePasteboard: enablePasteboard ?? this.enablePasteboard,
      sendDeviceInfo: sendDeviceInfo ?? this.sendDeviceInfo,
      includeVendorId: includeVendorId ?? this.includeVendorId,
      includeAdvertisingId: includeAdvertisingId ?? this.includeAdvertisingId,
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
    );
  }
}

class LinkMePayload {
  const LinkMePayload({
    this.linkId,
    this.path,
    this.params,
    this.utm,
    this.custom,
  });

  final String? linkId;
  final String? path;
  final Map<String, String>? params;
  final Map<String, String>? utm;
  final Map<String, String>? custom;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (linkId != null) 'linkId': linkId,
    if (path != null) 'path': path,
    if (params != null) 'params': params,
    if (utm != null) 'utm': utm,
    if (custom != null) 'custom': custom,
  };

  factory LinkMePayload.fromJson(Map<String, dynamic> json) {
    return LinkMePayload(
      linkId: json['linkId'] as String?,
      path: json['path'] as String?,
      params: _mapOfString(json['params']),
      utm: _mapOfString(json['utm']),
      custom: _mapOfString(json['custom']),
    );
  }

  static Map<String, String>? _mapOfString(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return value.map((dynamic key, dynamic val) {
        return MapEntry(key.toString(), val?.toString() ?? '');
      });
    }
    return null;
  }
}
