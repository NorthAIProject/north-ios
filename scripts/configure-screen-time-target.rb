# Adds the KhepriScreenTimeReport extension (a Device Activity report that
# draws today's screen time inside My Day), embeds it in the app, and gives
# both the Family Controls entitlement. Idempotent.
#
# Run this only once the App IDs have the Family Controls capability: for
# development builds Xcode can enable it itself, but TestFlight and App Store
# builds need Apple to approve the distribution entitlement first
# (developer.apple.com/contact/request/family-controls-distribution).
# Until then the app builds without the extension and My Day shows only the
# screen time that was typed in.
#
#   bundle exec ruby scripts/configure-screen-time-target.rb
require "xcodeproj"

PROJECT_PATH = File.expand_path("../khepri.xcodeproj", __dir__)
NAME = "KhepriScreenTimeReport"
ENTITLEMENT = "com.apple.developer.family-controls"
project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == "khepri" }

target = project.targets.find { |t| t.name == NAME }
unless target
  target = project.new_target(:app_extension, NAME, :ios, "26.2")
  group = project.main_group.find_subpath(NAME, true)
  group.set_source_tree("<group>")
  group.set_path(NAME)
  target.add_file_references([group.new_reference("ScreenTimeReportExtension.swift")])
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
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "#{APP_IDS.fetch(config.name)}.screentime"
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
  s["CODE_SIGN_ENTITLEMENTS"] = "#{NAME}/#{NAME}.entitlements"
end

# The app asks for authorization, so it needs the entitlement too.
app_entitlements = File.expand_path("../Config/khepri.entitlements", __dir__)
plist = Xcodeproj::Plist.read_from_path(app_entitlements)
unless plist[ENTITLEMENT]
  plist[ENTITLEMENT] = true
  Xcodeproj::Plist.write_to_path(plist, app_entitlements)
end

project.save
puts "#{NAME} configured and embedded in #{app.name}"
