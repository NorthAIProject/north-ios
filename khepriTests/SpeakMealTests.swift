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

    @Test func addSendsEveryKeptRowInOneBatch() async {
        let model = await parsedModel()
        model.rows[1].ingredientID = Self.white
        model.rows[1].included = true

        var batches: [[(ingredientID: String, grams: Double)]] = []
        let done = await model.add { batches.append($0); return true }

        #expect(done)
        #expect(batches.count == 1)
        #expect(batches.first?.map(\.ingredientID) == [Self.breast, Self.white])
        #expect(batches.first?.map(\.grams) == [200, 100])
    }

    /// The server adds a batch whole or not at all, so a refused one leaves
    /// every row to send again.
    @Test func aRefusedBatchKeepsEveryRow() async {
        let model = await parsedModel()

        let done = await model.add { _ in false }

        #expect(!done)
        #expect(model.kept.map(\.ingredientID) == [Self.breast])
        #expect(model.rows.count == 3)
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
