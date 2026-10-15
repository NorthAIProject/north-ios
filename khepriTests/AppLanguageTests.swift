import Foundation
import Testing
@testable import khepri

struct AppLanguageTests {
    /// A defaults suite and a way to read only what was written to it. Reading
    /// AppleLanguages through UserDefaults falls through to the simulator's own
    /// language list, which would hide what apply did.
    private struct Scratch {
        let name = "AppLanguageTests.\(UUID().uuidString)"
        var defaults: UserDefaults { UserDefaults(suiteName: name)! }
        var written: [String]? {
            UserDefaults.standard.persistentDomain(forName: name)?[AppLanguage.defaultsKey] as? [String]
        }
    }

    @Test func applyWritesTheNextLaunchLanguage() {
        let scratch = Scratch()
        AppLanguage.apply("pt-PT", defaults: scratch.defaults)
        #expect(scratch.written == ["pt-PT"])
    }

    @Test func applyIgnoresALanguageTheAppDoesNotShip() {
        let scratch = Scratch()
        AppLanguage.apply("fr", defaults: scratch.defaults)
        #expect(scratch.written == nil)
    }

    @Test func everyAccountLanguageHasATranslationBundle() {
        for language in AppLanguage.all {
            #expect(Bundle.main.localizations.contains(language.tag), "\(language.tag) is not in the app bundle")
        }
    }
}
