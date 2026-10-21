import Foundation
import Testing
@testable import khepri

/// The notify sheet's mute choice: an active mute is kept unless changed.
struct CrewNotifySheetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func activeMuteIsTheDefaultAndKeepsItsDate() {
        let until = now.addingTimeInterval(5 * 3600)
        let mute = CrewNotifySheet.Mute.initial(mutedUntil: until, now: now)
        #expect(mute == .current(until))
        #expect(mute.until(from: now) == until)
        let choices = CrewNotifySheet.Mute.choices(mutedUntil: until, now: now)
        #expect(choices == [.current(until), .off, .hour, .day, .week])
    }

    @Test func expiredOrNoMuteStartsOff() {
        let past = now.addingTimeInterval(-60)
        #expect(CrewNotifySheet.Mute.initial(mutedUntil: past, now: now) == .off)
        #expect(CrewNotifySheet.Mute.initial(mutedUntil: nil, now: now) == .off)
        #expect(CrewNotifySheet.Mute.choices(mutedUntil: past, now: now) == [.off, .hour, .day, .week])
        #expect(CrewNotifySheet.Mute.off.until(from: now) == nil)
        #expect(CrewNotifySheet.Mute.hour.until(from: now) == now.addingTimeInterval(3600))
    }
}
