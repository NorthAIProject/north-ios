# Changelog

What each App Store build of Khepri contains. TestFlight beta builds (the
separate `.beta` app) ship every merge to `main` and are not listed here.

## 1.0.3 — fix for the launch crash on iOS 26

- **Opens again on iOS 26.** 1.0.2 (22) closed at launch on every iPhone
  running iOS 26: it was built with Xcode 27, and swift-collections, compiled
  by that toolchain, needed `swift_initBorrow`, a Swift runtime function only
  iOS 27 has. dyld refused to load the app before any of its code ran, so no
  crash reporter could see it. The 1.0.1 (14) archive has the same import.
  iOS 27 was unaffected, which is why it never showed on an iOS 27 phone.
- Uploads are built with Xcode 26.3 again, the Xcode the tests use.
- `scripts/min-ios-symbol-guard.sh` checks every Mach-O in the app against the
  oldest supported iOS runtime; CI runs it after the test build and fastlane
  runs it on every archive before upload.

## 1.0.2 — submitted 2026-11-24

The first build submitted since 1.0 (16) was withdrawn: `main` at the time of
submission, with everything listed under 1.0.1 and 1.0 below. Neither of those
versions was submitted on its own. Crew chat ships here together with the crew
rules, reporting and blocking (guideline 1.2).

## 1.0.1 — never submitted (shipped in 1.0.2)

- **Crew chat**: each crew has channels with live messages, replies,
  reactions, edits, pins and @mentions, unread badges on More, Crews and each
  crew, and per-crew notifications with an inline Reply. The crew rules are
  agreed before the first post; every message can be reported, and its author
  blocked from the message menu or the member list.

## 1.0 — never submitted (shipped in 1.0.2)

Version 1.0 was withdrawn from review (Developer Rejected) with build 16
attached; these changes came after it.

- **Meal plans built with AI** (#72): Nutrition › Plans › Build with AI. Goal,
  number of days, meals per day, carb level, foods to leave out and notes; the
  plan is fitted to the macro target and reviewed before saving.
- **Training weekdays** (#72): pick which days you train; plans keep each
  session within the time you have.
- **Progress checks** (#76): front, side and back photos with measurements,
  a reminder cadence, first-vs-latest comparison, and Today's body figure
  shaped by the latest check (outline-only skin).
- **Quick coach** (#93): hold the orb on Today and speak, or type; the reply
  appears over Today and is read aloud if you spoke. Each visit is a normal
  Coach chat.
- **Coach messages first** (#73): a lighter session on low recovery (with
  Undo) or a missed session moved, answered from the notification or Today.
- **Your week** (#71): 7 / 30 day recap, share image, post to friends.
- **Daily Post** (#75): one AI-written wellbeing post a day under More, with
  kudos and Ask the Coach.
- **Languages** (#68): Spanish, European and Brazilian Portuguese, and one
  Language setting.
- **Appearance** (#70): Light, Dark or System, saved to the account.
- **Optional meals** (#66), **knowledge reader** (#65), **styled coach
  reports** (#64), **body figure inside a translucent skin** (#67).
- Fixes: light/dark legibility of buttons (#69), background form-check
  uploads and the post-reboot unlock wait (#63).

## 1.0 (16) — submitted 2026-10-10, withdrawn

- Chat attachments, meal options, background and Lock Screen fixes (#56, #62).
- Permission explainers with a single Continue button (5.1.1(iv)).

## 1.0 (1–15)

First submissions: coach with memory, training plans with animated exercises,
check-ins, goals, water, sleep, habits, meals, journal, decisions, friends and
crews, Apple Health and Strava, widgets and Siri capture.
