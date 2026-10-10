import NorthAPI
import NorthKit
import SwiftUI

typealias InsightsRecoverySignal = Components.Schemas.InsightsRecoverySignal

/// The recovery number and its words.
struct RecoveryHeadline: View {
    let recovery: InsightsRecovery

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(recovery.points)")
                .northDisplayNumber(.largeTitle)
            Text(recovery.label)
                .font(.headline)
                .foregroundStyle(recovery.verdict == "uneven" || recovery.verdict == "low" ? NorthColor.signal : .primary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recovery \(recovery.points) out of 100, \(recovery.label)")
    }
}

/// One signal behind recovery: today's value and where it sits against the usual.
struct RecoverySignalRow: View {
    let signal: InsightsRecoverySignal

    var body: some View {
        HStack {
            Label(signal.label, systemImage: HealthSymbol.name(for: signal.key))
                .font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(signal.latest).font(.subheadline.monospacedDigit())
                UsualChip(state: signal.usual.state)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Today's recovery on the Today screen. The screen loads it and shows this
/// only when there are enough fresh readings, so an account without a watch
/// never sees an empty card.
struct RecoveryCard: View {
    let recovery: InsightsRecovery

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NorthCardHeader("Recovery")
            RecoveryHeadline(recovery: recovery)
            ForEach(recovery.signals, id: \.key) { signal in
                RecoverySignalRow(signal: signal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .northSurfaceCard(padding: 16)
    }
}

/// Loads today's recovery for the Today screen.
@MainActor
@Observable
final class RecoveryStore {
    private(set) var recovery: InsightsRecovery?
    private let service: InsightsServicing

    init(service: InsightsServicing = InsightsService()) {
        self.service = service
    }

    func load() async {
        // A failed load keeps what was shown; no readings clears it.
        if let latest = try? await service.recovery() {
            recovery = latest.hasData ? latest : nil
        }
    }
}
