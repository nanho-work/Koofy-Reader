Pod::Spec.new do |s|
  s.name             = 'koofy_reader_bridge'
  s.version          = '0.1.0'
  s.summary          = 'Koofy native full-screen Readium reader.'
  s.description      = 'Typed Flutter bridge to the official Readium Swift EPUB navigator.'
  s.homepage         = 'https://github.com/readium/swift-toolkit'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Koofy Reader' => 'Koofy Reader' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  s.resource_bundles = { 'KoofyReaderAssets' => ['Resources/*.js', 'Resources/Fonts/*.otf', 'Resources/Fonts/catalog.json'] }
  s.dependency 'Flutter'
  s.dependency 'ReadiumShared', '= 3.11.0'
  s.dependency 'ReadiumStreamer', '= 3.11.0'
  s.dependency 'ReadiumNavigator', '= 3.11.0'
  s.platform = :ios, '15.0'
  s.swift_version = '5.10'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
