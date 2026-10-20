# AlertTapper.xcodeproj를 만든다. 대상 앱 없이 UI 테스트 번들 하나만 둔다.
#   gem install --user-install xcodeproj && ruby gen.rb
require 'xcodeproj'

dir = __dir__
project = Xcodeproj::Project.new(File.join(dir, 'AlertTapper.xcodeproj'))
target = project.new_target(:ui_test_bundle, 'AlertTapperUITests', :ios, '18.0')
group = project.main_group.new_group('AlertTapperUITests', 'AlertTapperUITests')
target.add_file_references([group.new_file('AlertTapperUITests.swift')])
target.build_configurations.each do |c|
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'example.fan.exp.AlertTapperUITests',
    'SWIFT_VERSION' => '5.0',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'CODE_SIGN_STYLE' => 'Manual',
    'CODE_SIGN_IDENTITY' => '-',
    'TARGETED_DEVICE_FAMILY' => '1',
  )
end
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(target)
scheme.save_as(project.path, 'AlertTapper', true)
