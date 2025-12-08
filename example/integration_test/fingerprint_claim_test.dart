import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const baseUrl = String.fromEnvironment('LINKME_BASE_URL', defaultValue: 'http://127.0.0.1:8080');
  const appId = String.fromEnvironment('LINKME_APP_ID', defaultValue: 'demo');
  const appKey = String.fromEnvironment('LINKME_APP_KEY', defaultValue: 'LKDEMO-0001-TESTKEY-LOCAL');
  const clickSlug = String.fromEnvironment('LINKME_CLICK_SLUG', defaultValue: 'hello');
  const clickHost = String.fromEnvironment('LINKME_CLICK_HOST', defaultValue: 'localhost:8080');
  const expectedLinkId = String.fromEnvironment('LINKME_EXPECTED_LINK_ID', defaultValue: 'hello');
  const retryDelayMs = int.fromEnvironment('LINKME_CLAIM_RETRY_MS', defaultValue: 400);
  const retryCount = int.fromEnvironment('LINKME_CLAIM_RETRIES', defaultValue: 5);

  final linkMe = LinkMe();

  group('Deferred fingerprint flow', () {
    setUpAll(() async {
      await linkMe.configure(
        const LinkMeConfig(
          baseUrl: baseUrl,
          appId: appId,
          appKey: appKey,
          debug: true,
        ),
      );
      await linkMe.getInitialLink();
    });

    testWidgets('claims deferred payload from seeded click', (tester) async {
      final clickUrl = _buildClickUrl(baseUrl, clickSlug);
      debugPrint('Visiting $clickUrl with Host $clickHost');
      final status = await linkMe.debugVisitUrl(
        clickUrl,
        headers: {'Host': clickHost},
      );
      expect(status, anyOf(200, 301, 302), reason: 'Expected click redirect status');

      LinkMePayload? payload;
      for (var attempt = 0; attempt < retryCount; attempt++) {
        payload = await linkMe.claimDeferredIfAvailable();
        if (payload != null) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: retryDelayMs));
      }

      expect(payload, isNotNull, reason: 'Expected fingerprint match after click');
      expect(payload!.linkId, expectedLinkId);

      final second = await linkMe.claimDeferredIfAvailable();
      expect(second, isNull, reason: 'Fingerprint claims should be single-use');
    });
  });
}

String _buildClickUrl(String base, String slug) {
  final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final path = slug.startsWith('/') ? slug.substring(1) : slug;
  return '$normalized/$path';
}
