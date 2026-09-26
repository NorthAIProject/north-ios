#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit
@testable import NorthKit

struct ThemeTests {
    @Test func everyTokenResolvesFromTheCatalog() {
        let names = ["Background", "Foreground", "Card", "Primary", "Signal", "Agent", "Ember", "SportRun", "SportStrength",
                     "DayWater", "DayFood", "DayMove", "DaySleep", "DayNow"]
        for name in names {
            #expect(UIColor(named: name, in: NorthKitBundle.bundle, compatibleWith: nil) != nil, "missing colour set \(name)")
        }
    }

    @Test func lightAndDarkBackgroundsDiffer() throws {
        let colour = try #require(UIColor(named: "Background", in: NorthKitBundle.bundle, compatibleWith: nil))
        let light = colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(light != dark)
    }

    @Test func geistRegistersWithCoreText() {
        NorthFont.register()
        #expect(UIFont(name: "Geist-Regular", size: 17) != nil)
        #expect(UIFont(name: "GeistMono-Regular", size: 17) != nil)
    }
}
#endif
