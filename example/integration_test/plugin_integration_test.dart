import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('configure completes without error', (tester) async {
    final linkMe = LinkMe();
    await linkMe.configure(const LinkMeConfig(baseUrl: 'https://example.com'));
    final initial = await linkMe.getInitialLink();
    expect(initial, isNull);
  });
}
