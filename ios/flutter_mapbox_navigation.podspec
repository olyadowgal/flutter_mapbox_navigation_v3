#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_mapbox_navigation.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_mapbox_navigation'
  s.version          = '0.2.2'
  s.summary          = 'Add Turn By Turn Navigation to Your Flutter Application Using MapBox. Never leave your app when you need to navigate your users to a location.'
  s.description      = <<-DESC
Add Turn By Turn Navigation to Your Flutter Application Using MapBox. Never leave your app when you need to navigate your users to a location.
                       DESC
  s.homepage         = 'https://eopeter.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Emmanuel Peter Oche' => 'eopeter@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_mapbox_navigation/Sources/flutter_mapbox_navigation/**/*.swift'
  s.resource_bundles = {'flutter_mapbox_navigation_privacy' => ['flutter_mapbox_navigation/Sources/flutter_mapbox_navigation/PrivacyInfo.xcprivacy']}
  s.dependency 'Flutter'
  s.dependency 'MapboxNavigationCore', '~> 3.7.0'
  s.dependency 'MapboxNavigationUIKit', '~> 3.7.0'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
