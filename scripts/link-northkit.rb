# Adds the local NorthKit package to the project and links it into the app.
# Idempotent.
#
#   bundle exec ruby scripts/link-northkit.rb
require "xcodeproj"

PROJECT_PATH = File.expand_path("../khepri.xcodeproj", __dir__)
project = Xcodeproj::Project.open(PROJECT_PATH)
root = project.root_object

reference = root.package_references.find do |ref|
  ref.isa == "XCLocalSwiftPackageReference" && ref.relative_path == "NorthKit"
end
unless reference
  reference = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  reference.relative_path = "NorthKit"
  root.package_references << reference
end

app = project.targets.find { |t| t.name == "khepri" }
unless app.package_product_dependencies.any? { |d| d.product_name == "NorthKit" }
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = "NorthKit"
  dependency.package = reference
  app.package_product_dependencies << dependency

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  app.frameworks_build_phase.files << build_file
end

project.save
puts "NorthKit linked into #{app.name}"
