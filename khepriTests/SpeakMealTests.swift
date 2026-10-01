import NorthAPI
import Testing
@testable import khepri

@MainActor
struct SpeakMealTests {
    private static let breast = "11111111-1111-1111-1111-111111111111"
    private static let white = "22222222-2222-2222-2222-222222222222"
    private static let brown = "33333333-3333-3333-3333-333333333333"

    private static let draft = FoodDraft(
        lines: [
            FoodLine(source: "200 grams of chicken breast", query: "chicken breast", grams: 200,
                     ingredientId: breast, matchedName: "Chicken breast",
                     candidates: [.init(id: breast, name: "Chicken breast")]),
            FoodLine(source: "some rice", query: "rice", grams: 100, uncertain: true,
                     candidates: [.init(id: white, name: "Rice, white"), .init(id: brown, name: "Rice, brown")]),
            FoodLine(source: "a dragonfruit", query: "dragonfruit", grams: 9000,
                     candidates: [], problem: "Nothing in the catalog matches \"dragonfruit\"."),
        ],
        unparsed: ["a glass of water"]
    )

    private func parsedModel() async -> SpeakMealModel {
        let model = SpeakMealModel { _ in Self.draft }
        model.text = "200 grams of chicken breast, some rice and a dragonfruit"
        await model.find()
        return model
    }

    @Test func onlyALoneMatchStartsTicked() async {
        let model = await parsedModel()

        #expect(model.rows.map(\.included) == [true, false, false])
        #expect(model.kept.map(\.ingredientID) == [Self.breast])
        #expect(model.unparsed == ["a glass of water"])
    }

    @Test func gramsAreHeldToWhatTheServerAccepts() async {
        let model = await parsedModel()
        #expect(model.rows[2].grams == SpeakMealModel.grams.upperBound)
    }

    @Test func choosingAnIngredientMakesTheRowAddable() async {
        let model = await parsedModel()
        model.rows[1].ingredientID = Self.brown
        model.rows[1].included = true

        #expect(model.kept.map(\.ingredientID) == [Self.breast, Self.brown])
    }

    @Test func addSendsEveryKeptRowInOrder() async {
        let model = await parsedModel()
        model.rows[1].ingredientID = Self.white
        model.rows[1].included = true

        var sent: [(String, Double)] = []
        let done = await model.add { sent.append(($0, $1)) }

        #expect(done)
        #expect(sent.map(\.0) == [Self.breast, Self.white])
        #expect(sent.map(\.1) == [200, 100])
        // The row nobody could add stays, so the person sees it was left out.
        #expect(model.rows.map(\.query) == ["dragonfruit"])
    }

    /// The rows still showing after a failure are exactly the ones not
    /// added, so tapping Add again cannot add anything twice.
    @Test func aFailureKeepsOnlyTheRowsNotYetAdded() async {
        struct Refused: Error {}
        let model = await parsedModel()
        model.rows[1].ingredientID = Self.white
        model.rows[1].included = true

        var calls = 0
        let done = await model.add { id, _ in
            calls += 1
            if id == Self.white { throw Refused() }
        }

        #expect(!done)
        #expect(calls == 2)
        #expect(model.error != nil)
        #expect(model.kept.map(\.ingredientID) == [Self.white])
    }

    @Test func aFailedReadKeepsTheWords() async {
        struct Down: Error {}
        let model = SpeakMealModel { _ in throw Down() }
        model.text = "two eggs"
        await model.find()

        #expect(model.error != nil)
        #expect(model.text == "two eggs")
        #expect(!model.parsed)
    }
}
