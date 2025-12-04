Pod::Spec.new do |s|
  s.name             = 'flutter_linkme_sdk'
  s.version          = '0.1.0'
  s.summary          = 'Flutter wrapper around LinkMe native SDKs.'
  s.description      = <<-DESC
Flutter plugin that bridges LinkMeKit (iOS/macOS) and the LinkMe Android SDK for deep linking + attribution.
                       DESC
  s.homepage         = 'https://li-nk.me/resources/developer/setup/flutter'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'R-DEV Limited' => 'support@li-nk.me' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'LinkMeKit', '~> 0.1.2'
  s.platform = :ios, '14.0'

  # Flutter.framework does not contain an i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.9'
end
