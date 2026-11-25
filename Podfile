# Nur für die Beta-App (VLCKit 4 gibt es bisher nur über CocoaPods)
platform :ios, '17.0'
project 'IPTVPlayerBeta.xcodeproj'

target 'IPTVPlayerBeta' do
  use_frameworks!
  pod 'VLCKit', '4.0.0a18'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |c|
      c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
