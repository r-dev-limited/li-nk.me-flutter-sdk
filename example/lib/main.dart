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
    await _linkMe.configure(
      const LinkMeConfig(
        baseUrl: 'https://li-nk.me',
        appId: 'demo-app',
        appKey: 'LKDEMO-0001-TESTKEY',
      ),
    );
    final initial = await _linkMe.getInitialLink();
    if (!mounted) return;
    setState(() {
      _initial = initial;
      _status = 'Ready';
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('LinkMe SDK example'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: $_status'),
              const SizedBox(height: 16),
              Text('Initial payload: ${_initial?.toJson() ?? 'none'}'),
              const SizedBox(height: 16),
              Text('Latest payload: ${_latest?.toJson() ?? 'none'}'),
            ],
          ),
        ),
      ),
    );
  }
}
