import NorthAPI
import NorthKit
import SwiftUI

/// An award as a coin: the monthly challenge coin for a monthly medal, the
/// badge coin for everything else. Every list, the detail sheet and the
/// celebration draw awards through this.
struct AwardCoin: View {
    let award: Award
    let size: CGFloat
    var locked = false

    var body: some View {
        if let monthly = award.monthly {
            MonthlyCoinView(month: monthly.month, target: monthly.target, size: size, locked: locked)
        } else {
            CoinMedalView(badgeID: award.id, area: award.area, size: size, locked: locked)
        }
    }
}
