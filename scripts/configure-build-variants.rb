# Adds the Beta build configuration and the per-variant settings that mirror
# Norviq: Debug talks to localhost, Beta and Release talk to production, and
# Beta installs beside Release under its own bundle ID.
#
# Idempotent: safe to re-run after Xcode rewrites the project.
#
#   bundle exec ruby scripts/configure-build-variants.rb
require "xcodeproj"

PROJECT_PATH = File.expand_path("../khepri.xcodeproj", __dir__)
APP_BUNDLE_ID = "com.fernandocorreia.khepri"

VARIANTS = {
  "Debug" => {
    "PRODUCT_BUNDLE_IDENTIFIER" => APP_BUNDLE_ID,
    "APP_DISPLAY_NAME" => "Khepri Dev",
    # $() stops xcconfig-style parsing from reading // as a comment.
    "API_BASE_URL" => "http:/$()/localhost:8090",
    "APS_ENVIRONMENT" => "development",
    "KHEPRI_KEYCHAIN_GROUP" => "$(AppIdentifierPrefix)#{APP_BUNDLE_ID}.shared",
  },
  "Beta" => {
    "PRODUCT_BUNDLE_IDENTIFIER" => "#{APP_BUNDLE_ID}.beta",
    "APP_DISPLAY_NAME" => "Khepri Beta",
    "API_BASE_URL" => "https:/$()/kheprios.com",
    "APS_ENVIRONMENT" => "production",
    "KHEPRI_KEYCHAIN_GROUP" => "$(AppIdentifierPrefix)#{APP_BUNDLE_ID}.beta.shared",
  },
  "Release" => {
    "PRODUCT_BUNDLE_IDENTIFIER" => APP_BUNDLE_ID,
    "APP_DISPLAY_NAME" => "Khepri",
    "API_BASE_URL" => "https:/$()/kheprios.com",
    "APS_ENVIRONMENT" => "production",
    "KHEPRI_KEYCHAIN_GROUP" => "$(AppIdentifierPrefix)#{APP_BUNDLE_ID}.shared",
  },
}.freeze

# Shared by every configuration of the app target.
APP_SETTINGS = {
  "INFOPLIST_KEY_CFBundleDisplayName" => "$(APP_DISPLAY_NAME)",
  "APP_GROUP_ID" => "group.$(PRODUCT_BUNDLE_IDENTIFIER)",
  "CODE_SIGN_ENTITLEMENTS" => "Config/khepri.entitlements",
  # iOS first. macOS gets its own destination in Phase 10.
  "SUPPORTED_PLATFORMS" => "iphoneos iphonesimulator",
  "SDKROOT" => "iphoneos",
  "TARGETED_DEVICE_FAMILY" => "1,2",
  "SUPPORTS_MACCATALYST" => "NO",
  # Usage strings iOS shows in its permission prompts. Required: asking for
  # Health access without them crashes the app.
  "INFOPLIST_KEY_NSHealthShareUsageDescription" =>
    "Khepri reads your workouts, activity, heart rate, sleep and weight so your coach can see how training and recovery are going.",
  # The workout on the Lock Screen and in the Dynamic Island.
  "INFOPLIST_KEY_NSSupportsLiveActivities" => "YES",
  # Only HTTPS and Apple's own crypto, which are exempt: answers App Store
  # Connect's export-compliance question so builds reach testers unprompted.
  "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption" => "NO",
  "INFOPLIST_KEY_NSHealthUpdateUsageDescription" =>
    "Khepri saves workouts you finish in the app to Apple Health.",
  # Dictation: the microphone, and Apple's on-device speech recognition.
  "INFOPLIST_KEY_NSMicrophoneUsageDescription" =>
    "Khepri listens only while the microphone button is on, to turn what you say into text.",
  "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription" =>
    "Your words are turned into text on this iPhone so you can speak to your coach instead of typing.",
}.freeze

project = Xcodeproj::Project.open(PROJECT_PATH)

def ensure_beta(list)
  return list["Beta"] if list["Beta"]

  release = list["Release"] or abort("no Release configuration in #{list}")
  beta = list.project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  beta.name = "Beta"
  beta.build_settings = Marshal.load(Marshal.dump(release.build_settings))
  beta.base_configuration_reference = release.base_configuration_reference
  list.build_configurations << beta
  beta
end

ensure_beta(project.build_configuration_list)
project.targets.each { |target| ensure_beta(target.build_configuration_list) }

base = project.files.find { |f| f.path == "Config/Base.xcconfig" } ||
       project.main_group.new_file("Config/Base.xcconfig")

app = project.targets.find { |t| t.name == "khepri" } or abort("no khepri target")
app.build_configurations.each do |config|
  config.base_configuration_reference = base
  settings = config.build_settings
  APP_SETTINGS.merge(VARIANTS.fetch(config.name)).each { |k, v| settings[k] = v }
  %w[MACOSX_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET ENABLE_APP_SANDBOX
     ENABLE_HARDENED_RUNTIME ENABLE_USER_SELECTED_FILES].each { |k| settings.delete(k) }
  settings.delete("LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]")
end

project.targets.reject { |t| t == app }.each do |target|
  target.build_configurations.each do |config|
    s = config.build_settings
    s["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
    s["SDKROOT"] = "iphoneos"
    s["TARGETED_DEVICE_FAMILY"] = "1,2"
    %w[MACOSX_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET].each { |k| s.delete(k) }
  end
end

project.save
puts "configured #{project.targets.map(&:name).join(', ')} for Debug/Beta/Release"
