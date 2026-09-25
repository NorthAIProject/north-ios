# Adds the KhepriWidgets extension (Live Activities now, widgets in Phase 7),
# embeds it in the app, and links NorthKit into it. Idempotent.
#
#   bundle exec ruby scripts/configure-widgets-target.rb
require "xcodeproj"

PROJECT_PATH = File.expand_path("../khepri.xcodeproj", __dir__)
NAME = "KhepriWidgets"
project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == "khepri" }

target = project.targets.find { |t| t.name == NAME }
unless target
  target = project.new_target(:app_extension, NAME, :ios, "26.2")
  group = project.main_group.find_subpath(NAME, true)
  group.set_source_tree("<group>")
  group.set_path(NAME)
  %w[KhepriWidgetsBundle.swift WorkoutLiveActivity.swift].each do |file|
    target.add_file_references([group.new_reference(file)])
  end
  group.new_reference("Info.plist")

  # Embed in the app, and build it first.
  app.add_dependency(target)
  embed = app.copy_files_build_phases.find { |p| p.name == "Embed Foundation Extensions" } ||
          app.new_copy_files_build_phase("Embed Foundation Extensions")
  embed.dst_subfolder_spec = "13" # PlugIns
  embed.add_file_reference(target.product_reference).settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

# Beta, copied from Release, as for every other target.
list = target.build_configuration_list
unless list["Beta"]
  beta = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  beta.name = "Beta"
  beta.build_settings = Marshal.load(Marshal.dump(list["Release"].build_settings))
  list.build_configurations << beta
end

APP_IDS = { "Debug" => "com.fernandocorreia.khepri", "Beta" => "com.fernandocorreia.khepri.beta", "Release" => "com.fernandocorreia.khepri" }
target.build_configurations.each do |config|
  s = config.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "#{APP_IDS.fetch(config.name)}.widgets"
  s["PRODUCT_NAME"] = "$(TARGET_NAME)"
  s["INFOPLIST_FILE"] = "#{NAME}/Info.plist"
  s["GENERATE_INFOPLIST_FILE"] = "YES"
  s["INFOPLIST_KEY_CFBundleDisplayName"] = "Khepri"
  s["IPHONEOS_DEPLOYMENT_TARGET"] = "26.2"
  s["SWIFT_VERSION"] = "5.0"
  s["TARGETED_DEVICE_FAMILY"] = "1,2"
  s["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
  s["SDKROOT"] = "iphoneos"
  s["DEVELOPMENT_TEAM"] = "84X9WYBF36"
  s["CODE_SIGN_STYLE"] = "Automatic"
  s["SKIP_INSTALL"] = "YES"
  s["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
  s["MARKETING_VERSION"] = "1.0"
  s["CURRENT_PROJECT_VERSION"] = "1"
  s["SWIFT_EMIT_LOC_STRINGS"] = "YES"
  s["CODE_SIGN_ENTITLEMENTS"] = "#{NAME}/#{NAME}.entitlements"
  # Widgets fetch their own data, so they need the server and the session.
  s["API_BASE_URL"] = config.name == "Debug" ? "http:/$()/localhost:8090" : "https:/$()/kheprios.com"
  s["KHEPRI_KEYCHAIN_GROUP"] = "$(AppIdentifierPrefix)#{APP_IDS.fetch(config.name)}.shared"
end

# NorthKit (the shared attributes type, colours) into the extension.
reference = project.root_object.package_references.find { |r| r.respond_to?(:relative_path) && r.relative_path == "NorthKit" }
unless target.package_product_dependencies.any? { |d| d.product_name == "NorthKit" }
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = "NorthKit"
  dependency.package = reference
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

# Widget sources beyond the Live Activity.
group = project.main_group.find_subpath(NAME, false)
%w[TodayProvider.swift TodayWidget.swift LockScreenWidget.swift].each do |file|
  next if target.source_build_phase.files_references.any? { |r| r.path == file }
  target.add_file_references([group.files.find { |f| f.path == file } || group.new_reference(file)])
end
group.new_reference("#{NAME}.entitlements") unless group.files.any? { |f| f.path == "#{NAME}.entitlements" }

# Shared/ is compiled into both the app and the extension: the mirrored
# session, the client that reads it, the snapshot, and the water intent.
shared = project.main_group.find_subpath("Shared", true)
shared.set_source_tree("<group>")
shared.set_path("Shared")
Dir.children(File.expand_path("../Shared", __dir__)).grep(/\.swift\z/).sort.each do |file|
  ref = shared.files.find { |f| f.path == file } || shared.new_reference(file)
  [app, target].each do |t|
    t.add_file_references([ref]) unless t.source_build_phase.files_references.include?(ref)
  end
end

# NorthAPI too, now that widgets call the server.
%w[NorthKit NorthAPI].each do |product|
  next if target.package_product_dependencies.any? { |d| d.product_name == product }
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = product
  dependency.package = reference
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

project.save
puts "#{NAME} configured and embedded in #{app.name}"
