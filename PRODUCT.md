# Product

Adapted from `north-web-app/PRODUCT.md`. Web and iOS are the same product; keep the two files in step.

## Register

product

## Users

People working on their own training, nutrition, sleep and mood who want one coach that remembers them. On iOS they are on a phone, often one-handed and mid-activity: in the gym between sets, in the kitchen logging a meal, in bed answering a check-in, or glancing at a widget or notification. Sessions are short and task-shaped ("what do I do today?", "log this", "how was my week?"), with occasional longer reads (reports, knowledge, insights) and voice when hands are busy.

## Product Purpose

Khepri is an operating system for personal growth: one AI coach with one long-term memory across web, iOS, Telegram and MCP. It holds goals, training, nutrition plans, photos, documents and every check-in, and turns them into plans, nudges and insights. Success is a user who comes back daily because the coach already knows the context, not because the app nags.

The iOS app is the capture-first surface: Today, the coach, training sessions, check-ins, Apple Health, widgets, Siri and notifications. The signed-out landing, sign-in and onboarding screens follow the brand register; everything behind sign-in is product.

## Brand Personality

Precise, calm, knowledgeable. A sports scientist with a long memory: data-led, quiet confidence, never hype. Motto "A brighter you": optimism is carried by the solar brand (navy and gold, winged emblem, Marcellus wordmark), not by exclamation marks. The coach speaks plainly, cites what it knows about the user, and admits uncertainty.

## Anti-references

- Gym-bro energy: neon on black, flames, aggressive streak shaming, all-caps motivational copy.
- Gamified wellness clutter: confetti on every action, badges as decoration, points everywhere.
- Generic SaaS dashboards: hero-metric tiles, identical card grids, gradient accents.
- Chatbot-first UIs where everything is a chat bubble and the data is hidden.
- The default SwiftUI tutorial stack: white `cornerRadius` cards with a drop shadow, a `List` for everything, system blue as the only brand expression.

## Design Principles

1. **The instrument, not the show.** Data and the user's own words lead; chrome recedes. Every colour and motion has a job (signal, coach, effort).
2. **Memory is visible.** Show what the coach knows and why it suggests something; context beats cleverness.
3. **Earned familiarity.** Standard iOS affordances, one component vocabulary across all screens; delight is saved for moments (a finished week, a recap), not pages.
4. **Calm by default.** No urgency theatre; nudges are rare, specific and dismissible.
5. **Same product everywhere.** Web and iOS share tokens and words; a feature should feel like the same coach on both.

## Accessibility & Inclusion

WCAG 2.2 AA contrast: 4.5:1 body text, 3:1 large text and UI edges. Dynamic Type through the accessibility sizes without clipped or truncated primary content. VoiceOver labels on every control and non-decorative symbol. 44x44pt minimum touch targets. Reduce Motion honoured on every animation that is not strictly informative. Four locales (en, es, pt-PT, pt-BR), so layouts must survive ~30% longer strings and decimal commas. Light, Dark and System appearance all supported.
