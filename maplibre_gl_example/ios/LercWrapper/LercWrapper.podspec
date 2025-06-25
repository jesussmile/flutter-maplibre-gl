Pod::Spec.new do |s|
  s.name             = 'LercWrapper'
  s.version          = '1.0.0'
  s.summary          = 'LERC Terrain Decoder Native Library'
  s.description      = <<-DESC
Native library to decode LERC (Limited Error Raster Compression) terrain data.
                       DESC
  s.homepage         = 'https://github.com/Esri/lerc'
  s.license          = { :type => 'Apache License, Version 2.0', :text => <<-LICENSE
                         Apache License, Version 2.0
                         
                         Copyright 2016 - 2022 Esri
                         Licensed under the Apache License, Version 2.0 (the "License")
                         you may not use this file except in compliance with the License.
                         You may obtain a copy of the License at
                         
                         http://www.apache.org/licenses/LICENSE-2.0
                         LICENSE
                       }
  s.author           = { 'Esri' => 'www.esri.com' }
  s.source           = { :path => '.' }
  s.source_files     = '../../src/lerc_wrapper/**/*.{h,cpp}', '../../lerc-master/src/LercLib/**/*.{h,cpp}'
  s.public_header_files = '../../src/lerc_wrapper/*.h'
  s.preserve_paths   = '../../src/lerc_wrapper/**/*.h', '../../lerc-master/src/LercLib/**/*.h'
  s.ios.deployment_target = '12.0'
  
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-std=c++14 -stdlib=libc++',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/../../src/lerc_wrapper $(PODS_TARGET_SRCROOT)/../../lerc-master/src/LercLib'
  }
end
