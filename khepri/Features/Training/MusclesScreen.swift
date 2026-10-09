import NorthAPI
import NorthKit
import SwiftUI

/// The body figure full size: what the last week of training heated, front
/// or back, with every region listed beneath it. Tapping a region, on the
/// figure or in the list, opens its exercises.
struct MusclesScreen: View {
    var service: DayServicing = DayService()
    @State private var bodyMap: BodyMap?
    @State private var side: BodySide = .front
    @State private var error: String?
    @State private var muscle: MuscleFilter?
    @State private var training: TrainingServicing = TrainingService()

    var body: some View {
        List {
            Section {
                Picker("Side", selection: $side) {
                    ForEach(BodySide.allCases) { Text($0 == .front ? "Front" : "Back").tag($0) }
                }
                .pickerStyle(.segmented)
                BodyMapView(heat: bodyMap?.heat ?? [:], side: side) { muscle = MuscleFilter(id: $0) }
                    .frame(height: 360)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("muscles-body-map")
            }
            if let bodyMap {
                Section("Last \(bodyMap.days) days") {
                    ForEach(bodyMap.muscles.sorted { $0.intensity > $1.intensity }, id: \.id) { region in
                        Button { muscle = MuscleFilter(id: region.id) } label: {
                            LabeledContent(BodyMapText.name(region.id), value: BodyMapText.lastTrained(region.lastTrainedOn))
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Muscles")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $muscle) { filter in
            NavigationStack {
                ExerciseLibrary(service: training, muscle: filter.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { muscle = nil } } }
            }
        }
    }

    private func load() async {
        do {
            let fresh = try await service.bodyMap(days: 7)
            bodyMap = fresh
            side = BodySide.hottest(fresh.heat)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct MuscleFilter: Identifiable {
    let id: String
}
