import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final LinkMe _linkMe = LinkMe();
  StreamSubscription<LinkMePayload>? _subscription;
  LinkMePayload? _initial;
  LinkMePayload? _latest;
  String _status = 'Configuring…';

  @override
  void initState() {
    super.initState();
    _subscription = _linkMe.onLink.listen((payload) {
      setState(() => _latest = payload);
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    const baseUrl = String.fromEnvironment(
      'LINKME_BASE_URL',
      defaultValue: 'https://e0qcsxfc.li-nk.me',
    );
    const appId = String.fromEnvironment(
      'LINKME_APP_ID',
      defaultValue: 'e0qcsxfc',
    );
    const appKey = String.fromEnvironment(
      'LINKME_APP_KEY',
      defaultValue: 'ak_nMqCl4QwFSVvjC5VrrAvTH0ziWH06WLhua6EtCvFO6o',
    );

    await _linkMe.configure(
      const LinkMeConfig(
        baseUrl: baseUrl,
        appId: appId,
        appKey: appKey,
        debug: true,
      ),
    );
    final initial = await _linkMe.getInitialLink();
    if (!mounted) return;
    setState(() {
      _initial = initial;
      _status = 'Ready';
    });
  }

  Future<void> _claimDeferred() async {
    final payload = await _linkMe.claimDeferredIfAvailable();
    if (payload != null && mounted) {
      setState(() => _latest = payload);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayPayload = _latest ?? _initial;

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Semantics(
            identifier: 'home-title',
            child: const Text('LinkMe SDK example'),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                identifier: 'home-status',
                child: Text('Status: $_status'),
              ),
              const SizedBox(height: 16),
              Semantics(
                identifier: 'latest-link-id',
                child: Text('Link ID: ${displayPayload?.linkId ?? 'none'}'),
              ),
              const SizedBox(height: 8),
              Semantics(
                identifier: 'latest-payload',
                child: _buildPayloadInfo('Latest payload', displayPayload),
              ),
              const SizedBox(height: 16),
              Semantics(
                identifier: 'button-claim-deferred',
                child: ElevatedButton(
                  onPressed: _claimDeferred,
                  child: const Text('Claim Deferred'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPayloadInfo(String label, LinkMePayload? payload) {
    if (payload == null) {
      return Text('$label: none', style: const TextStyle(color: Colors.grey));
    }

    final utm = payload.utm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(payload.toJson().toString()),
              if (utm != null && utm.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue[100]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'UTM Inspector',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...utm.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            children: [
                              Text(
                                '${e.key}: ',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Expanded(child: Text(e.value.toString())),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
