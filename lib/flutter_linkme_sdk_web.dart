import 'dart:async';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_linkme_sdk_platform_interface.dart';
import 'src/web_controller.dart';

class FlutterLinkmeSdkWeb extends LinkMeWebController {
  FlutterLinkmeSdkWeb() : super(environment: _BrowserEnvironment());

  static void registerWith(Registrar registrar) {
    FlutterLinkmeSdkPlatform.instance = FlutterLinkmeSdkWeb();
  }
}

class _BrowserEnvironment implements LinkMeWebEnvironment {
  @override
  String get currentHref => web.window.location.href;
  @override
  Uri get baseUri => Uri.base;
  @override
  Stream<void> get locationChanges => Stream<void>.multi((controller) {
    final pop = web.window.onPopState.listen((_) => controller.add(null));
    final hash = web.EventStreamProviders.hashChangeEvent
        .forTarget(web.window)
        .listen((_) => controller.add(null));
    controller.onCancel = () async {
      await pop.cancel();
      await hash.cancel();
    };
  });
  @override
  void replaceUrl(String url) =>
      web.window.history.replaceState(web.window.history.state, '', url);
  @override
  void openExternalUrl(String url) {
    web.window.location.href = url;
  }

  @override
  Map<String, dynamic> buildDevicePayload() {
    final nav = web.window.navigator;
    return <String, dynamic>{
      'platform': 'web',
      if (nav.userAgent.isNotEmpty) 'userAgent': nav.userAgent,
      if (nav.language.isNotEmpty) 'locale': nav.language,
      'timezone': DateTime.now().timeZoneName,
      'screen': <String, dynamic>{
        'width': web.window.screen.width,
        'height': web.window.screen.height,
        'pixelRatio': web.window.devicePixelRatio,
      },
    };
  }
}
