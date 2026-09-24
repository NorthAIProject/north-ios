# Writes the two shared schemes CI and fastlane build:
#
#   khepri                  Run/Test in Debug, Archive in Release (App Store)
#   Khepri TestFlight Dev   Run/Test in Debug, Archive in Beta    (TestFlight)
#
# Shared schemes live in xcshareddata so a fresh clone and CI see them;
# Xcode's auto-created schemes are per-user and gitignored.
#
#   bundle exec ruby scripts/configure-schemes.rb
require "xcodeproj"

PROJECT_PATH = File.expand_path("../khepri.xcodeproj", __dir__)
project = Xcodeproj::Project.open(PROJECT_PATH)

app = project.targets.find { |t| t.name == "khepri" }
unit = project.targets.find { |t| t.name == "khepriTests" }
ui = project.targets.find { |t| t.name == "khepriUITests" }

{ "khepri" => "Release", "Khepri TestFlight Dev" => "Beta" }.each do |name, archive_config|
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(app)
  scheme.set_launch_target(app)
  scheme.add_test_target(unit)
  scheme.add_test_target(ui)
  scheme.launch_action.build_configuration = "Debug"
  scheme.test_action.build_configuration = "Debug"
  scheme.profile_action.build_configuration = archive_config
  scheme.analyze_action.build_configuration = "Debug"
  scheme.archive_action.build_configuration = archive_config
  scheme.save_as(PROJECT_PATH, name, true)
  puts "wrote scheme #{name} (archive: #{archive_config})"
end
