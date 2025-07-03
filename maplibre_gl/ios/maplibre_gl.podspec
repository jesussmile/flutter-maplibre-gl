#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'maplibre_gl'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin.'
  s.description      = <<-DESC
A new Flutter plugin.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'maplibre_gl/Sources/maplibre_gl/**/*'
  
  # Include LERC native sources
  s.source_files += 'maplibre_gl/Sources/maplibre_gl/LERC/**/*.{h,cpp}'
  s.public_header_files = 'maplibre_gl/Sources/maplibre_gl/LERC/*.h'
  
  # LERC library configuration
  s.preserve_paths = 'maplibre_gl/Sources/maplibre_gl/LERC/**/*.h'
  
  s.dependency 'Flutter'
  # When updating the dependency version,
  # make sure to also update the version in Package.swift.
  s.dependency 'MapLibre', '6.14.0'
  s.swift_version = '5.0'
  s.ios.deployment_target = '12.0'
  
  # Configure C++ compilation
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-std=c++14 -stdlib=libc++',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/maplibre_gl/Sources/maplibre_gl/LERC $(PODS_TARGET_SRCROOT)/maplibre_gl/Sources/maplibre_gl/LERC/lerc-master/src/LercLib'
  }
end

