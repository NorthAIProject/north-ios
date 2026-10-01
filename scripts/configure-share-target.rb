# Adds the KhepriShare extension (Save to Knowledge, or log it, from any app's
# Share sheet), embeds it in the app, and links NorthKit and NorthAPI into it.
# Idempotent; modelled on configure-widgets-target.rb.
#
#   bundle exec ruby scripts/configure-share-target.rb
require "xcodeproj"

PROJECT_PATH = File.expand_path("../khepri.xcodeproj", __dir__)
NAME = "KhepriShare"
project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == "khepri" }

target = project.targets.find { |t| t.name == NAME }
unless target
  target = project.new_target(:app_extension, NAME, :ios, "26.2")
  group = project.main_group.find_subpath(NAME, true)
  group.set_source_tree("<group>")
  group.set_path(NAME)
  %w[ShareViewController.swift ShareView.swift].each do |file|
    target.add_file_references([group.new_reference(file)])
  end
  group.new_reference("Info.plist")
  group.new_reference("#{NAME}.entitlements")

  app.add_dependency(target)
  embed = app.copy_files_build_phases.find { |p| p.name == "Embed Foundation Extensions" } ||
          app.new_copy_files_build_phase("Embed Foundation Extensions")
  embed.dst_subfolder_spec = "13" # PlugIns
  embed.add_file_reference(target.product_reference).settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

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
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "#{APP_IDS.fetch(config.name)}.share"
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
  # The extension calls the server with the session the app mirrors into the
  # shared Keychain group, exactly as the widgets do.
  s["API_BASE_URL"] = config.name == "Debug" ? "http:/$()/localhost:8090" : "https:/$()/kheprios.com"
  s["KHEPRI_KEYCHAIN_GROUP"] = "$(AppIdentifierPrefix)#{APP_IDS.fetch(config.name)}.shared"
end

# Shared/ holds the mirrored session and SharedAPI; compile it in here too.
shared = project.main_group.find_subpath("Shared", false)
shared.files.select { |f| f.path.end_with?(".swift") }.each do |ref|
  target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)
end

reference = project.root_object.package_references.find { |r| r.respond_to?(:relative_path) && r.relative_path == "NorthKit" }
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
