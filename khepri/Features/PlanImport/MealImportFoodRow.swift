import NorthAPI
import SwiftUI

/// One imported food: what the file said, the ingredient it maps to, and its
/// weight.
struct MealImportFoodRow: View {
    @Binding var food: MealImportFood
    let recompute: () -> Void

    private static let mine = "mine"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(food.food)
            if let line = food.sourceText, !line.isEmpty, line != food.food {
                Text("“\(line)”").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Your plan said \(line)")
            }
            Text(source).font(.caption).foregroundStyle(.secondary)
            Picker("Ingredient", selection: ingredient) {
                Text("Choose…").tag("")
                ForEach(food.candidates ?? [], id: \.id) { Text($0.name).tag($0.id) }
                if let id = food.ingredientId, !(food.candidates ?? []).contains(where: { $0.id == id }) {
                    Text(food.matchedName).tag(id)
                }
                if hasStatedMacros { Text("My own food (file's macros)").tag(Self.mine) }
            }
            HStack {
                Text("Grams")
                // The decimal pad has no Return key, so the committed value,
                // not a submit, is what asks for a recompute.
                TextField("—", value: $food.grams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: food.grams) { recompute() }
            }
            if food.estimated == true {
                Text("≈ estimated").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("estimated weight")
            }
            if food.optional == true {
                Text("Optional · not counted").font(.caption).foregroundStyle(.secondary)
            }
            if let macros = food.macros {
                Text(macros.summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(food.flags ?? [], id: \.self) { flag in
                Label(flag, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            ForEach(food.checks ?? [], id: \.self) { check in
                Label(check, systemImage: "xmark.circle").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var hasStatedMacros: Bool {
        food.statedProteinG != nil && food.statedCarbG != nil && food.statedFatG != nil
    }

    private var source: String {
        var parts: [String] = []
        if let quantity = food.quantity { parts.append("\(quantity.formatted()) \(food.unit)") }
        if let protein = food.statedProteinG, let carbs = food.statedCarbG, let fat = food.statedFatG {
            parts.append("file says \(Int(protein)) P · \(Int(carbs)) C · \(Int(fat)) F")
        }
        return parts.isEmpty ? "From your file" : parts.joined(separator: " · ")
    }

    private var ingredient: Binding<String> {
        Binding(
            get: { food.saveAsMine ? Self.mine : (food.ingredientId ?? "") },
            set: { choice in
                food.saveAsMine = choice == Self.mine
                food.ingredientId = (choice.isEmpty || choice == Self.mine) ? nil : choice
                recompute()
            }
        )
    }
}
