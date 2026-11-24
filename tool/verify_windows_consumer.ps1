$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$sdk = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path.Replace('\', '/')
$consumer = Join-Path $env:RUNNER_TEMP 'linkme_windows_consumer'
flutter create --platforms=windows --project-name=linkme_windows_consumer --no-pub $consumer
Push-Location $consumer
try {
  @"
name: linkme_windows_consumer
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter:
    sdk: flutter
  flutter_linkme_sdk:
    path: "$sdk"
  flutter_linkme_sdk_windows:
    path: "$sdk/packages/flutter_linkme_sdk_windows"
dependency_overrides:
  flutter_linkme_sdk:
    path: "$sdk"
"@ | Set-Content pubspec.yaml

  $runner = 'windows/runner/main.cpp'
  $source = Get-Content $runner -Raw
  $source = $source.Replace('#include "flutter_window.h"', @'
#include <flutter_linkme_sdk_windows/flutter_linkme_sdk_windows_plugin_c_api.h>

#include "flutter_window.h"
'@)
  $source = $source.Replace('  // Attach to console', @'
  switch (LinkMeStartWindowsInstance(L"LinkMe.Windows.Consumer.CI")) {
    case kLinkMeForwarded:
      return EXIT_SUCCESS;
    case kLinkMeActivationFailed:
      return EXIT_FAILURE;
    case kLinkMePrimary:
      break;
  }
  // Attach to console
'@)
  $source = $source.Replace('  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));', @'
  if (!LinkMeHasWindowsProtocolArgument()) {
    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
  }
'@)
  Set-Content $runner $source
  @'
import 'package:flutter/widgets.dart';
import 'package:flutter_linkme_sdk/flutter_linkme_sdk.dart';
import 'package:flutter_linkme_sdk_windows/flutter_linkme_sdk_windows.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final linkMe = LinkMe();
  await linkMe.configure(const LinkMeWindowsConfig(
    appId: 'fixture-app',
    appKey: 'fixture-key',
    scheme: 'linkme-ci',
  ));
  await linkMe.setReady();
  runApp(const SizedBox.shrink());
}
'@ | Set-Content lib/main.dart

  flutter pub get
  flutter build windows --debug --no-pub
} finally {
  Pop-Location
}
