import Foundation
import NorthAPI
import Testing

@testable import khepri

struct DailyPostTests {
    private func post(body: String = "One.\n\nTwo.\r\n\r\nThree.", kudos: Int = 0, kudoed: Bool = false) -> DailyPost {
        DailyPost(id: "p1", date: "2026-10-20", theme: "hydration", title: "Water before meals", body: body,
                  aiGenerated: true, kudos: kudos, kudoed: kudoed)
    }

    @Test func splitsTheBodyOnBlankLines() {
        #expect(post().paragraphs == ["One.", "Two.", "Three."])
        #expect(post(body: "  \n\nOnly one.\n\n ").paragraphs == ["Only one."])
    }

    @Test func kudosFlipsOnceAndNeverGoesNegative() {
        let given = post(kudos: 2).withKudos(true)
        #expect(given.kudoed && given.kudos == 3)
        #expect(given.withKudos(true).kudos == 3, "giving twice counts once")
        #expect(given.withKudos(false).kudos == 2)
        #expect(post(kudos: 0, kudoed: true).withKudos(false).kudos == 0)
    }

    @Test func theDraftNamesThePost() {
        #expect(post().coachDraft == "About today's post, \"Water before meals\": ")
    }

    @Test func theDayIsTheCalendarDay() {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: post().day)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 20)
    }
}
