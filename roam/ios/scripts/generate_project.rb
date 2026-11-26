# Generates ios/Roam.xcodeproj from the sources on disk: the app plus the share extension.
# Run from the ios/ folder:  gem install xcodeproj && ruby scripts/generate_project.rb
require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Roam.xcodeproj')
BUNDLE_ID = ENV.fetch('BUNDLE_ID', 'com.eitanshay.roam')
SHARE_ID = "#{BUNDLE_ID}.share"

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes['LastUpgradeCheck'] = '2600'
project.root_object.attributes['LastSwiftUpdateCheck'] = '2600'

app = project.new_target(:application, 'Roam', :ios, '17.0')
share = project.new_target(:app_extension, 'RoamShare', :ios, '17.0')

# Drop the SDK-pinned Foundation.framework references the gem adds; Swift links system frameworks automatically.
[app, share].each do |t|
  t.frameworks_build_phase.files.to_a.each do |bf|
    ref = bf.file_ref
    bf.remove_from_project
    ref.remove_from_project if ref
  end
end

def attach(targets, ref, name)
  case File.extname(name)
  when '.swift'
    targets.each { |t| t.source_build_phase.add_file_reference(ref) }
  when '.xcassets', '.ttf', '.tsv'
    targets.each { |t| t.resources_build_phase.add_file_reference(ref) }
  end
end

def add_children(group, targets, dir)
  Dir.glob(File.join(dir, '*')).sort.each do |path|
    name = File.basename(path)
    if File.directory?(path) && !name.end_with?('.xcassets')
      sub = group.new_group(name, name)
      add_children(sub, targets, path)
    else
      ref = group.new_reference(path)
      ref.path = name
      ref.source_tree = '<group>'
      attach(targets, ref, name)
    end
  end
end

# App sources and resources (Info.plist and entitlements are referenced by build settings, not copied).
add_children(project.main_group.new_group('Roam', 'Roam'), [app], File.join(ROOT, 'Roam'))
add_children(project.main_group.new_group('RoamShare', 'RoamShare'), [share], File.join(ROOT, 'RoamShare'))

# Code shared by the app and the extension (Keychain hand-off).
add_children(project.main_group.new_group('Shared', 'Shared'), [app, share], File.join(ROOT, 'Shared'))

# Core logic, compiled straight into both targets. The same files are unit-tested by RoamCore/Package.swift.
core_group = project.main_group.new_group('RoamCore', 'RoamCore/Sources/RoamCore')
add_children(core_group, [app, share], File.join(ROOT, 'RoamCore', 'Sources', 'RoamCore'))

common = lambda do |s|
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['SUPPORTS_MACCATALYST'] = 'NO'
  s['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = ''
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['MARKETING_VERSION'] = '1.0'
  s['VERSIONING_SYSTEM'] = 'apple-generic'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['SWIFT_EMIT_LOC_STRINGS'] = 'NO'
  s['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
end

app.build_configurations.each do |config|
  s = config.build_settings
  common.call(s)
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['PRODUCT_NAME'] = 'Roam'
  s['INFOPLIST_FILE'] = 'Roam/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'Roam/Roam.entitlements'
  s['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  s['ENABLE_PREVIEWS'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
end

share.build_configurations.each do |config|
  s = config.build_settings
  common.call(s)
  s['PRODUCT_BUNDLE_IDENTIFIER'] = SHARE_ID
  s['PRODUCT_NAME'] = 'RoamShare'
  s['INFOPLIST_FILE'] = 'RoamShare/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'RoamShare/RoamShare.entitlements'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# Google Maps SDK (Swift Package) for the Map tab; app target only.
maps_pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
maps_pkg.repositoryURL = 'https://github.com/googlemaps/ios-maps-sdk'
maps_pkg.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '11.4.0' }
project.root_object.package_references << maps_pkg
maps_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
maps_dep.package = maps_pkg
maps_dep.product_name = 'GoogleMaps'
app.package_product_dependencies << maps_dep
maps_bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
maps_bf.product_ref = maps_dep
app.frameworks_build_phase.files << maps_bf

# Embed the extension in the app.
app.add_dependency(share)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(share.product_reference)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
end

project.save

# Shared scheme: CI (Codemagic) can only see shared schemes.
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app, nil, launch_target: true)
scheme.save_as(PROJECT_PATH, 'Roam', true)

puts "Generated #{PROJECT_PATH} (#{BUNDLE_ID} + #{SHARE_ID})"
