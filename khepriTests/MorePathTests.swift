import Foundation
import NorthAPI
import Testing
@testable import khepri

/// The More tab's stack: sections, and one crew's space over Crews. A crew
/// space lives on the path itself, so a link that replaces it is a path edit
/// and Back from it always lands on the Crews list.
struct MorePathTests {
    private func crew(_ id: String, _ name: String) -> Crew {
        Crew(id: id, name: name, memberCount: 2, joinUrl: "https://kheprios.com/i/c/abcdefghij")
    }

    private let ironRats = "66666666-6666-6666-6666-666666666666"
    private let nightOwls = "77777777-7777-7777-7777-777777777777"

    @Test func aSectionLinkOpensThatSectionAlone() {
        #expect(MorePath.opening(section: "goals", in: []) == [.section("goals")])
        #expect(MorePath.opening(section: "crews", in: [.section("goals")]) == [.section("crews")])
    }

    /// A crew link sends its section too; a crew space already open over
    /// Crews must survive it, or the link would pop the screen it targets.
    @Test func aSectionLinkKeepsWhatIsOpenInsideIt() {
        let space = MoreRoute.crew(OpenedCrew(crew: crew(ironRats, "Iron rats")))
        let path: [MoreRoute] = [.section("crews"), space]
        #expect(MorePath.opening(section: "crews", in: path) == path)
    }

    @Test func theOpenCrewIsTheSpaceOnTop() {
        #expect(MorePath.openCrewID(in: []) == nil)
        #expect(MorePath.openCrewID(in: [.section("crews")]) == nil)
        let space = MoreRoute.crew(OpenedCrew(crew: crew(ironRats.uppercased(), "Iron rats")))
        #expect(MorePath.openCrewID(in: [.section("crews"), space]) == ironRats)
    }

    /// Another crew's space replaces the open one: one space, one live
    /// stream, and Back goes to the list.
    @Test func openingACrewReplacesTheOpenSpace() {
        let ironRatsSpace = OpenedCrew(crew: crew(ironRats, "Iron rats"))
        let nightOwlsSpace = OpenedCrew(crew: crew(nightOwls, "Night owls"))
        #expect(MorePath.opening(nightOwlsSpace, in: [.section("crews")]) == [.section("crews"), .crew(nightOwlsSpace)])
        #expect(
            MorePath.opening(nightOwlsSpace, in: [.section("crews"), .crew(ironRatsSpace)])
                == [.section("crews"), .crew(nightOwlsSpace)]
        )
        // From another tab or section, Crews comes first.
        #expect(MorePath.opening(nightOwlsSpace, in: [.section("goals")]) == [.section("crews"), .crew(nightOwlsSpace)])
    }

    /// The path can name a space the stack never showed (a push written
    /// while the app was not in front). Only a space that reported itself on
    /// screen counts as open; a link for it otherwise pushes it again.
    @Test func aSpaceIsOpenOnlyOnceShown() {
        let opened = OpenedCrew(crew: crew(ironRats.uppercased(), "Iron rats"))
        let path: [MoreRoute] = [.section("crews"), .crew(opened)]
        #expect(MorePath.shownCrewID(in: path, shown: nil) == nil)
        #expect(MorePath.shownCrewID(in: path, shown: UUID()) == nil)
        #expect(MorePath.shownCrewID(in: path, shown: opened.id) == ironRats)
        #expect(MorePath.shownCrewID(in: [.section("crews")], shown: opened.id) == nil)
    }

    /// Before another crew's space is pushed, the open one is closed.
    @Test func closingACrewLeavesCrews() {
        let space = MoreRoute.crew(OpenedCrew(crew: crew(ironRats, "Iron rats")))
        #expect(MorePath.closingCrew(in: [.section("crews"), space]) == [.section("crews")])
        #expect(MorePath.closingCrew(in: [.section("crews")]) == [.section("crews")])
        #expect(MorePath.closingCrew(in: []) == [])
    }

    /// A link names the channel the new space opens on; it travels with the
    /// path value, so the space needs no other state to find it.
    @Test func aLinkedSpaceCarriesItsChannel() {
        let route = CrewRoute(crewID: nightOwls, channelID: "88888888-8888-8888-8888-888888888888")
        let opened = OpenedCrew(crew: crew(nightOwls, "Night owls"), channelID: route.channelID)
        #expect(opened.channelID == route.channelID)
        #expect(OpenedCrew(crew: crew(nightOwls, "Night owls")).channelID == nil)
    }

    /// Opening the same crew again is a new screen (a new row tap), never
    /// the old one's state reused.
    @Test func eachOpeningIsANewScreen() {
        let first = OpenedCrew(crew: crew(ironRats, "Iron rats"))
        let again = OpenedCrew(crew: crew(ironRats, "Iron rats"))
        #expect(MoreRoute.crew(first) != MoreRoute.crew(again))
    }
}
