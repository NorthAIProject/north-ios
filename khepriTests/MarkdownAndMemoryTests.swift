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
