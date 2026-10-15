import Foundation
import NorthAPI
import Testing
@testable import khepri

struct MarkdownBlockTests {
    @Test func readsTheBlocksACoachReportUses() {
        let blocks = MarkdownBlock.parse("""
        ## The week

        Four sessions, sleep steady
        at 7.2 h.

        - Two long runs
        * One **strength** day
        1. Keep the Monday run
        12. Add a rest day
        #not a heading
        """)
        #expect(blocks == [
            .heading(level: 2, text: "The week"),
            .paragraph("Four sessions, sleep steady at 7.2 h."),
            .bullet("Two long runs"),
            .bullet("One **strength** day"),
            .numbered(number: "1", text: "Keep the Monday run"),
            .numbered(number: "12", text: "Add a rest day"),
            .paragraph("#not a heading"),
        ])
    }

    @Test func keepsAFencedBlockVerbatim() {
        let blocks = MarkdownBlock.parse("""
        Warm-up:

        ```
        # not a heading
          - not a bullet
        ```
        After.
        """)
        #expect(blocks == [
            .paragraph("Warm-up:"),
            .code("# not a heading\n  - not a bullet"),
            .paragraph("After."),
        ])
    }

    @Test func anUnclosedFenceRunsToTheEnd() {
        #expect(MarkdownBlock.parse("~~~\nsquat 5x5") == [.code("squat 5x5")])
    }

    @Test func joinsQuotedLinesIntoOneQuote() {
        let blocks = MarkdownBlock.parse("> Keep the knee\n> over the toe.\n\n>Second")
        #expect(blocks == [.quote("Keep the knee over the toe."), .quote("Second")])
    }

    @Test func readsThematicBreaks() {
        let blocks = MarkdownBlock.parse("One\n\n---\n\n* * *\n\nTwo")
        #expect(blocks == [.paragraph("One"), .rule, .rule, .paragraph("Two")])
    }

    @Test func joinsTheHardWrappedLinesOfAPDF() {
        let blocks = MarkdownBlock.parse("Phase one runs for\nsix weeks, three\nsessions a week.\n\nPhase two")
        #expect(blocks == [.paragraph("Phase one runs for six weeks, three sessions a week."), .paragraph("Phase two")])
    }

    @Test func outlinesHeadingsByTheirPosition() {
        let blocks = MarkdownBlock.parse("# Plan\n\nIntro\n\n## Weeks 1–4\n\n- Base\n\n### Long run")
        #expect(MarkdownBlock.outline(blocks) == [
            .init(index: 0, level: 1, text: "Plan"),
            .init(index: 2, level: 2, text: "Weeks 1–4"),
            .init(index: 4, level: 3, text: "Long run"),
        ])
    }
}

struct MarkdownDocumentTests {
    @Test func aWeeklyReportLeadsWithItsOpeningAndCardsEachSection() {
        let document = MarkdownDocument(markdown: """
        # A steady week

        Four sessions.

        ## What moved

        - Squat up

        ## What stalled

        Sleep.

        ## Next week

        1. Rest
        """)
        #expect(document.lead == [.paragraph("Four sessions.")])
        #expect(document.sections == [
            .init(heading: "What moved", blocks: [.bullet("Squat up")]),
            .init(heading: "What stalled", blocks: [.paragraph("Sleep.")]),
            .init(heading: "Next week", blocks: [.numbered(number: "1", text: "Rest")]),
        ])
    }

    @Test func aBriefingIsAllOpening() {
        let document = MarkdownDocument(markdown: "Recovery is low.\n\nLast check-in was yesterday.")
        #expect(document.lead == [.paragraph("Recovery is low."), .paragraph("Last check-in was yesterday.")])
        #expect(document.sections.isEmpty)
    }

    @Test func groupsByPositionNotHeadingText() {
        let document = MarkdownDocument(markdown: "# Semana\n\nAbertura.\n\n## O que avançou\n\n- Agachamento")
        #expect(document.lead == [.paragraph("Abertura.")])
        #expect(document.sections == [.init(heading: "O que avançou", blocks: [.bullet("Agachamento")])])
    }

    @Test func keepsATitleHeadingThatIsNotFirst() {
        let document = MarkdownDocument(markdown: "Opening.\n\n# Later")
        #expect(document.lead == [.paragraph("Opening.")])
        #expect(document.sections == [.init(heading: "Later", blocks: [])])
    }
}

struct MemoryUseTests {
    private func memory(pinned: Bool, excluded: Bool) -> Memory {
        Memory(id: UUID().uuidString, category: "general", content: "x", status: .approved,
               pinned: pinned, excluded: excluded, source: "user", createdAt: .now)
    }

    @Test func pinnedIsAlwaysAndExcludedIsNever() {
        #expect(MemoryUse(memory(pinned: true, excluded: false)) == .always)
        #expect(MemoryUse(memory(pinned: false, excluded: true)) == .never)
        #expect(MemoryUse(memory(pinned: false, excluded: false)) == .normally)
    }
}
