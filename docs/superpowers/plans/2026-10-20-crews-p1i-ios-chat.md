# Crews P1i: iOS crew chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Members can chat in their crews from the iPhone. The phone gets live messages, replies, reactions, pins, unread badges and crew pushes with inline reply. It also gets the four things Apple 1.2 requires before any user content ships: crew rules accepted before the first post, report on every message, block from the message and the member, and the server-side filter (already live).

**Architecture:**
- A `CrewChatService` wraps the P1 endpoints that are on north-client main `5464d0c5`.
- A `CrewLiveStream` turns `GET /crews/{id}/live` into typed events. It reconnects while the screen is in front and reports every (re)connect as a resync.
- One `@Observable CrewChatStore` per open channel holds messages keyed by id, the `after` cursor, and pending sends. Views stay thin.
- `CrewsScreen` now opens a `CrewSpaceScreen` with a Chat | Challenge picker. The Challenge tab is today's `CrewBoardView`.
- Pushes and badges hang off a small `CrewUnread` model in the environment.

**Tech Stack:**
- SwiftUI (iOS 26.2, `@Observable`, MainActor default isolation)
- swift-openapi-generator (`NorthKit/NorthAPI`)
- Swift Testing for unit tests, XCTest for UI tests

**Spec:** `/Users/fernandocorreiachill/.claude/plans/groups-discord-like-servers-with-parallel-brook.md`, phase P1 (the "P1i" row, plus "Realtime", "Moderation" and "UX › iOS"). Read the server contract in north-client `docs/api/openapi.yaml` at `5464d0c5`; its descriptions are binding.

## Global Constraints

- **Apple 1.2.** No build that shows crew chat may ship without terms-before-first-post, report on every message, and block from the message menu and the member list. All of them land in this one branch. The branch must not merge to main half-done.
- **Closed enums.** Never switch exhaustively on server strings. Message `kind` (`text`, `system`; anything else shows "Update Khepri to see this"), channel `kind` (`text`; hide others), live `type`, `notify` and report reasons are open strings. Unknown values are skipped or shown as a placeholder and must never fail decoding.
- **The push category string is exactly `CREW_MESSAGE`.** It must match the server, or the inline Reply action silently disappears (see the CHECKIN precedent).
- **Reaction keys:** `fire`, `muscle`, `clap`, `heart`, `laugh`, `hundred`, `trophy`, `eyes`, in that order. Glyphs: 🔥 💪 👏 ❤️ 😂 💯 🏆 👀.
- **Report reasons:** `spam`, `harassment`, `hate`, `sexual`, `violence`, `self_harm`, `other`, with an optional note.
- **Copy matches the web.** Use the English strings from north-client `internal/shared/i18n/en_crews.go` (`crews.*`, `moderation.terms.*`) as the xcstrings source text, and the web's es/pt-PT/pt-BR wording for the translations. `scripts/check-translations.py` must pass.
- **The live stream is open only while the crew screen is in front.** Every (re)connect is a resync, because nothing is replayed (openapi `streamCrewLive`).
- **Every send carries a `clientId` UUID,** reused on retry, so a resent message is stored once.
- **Tests never hit a real server or key.** Stub with `ClientTransport` fakes (`RecordingTransport`, `StatusTransport`) or protocol fakes.
- **Keep SwiftLint at 0 errors,** or local `xcodebuild` breaks.
- **This branch never touches the main checkout** (`north-ios-app/khepri`), which holds the release session's uncommitted work. Work only in `.worktrees/ios-crews-p1i`. Merging to main ships to the beta lane only; an App Store build is a separate, approved dispatch.

## Review Focus

1. **App backgrounded mid-chat, then foregrounded after others posted, edited or deleted.** The stream closes in the background. On return the channel shows the gap exactly once, with edits and deletes applied. (Task 4: `foregroundResyncs`.)
2. **A send that fails (offline or 5xx), then Retry.** One message is stored, and the failed bubble turns into the real one. (Task 4: `retryReusesClientID`.)
3. **Blocking the author of a message you are reading.** Their messages leave the open channel immediately, without a relaunch. (Task 4: `blockReloadsChannel`.)
4. **Being removed from the crew while the channel is open.** The screen closes with "You're no longer in this crew", and that crew's unread badge clears. (Task 4: `removedClosesChannel`; Task 7: `unreadDropsRemovedCrew`.)
5. **A push for the channel already on screen.** No banner. A push for any other channel still shows. (Task 7: `suppressesOnlyOpenChannel`.)

---

### Task 1: Sync the P1 API, decode the goldens, carry the error code

**Files:**
- Modify: `NorthKit/Sources/NorthAPI/openapi.yaml` and `NorthKit/Tests/NorthAPITests/golden/*` (via the sync script)
- Modify: `NorthKit/Tests/NorthAPITests/ContractTests.swift` (decode tests; `covered` set at ~:455)
- Modify: `NorthKit/Sources/NorthAPI/APIError.swift` (`ErrorDetail` ~:179, mapping ~:125)
- Test: `NorthKit/Tests/NorthAPITests/MiddlewareTests.swift`

**Interfaces:**
- Produces: the generated `Components.Schemas.CrewSpace`, `CrewChannel`, `CrewMessage`, `CrewMessagePage`, `CrewMessageList`, `CrewQuote`, `CrewReaction`, `CrewPerson`, `CrewUnread(List)`, `CrewLiveEvent`, `CrewSendMessage`, `CrewEditMessage`, `CrewReadRequest`, `CrewReportRequest`, `CrewNotifyRequest`, `ModerationTerms`, and every crew-chat operation id listed in the spec.
- Produces: a new `APIError.refused(code: String, message: String)` for a 403 whose `ErrorDetail.code` is non-empty. Its `errorDescription` is the message.

- [ ] **Step 1: Sync from server main.**
  - Run `git -C ../../north-client worktree add --detach /tmp/north-client-main origin/main` (after a fetch).
  - Then run `NORTH_WEB_APP=/tmp/north-client-main scripts/sync-openapi.sh`.
  - Afterwards, `scripts/sync-openapi.sh --check` with the same env exits 0.
- [ ] **Step 2: Write failing decode tests.**
  - In `ContractTests.swift`, add `crewSpaceGoldenDecodes` and `crewMessagesGoldenDecodes`.
  - They decode `crew-space.golden.json` → `CrewSpace` and `crew-messages.golden.json` → `CrewMessagePage`.
  - Assert at least one channel with `default == true`, and a message with non-empty `reactions`, or a `replyTo`, whichever the golden carries (read it).
  - Add both files to `covered`.
- [ ] **Step 3: Write a failing middleware test.**
  - `refusedCarriesCode`: a `CannedTransport` returning 403 `{"error":{"message":"Accept the crew rules to post.","code":"terms_required"}}`.
  - The call throws `.refused(code: "terms_required", message: "Accept the crew rules to post.")`.
  - A 403 without `code` still maps to `.server(message)`.
- [ ] **Step 4: Run** `cd NorthKit && xcodebuild test -scheme NorthKit-Package -skipPackagePluginValidation -destination 'platform=iOS Simulator,name=iPhone 17'`. Expected: the new tests FAIL (missing case / not covered). Any golden test not yet written also fails.
- [ ] **Step 5: Implement.**
  - Add `code: String?` to `ErrorDetail`.
  - Add the `.refused` case.
  - Fix any exhaustive `switch` over `APIError` that the compiler reports, in the app and the package.
- [ ] **Step 6: Run** the same command; expected PASS. Then run the app unit tests (CI command in "Verification") — the sync must not break existing decodes.
- [ ] **Step 7: Commit** `API: sync crew chat endpoints from server main; refused errors carry their code`.

### Task 2: CrewChatService

**Files:**
- Create: `khepri/Features/Crews/Chat/CrewChatService.swift`
- Test: `khepriTests/CrewChatServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces the protocol below.

```swift
typealias CrewSpace = Components.Schemas.CrewSpace
typealias CrewChannel = Components.Schemas.CrewChannel
typealias CrewMessage = Components.Schemas.CrewMessage

protocol CrewChatServicing: Sendable {
    func space(_ crewID: String) async throws -> CrewSpace
    func messages(_ crewID: String, channel: String, before: Int64?, after: Int64?) async throws -> Components.Schemas.CrewMessagePage
    func message(_ crewID: String, id: String) async throws -> CrewMessage
    func send(_ crewID: String, channel: String, body: String, replyTo: String?, clientID: UUID) async throws -> CrewMessage
    func edit(_ crewID: String, id: String, body: String) async throws -> CrewMessage
    func delete(_ crewID: String, id: String) async throws
    func react(_ crewID: String, id: String, emoji: String, on: Bool) async throws
    func pin(_ crewID: String, id: String, on: Bool) async throws
    func pins(_ crewID: String, channel: String) async throws -> [CrewMessage]
    func markRead(_ crewID: String, channel: String, seq: Int64) async throws
    func report(_ crewID: String, id: String, reason: String, note: String?) async throws
    func setNotify(_ crewID: String, notify: String, mutedUntil: Date?) async throws
    func unread() async throws -> Components.Schemas.CrewUnreadList
    func termsAccepted() async throws -> Bool
    func acceptTerms() async throws
    func block(_ userID: String) async throws
    func live(_ crewID: String) async throws -> HTTPBody   // text/event-stream
}
```

- [ ] **Step 1: Write failing tests** with `RecordingTransport` (see `CoachTests.swift:180`):
  - `sendCarriesClientID`: posts to `/crews/c1/channels/ch1/messages` and the recorded body contains `"clientId":"<uuid>"`.
  - `reactUsesKeyPath`: `PUT …/messages/m1/reactions/fire` for on, `DELETE` for off.
  - `messagesAfterQuery`: `after=41` and no `before`.
  - `liveAcceptsEventStream`: the request's `Accept` is `text/event-stream` (the retry middleware skips it).
- [ ] **Step 2: Run** the app unit tests filtered to `CrewChatServiceTests`; expected FAIL (type missing).
- [ ] **Step 3: Implement** `struct CrewChatService: CrewChatServicing` in the `CrewsService` style: `var api: Client = API.shared`, every call in `NorthAPI.call`. `block` calls the existing `api.block(path:)`.
- [ ] **Step 4: Run**; expected PASS.
- [ ] **Step 5: Commit** `Crews chat: service for space, messages, reactions, pins, reads, reports, terms and live`.

### Task 3: CrewLiveStream

**Files:**
- Create: `khepri/Features/Crews/Chat/CrewLiveStream.swift`
- Test: `khepriTests/CrewLiveStreamTests.swift`

**Interfaces:**
- Consumes: `CrewChatServicing.live`.
- Produces:

```swift
enum CrewLiveEvent: Equatable {
    case connected                       // first connect and every reconnect: treat as resync
    case message(channelID: String, seq: Int64)
    case update(messageID: String)
    case channels
    case removed(userID: String)
    case resync
}
struct CrewLiveStream {
    init(crewID: String, service: CrewChatServicing, backoff: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(10)])
    func events() -> AsyncStream<CrewLiveEvent>   // ends when the consuming Task is cancelled
    static func decode(_ frame: ServerSentEvent) -> CrewLiveEvent?   // nil for unknown types, pings, bad JSON
}
```

- [ ] **Step 1: Write failing tests.**
  - `decodesKnownFrames`: one test per type, using the payload shape from `CrewLiveEvent` in the spec.
  - `ignoresUnknownAndPings`: `type: "poll"` and a comment-only frame return nil.
  - `reconnectEmitsConnectedAgain`: a fake service whose first `live` body ends after one `message` frame and whose second blocks. The collected events start with `[.connected, .message(…), .connected]`, with backoff injected as `[.zero]`.
- [ ] **Step 2: Run**; expected FAIL.
- [ ] **Step 3: Implement.**
  - Loop: open, then yield `.connected`, then `for try await frame in body.asDecodedServerSentEvents()` and yield the decoded events.
  - On end or error, sleep the next backoff step (stay on the last one), then reopen.
  - A 404 or `.refused` from `live` ends the stream with `.removed(userID: "")`.
  - `Task.isCancelled` ends the loop.
  - Mirror `CoachService.events` (`:110`) for body handling.
- [ ] **Step 4: Run**; expected PASS.
- [ ] **Step 5: Commit** `Crews chat: live stream that reconnects and resyncs on every connect`.

### Task 4: CrewChatStore

**Files:**
- Create: `khepri/Features/Crews/Chat/CrewChatStore.swift`
- Test: `khepriTests/CrewChatStoreTests.swift` (with `FakeCrewChat: CrewChatServicing`)

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces:

```swift
@Observable final class CrewChatStore {
    struct Pending: Identifiable { let id: UUID; var body: String; var replyTo: String?; var failed: Bool }
    init(crewID: String, channelID: String, meID: String, service: CrewChatServicing)
    private(set) var rows: [CrewMessage]           // oldest first, unique by id, ordered by seq
    private(set) var pending: [Pending]
    private(set) var hasOlder: Bool
    private(set) var needsTerms: Bool              // drives the rules sheet
    private(set) var closedReason: String?         // non-nil → the screen pops with this text
    private(set) var error: String?
    var replyTo: CrewMessage?
    func load() async                               // newest page; sets the cursor
    func loadOlder() async
    func handle(_ event: CrewLiveEvent) async
    func send(_ body: String) async
    func retry(_ id: UUID) async
    func acceptTermsAndResend() async
    func edit(_ m: CrewMessage, body: String) async
    func delete(_ m: CrewMessage) async
    func toggle(_ emoji: String, on m: CrewMessage) async
    func setPinned(_ m: CrewMessage, _ on: Bool) async
    func report(_ m: CrewMessage, reason: String, note: String?) async   // hides it locally at once
    func block(authorOf m: CrewMessage) async                            // then reloads
    func markRead() async                                                // POST read with the cursor
}
```

**Rules the tests pin:**
- Fetches after the cursor are serialised. One runs at a time; another request while one is in flight sets a "fetch again" flag instead of starting a parallel fetch (the web's duplicate-row bug).
- A merge replaces by id and re-sorts by `seq`.
- `.message` for another channel does nothing here; `CrewUnread` (Task 7) handles it.
- `.update` refetches that one message.
- `.removed` with `meID` sets `closedReason`.
- `.connected` and `.resync` reload the newest page and keep `pending`.

- [ ] **Step 1: Write failing tests:**
  - `mergeIsUniqueAndOrdered`: two overlapping `after` pages give unique, `seq`-ordered rows.
  - `overlappingSignalsFetchOnceMore`: three `.message` events during one slow fetch cause exactly two fetches.
  - `foregroundResyncs`: after `.connected`, edits and deletes from the fake are reflected with no duplicates.
  - `retryReusesClientID`: the first send throws `.server`, `retry` sends with the same UUID, the fake stores one message, `pending` is empty, and the row is present.
  - `termsRequiredOpensRules`: send throws `.refused(code: "terms_required", …)`, so `needsTerms == true` and the pending item is kept. `acceptTermsAndResend` calls `acceptTerms` then sends with the same UUID.
  - `suspendedShowsMessage`: `.refused(code: "suspended", …)` sets `error` and leaves `needsTerms` false.
  - `reportHidesAtOnce`: the reported row leaves `rows` before the fake returns.
  - `blockReloadsChannel`: after `block`, `load()` ran and the author's rows are gone (the fake filters them like the server).
  - `removedClosesChannel`.
  - `unknownKindKeptAsPlaceholder`: a message with `kind: "poll"` stays in `rows` (the view renders a placeholder) and decoding never fails.
- [ ] **Step 2: Run**; expected FAIL.
- [ ] **Step 3: Implement.** The `after` cursor is the max `seq` seen.
- [ ] **Step 4: Run**; expected PASS.
- [ ] **Step 5: Commit** `Crews chat: channel store with live merge, retries, rules, report and block`.

### Task 5: One composer for coach and crews

**Files:**
- Create: `khepri/Core/UI/ChatComposer.swift` (moved from the private `Composer` at `Features/Coach/ConversationView.swift:323`)
- Modify: `Features/Coach/ConversationView.swift`

**Interfaces:**
- Produces:

```swift
ChatComposer<Attachments: View>(
    text: Binding<String>,
    placeholder: LocalizedStringKey,
    isBusy: Bool,
    canSend: Bool,
    focused: FocusState<Bool>.Binding,
    dictation: Bool = true,
    onAttach: (() -> Void)? = nil,
    onSend: () -> Void,
    onStop: (() -> Void)? = nil,
    @ViewBuilder attachments: () -> Attachments
)
```

The accessibility id stays `composer`.

- [ ] **Step 1:** Move the composer and generalise it as above. With `onAttach == nil` there is no paperclip; with `onStop == nil` there is no stop toggle. The coach passes today's values ("Message your coach", attach, stop).
- [ ] **Step 2: Verify.**
  - Build the app.
  - Run the existing coach unit tests.
  - Run `khepriUITests/CoachUITests` against a local server (see Verification).
  - Expected: unchanged behaviour, and the `composer` id is still found.
- [ ] **Step 3: Commit** `Coach: composer moves to Core/UI so crews can use it`.

### Task 6: Crew space, channel and moderation UI

**Files:**
- Create in `khepri/Features/Crews/Chat/`:
  - `CrewSpaceScreen.swift`
  - `ChannelView.swift`
  - `CrewMessageRow.swift`
  - `CrewRulesSheet.swift`
  - `CrewReportSheet.swift`
  - `CrewPinsSheet.swift`
  - `CrewNotifySheet.swift`
- Modify: `khepri/Features/Crews/CrewsScreen.swift`
  - The list opens `CrewSpaceScreen` instead of `CrewBoardView`.
  - `CrewBoardView` becomes the Challenge tab.
  - Member rows gain a "Block" swipe and context action (not on yourself), behind a confirmation.
  - Replace the "up to eight" copy at :22 and "of up to 8" at :135 with copy that names no number: "A crew is a small group who keep each other going." and "Anyone with the link can join."
- Modify: `khepri/Resources/Localizable.xcstrings` (all new keys, 4 languages)
- Test: `khepriTests/CrewMessageRowTests.swift`

**Decisions:**
- **CrewSpaceScreen.** A segmented Chat | Challenge picker in the navigation bar. In Chat, a toolbar menu titled `#<channel>` lists the text channels with unread counts and opens the default channel first. Toolbar items: Pins and Notifications (a bell opens `CrewNotifySheet`, with All / Mentions and replies / Nothing and mute Off / 1 hour / 1 day / 1 week). It owns the `CrewLiveStream` task through `.task(id: scenePhase)`: run only when `.active`, cancel otherwise. It forwards events to the open channel's store and to `CrewUnread`. `closedReason` pops back to the list with an alert.
- **ChannelView.**
  - Built like `ConversationView`: `ScrollViewReader`, bottom sentinel, `.defaultScrollAnchor(.bottom)`, `.scrollDismissesKeyboard(.interactively)`, `.toolbar(.hidden, for: .tabBar)`.
  - A "Load older messages" button at the top when `hasOlder`.
  - `ChatComposer` with placeholder `Message #<name>`, no dictation, no attach.
  - A reply bar above the composer showing "Replying to <name>" and a cancel button.
  - `markRead` runs on appear, after each live append while active, and on scene `.active`.
- **CrewMessageRow.**
  - Avatar initial, name, time, then the body.
  - `@handle` runs are highlighted in `NorthColor.signal`; `mentionsMe` rows get a subtle signal tint.
  - A `(edited)` suffix.
  - Deleted messages show "This message was deleted.", and an unavailable quote shows "This message isn't available.".
  - Pills for each reaction with its count, filled when `mine`.
  - A quote block for `replyTo`.
  - A "Pinned" label.
  - `kind` other than `text` or `system` renders "Update Khepri to see this".
  - Swipe right to reply.
  - `contextMenu` items:
    - React: the 8 emoji, in a `ControlGroup`
    - Reply
    - Copy
    - Edit and Delete: own messages only; Delete also for owner/admin
    - Pin/Unpin: owner/admin only
    - Report: others' messages
    - Block <name>: others' messages, behind a confirmation
- **CrewRulesSheet.** Title, body and an "I agree" button use the `moderation.terms.*` web copy. It is presented when `needsTerms`. Agreeing calls `acceptTermsAndResend`. Dismissing keeps the draft. It has no "Not now" button (Apple rejected a skippable primer before).
- **CrewReportSheet.** The 7 reasons as a list, an optional note, "Send report", and the explanatory text "The message disappears for you right away, and we review every report."

- [ ] **Step 1: Write failing tests** in `CrewMessageRowTests.swift` for the pure helpers the row uses:
  - `glyphForKeys`: all 8 keys map to their glyphs and an unknown key maps to nil.
  - `mentionRunsHighlight`: `"lift with @ana and @leo"` gives 2 highlighted runs.
  - `actionsForRole`: a member sees no Pin, the admin sees Pin, the author sees Edit, and others see Report and Block.

  Put these helpers in a `CrewMessageActions` / `CrewEmoji` file beside the row so they are testable.
- [ ] **Step 2: Run**; expected FAIL.
- [ ] **Step 3: Implement** the views and helpers. Add every new string to the xcstrings in en, es, pt-PT and pt-BR, using the web wording.
- [ ] **Step 4: Run** the unit tests and `python3 scripts/check-translations.py`; expected PASS and no missing keys. Build with lint at 0 errors.
- [ ] **Step 5: Commit** `Crews: crew space with chat, rules, report, block, pins and notification settings`.

### Task 7: Unread badges, deep links and crew pushes

**Files:**
- Create: `khepri/Features/Crews/Chat/CrewUnread.swift`, `khepri/Core/Notifications/CrewNotifications.swift`
- Modify:
  - `khepri/App/AppRouter.swift`: parse `/app/crews/<uuid>/c/<uuid>` and `/app/crews/<uuid>` before the `sections` fallback at ~:251
  - `khepri/App/AppDelegate.swift`: register the category, `willPresent`, `didReceive`
  - `khepri/Features/Shell/MainTabView.swift`: a More badge
  - `khepri/Features/More/MoreScreen.swift`: a Crews row badge, and open a crew/channel route
  - `khepri/Features/Crews/CrewsScreen.swift`: a per-crew unread badge
  - `khepri/khepriApp.swift`: inject `CrewUnread`
- Test: `khepriTests/CrewNotificationsTests.swift`, `khepriTests/ShellTests.swift` (link parsing)

**Interfaces:**

```swift
@Observable final class CrewUnread {
    private(set) var total: Int
    private(set) var byCrew: [String: (unread: Int, mentions: Int)]
    func refresh() async                   // GET /crews/unread
    func clear(crewID: String)
}
enum CrewNotifications {
    static let category = "CREW_MESSAGE"
    static let replyAction = "CREW_REPLY"
    static func target(href: String) -> (crewID: String, channelID: String)?
    static func shouldPresent(href: String?, open: (crewID: String, channelID: String)?) -> Bool
    static var openChannel: (crewID: String, channelID: String)?   // set by ChannelView on appear, cleared on disappear
    static func clientID(for notificationID: String) -> UUID      // stable per notification, so a retried inline reply is stored once
}
// AppRouter: case crewChannel(crewID: String, channelID: String?)
```

- [ ] **Step 1: Write failing tests:**
  - `targetParsesHref`: `/app/crews/<a>/c/<b>` gives `(a, b)`; `/app/nudges/x` gives nil.
  - `suppressesOnlyOpenChannel`: same crew and channel gives false; another channel gives true; nil `open` gives true.
  - `clientIDIsStable`: the same notification id gives the same UUID, and different ids give different UUIDs. Use a UUIDv5-style hash of the id, not random.
  - `unreadDropsRemovedCrew`: after `clear(crewID:)`, `total` falls by that crew's count.
  - In `ShellTests`: `crewChannelLinkRoutes` and `crewLinkRoutes`.
- [ ] **Step 2: Run**; expected FAIL.
- [ ] **Step 3: Implement.**
  - Register `UNNotificationCategory(identifier: "CREW_MESSAGE", actions: [UNTextInputNotificationAction(identifier: "CREW_REPLY", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Message")])` next to the existing categories.
  - `willPresent`: return `[]` when `!shouldPresent(...)`; otherwise keep today's behaviour.
  - `didReceive` with `CREW_REPLY`: send through `CrewChatService` inside `BackgroundActivity.run`, with `clientID(for: response.notification.request.identifier)`. A tap opens the route.
  - `CrewUnread.refresh()` runs on scene `.active`, on any crew push, and when a crew screen disappears.
  - The More tab uses `.badge(total)`.
- [ ] **Step 4: Run**; expected PASS.
- [ ] **Step 5: Commit** `Crews: unread badges, crew links and pushes with inline reply`.

### Task 8: UI test, seed and the two-device check

**Files:**
- Create: `scripts/seed-crews-uitest.sh` (style of `seed-coach-uitest.sh`).
  - It creates the owner `crewowner@crew.test` (accepts terms, creates "Iron rats", posts 3 messages) and the joiner `crewjoiner@crew.test` (joins, has NOT accepted terms).
  - It prints the `export TEST_RUNNER_CREW_*` lines.
- Create: `khepriUITests/CrewChatUITests.swift`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Write the UI test** `testChatRulesReportBlock`, signed in as the joiner:
  1. More › Crews › Iron rats.
  2. Chat shows the 3 seeded messages.
  3. Typing "hi" and sending presents the rules sheet; "I agree" makes "hi" appear.
  4. Long-pressing a seeded message › Report › Spam › Send report removes the message.
  5. Long-pressing another › Block Owner › confirm leaves no Owner messages.
- [ ] **Step 2: Run it against a local server** built from north-client `origin/main` with `AI_PROVIDER_CHAIN=fake` (follow the `north-ios-ui-testing` recipe: rebuild the server first, reset the simulator). Fix until it PASSES.
- [ ] **Step 3: Manual check** with the simulator plus web (the second member):
  - A web message reaches the phone in under 1 s.
  - A phone message reaches the web.
  - Reactions and edits propagate.
  - Background the app, post from the web, foreground: the gap appears once.
  - Removing the phone user from the web closes the screen.
  - Push is not checked on the simulator, since APNs needs a device. Say so.
  - Screenshots in light and dark.
  - Report honestly what was and wasn't checked.
- [ ] **Step 4: Commit** `Crews: chat UI test, seed script and changelog`.

## Verification (every task)

- **Unit tests:** `xcodebuild test -project khepri.xcodeproj -scheme khepri -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:khepriTests -skipPackagePluginValidation -parallel-testing-enabled NO -quiet` (the CI command).
- **Package tests:** `cd NorthKit && xcodebuild test -scheme NorthKit-Package -skipPackagePluginValidation -destination 'platform=iOS Simulator,name=iPhone 17'`.
- **Lint:** 0 errors (the build phase). If `ENABLE_USER_SCRIPT_SANDBOXING` blocks it in a worktree, set it to NO locally and never commit that.
- **Checks:** `python3 scripts/check-translations.py` and `scripts/sync-openapi.sh --check` (with `NORTH_WEB_APP` set as in Task 1).
- **Rebase:** before the PR, rebase on `origin/main`. The release session may land `Localizable.xcstrings` changes, so resolve that file by re-adding our keys, never by taking one side wholesale.
