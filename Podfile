platform :ios, '17.0'
use_frameworks!

target 'HICOR' do
  pod 'GoogleMLKit/TextRecognition'

  target 'HICORTests' do
    inherit! :search_paths
  end
end

# ML Kit's static .framework arm64 slice targets iOS device only;
# Apple Silicon Mac simulator builds must run x86_64 via Rosetta.
# Also lift transitive pods' minimum iOS target to silence Xcode 26 warnings
# about pre-iOS-12 deployment targets in PromisesObjC, GoogleToolboxForMac, GTMSessionFetcher.
post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
  end
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end
