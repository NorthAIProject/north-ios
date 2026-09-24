import Foundation

/// NorthKit's resource bundle under a name of its own. Every target with
/// resources gets an internal `Bundle.module`; inside a test target that has
/// resources too, `.module` means the tests' bundle, not this one.
enum NorthKitBundle {
    static let bundle = Bundle.module
}
