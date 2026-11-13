---
name: Khepri
description: One AI coach with one long memory. Warm paper and deep navy, gold where it matters.
colors:
  accent: AccentColor
  signal: Signal
  agent: Agent
  ember: Ember
  destructive: Destructive
  background: Background
  surface: Surface
  card: Card
  foreground: Foreground
  muted-foreground: MutedForeground
  primary: Primary
  primary-foreground: PrimaryForeground
  hairline: Hairline
  border: Border
  sport-run: SportRun
  sport-ride: SportRide
  sport-swim: SportSwim
  sport-walk: SportWalk
  sport-strength: SportStrength
  day-water: DayWater
  day-sleep: DaySleep
  day-food: DayFood
  day-move: DayMove
typography:
  display:
    fontFamily: "Marcellus, serif"
    fontSize: "largeTitle"
    fontWeight: 400
    letterSpacing: "0.5"
  title:
    fontFamily: "Geist"
    fontSize: "title2"
    fontWeight: 600
  body:
    fontFamily: "Geist"
    fontSize: "body"
    fontWeight: 400
  label:
    fontFamily: "Geist"
    fontSize: "caption"
    fontWeight: 500
    letterSpacing: "1.5"
  number:
    fontFamily: "Geist"
    fontSize: "largeTitle"
    fontWeight: 600
  chrome:
    fontFamily: "SF Pro"
    fontSize: "body"
    fontWeight: 400
rounded:
  small: "6"
  medium: "10"
  control: "12"
  large: "16"
spacing:
  xs: "4"
  sm: "8"
  md: "12"
  lg: "16"
  xl: "20"
  xxl: "24"
components:
  button-prominent:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.primary-foreground}"
    typography: "{typography.chrome}"
  surface-card:
    rounded: "{rounded.large}"
    padding: "20"
  card:
    rounded: "{rounded.medium}"
    padding: "16"
  inset-list:
    rounded: "{rounded.control}"
    padding: "12 16"
  field:
    rounded: "{rounded.control}"
    padding: "14 16"
  social-button:
    rounded: "{rounded.control}"
    height: "50"
---

# Design System: Khepri

## 1. Overview

**Creative North Star: "The Instrument, Not the Show"**

Khepri reads like a well-made training log kept by someone who knows the science: warm paper in the light, deep navy at night, and a single gold that points at what matters. Data and the user's own words lead. Chrome recedes into system materials and semantic colours, so the app feels native first and branded second. The brand speaks in three places only: the coach, the sports and trackers, and the rare highlight.

Density is moderate and task-shaped. Today is a single scrolling column of cards, each one answering one question. Training, Settings and every editing surface are plain `List` and `Form`, because those are the honest affordances. Motion is `.snappy` and conveys state; nothing loops, nothing celebrates by default. Every animation checks `accessibilityReduceMotion`. At accessibility text sizes, side-by-side layouts stack.

This system rejects gym-bro energy (neon on black, flames, streak shaming, all-caps motivation), gamified wellness clutter (confetti, decorative badges), generic SaaS dashboards (hero-metric tiles, identical card grids, gradient accents), chatbot-first screens where the data hides behind bubbles, and the default SwiftUI tutorial stack of shadowed white cards.

**Key Characteristics:**

- Colour tokens are the web app's, generated from its CSS by `scripts/sync-theme.py`. Edit the CSS, never the catalog.
- System chrome, brand content: `List`, `Form`, toolbars and sheets stay stock.
- One gold accent, used for links, the Next badge, and the one prominent button.
- Flat surfaces separated by tone and a hairline, never by shadow.
- Geist for content, SF Pro for system controls, Marcellus for the wordmark and nothing else.

## 2. Colors

Warm off-white paper and deep navy ink, with antique gold as the only accent and a small set of muted functional hues.

### Primary / Accent

- **Solar Gold** (Color Sets: `AccentColor`, `Signal`, `Ring`; dark variant: yes): links, the Next badge, eyebrow highlights, progress gauges, the prominent button fill. Darkens to a bronze in Light so it holds 4.5:1 on paper.
- **Coach Blue** (Color Set: `Agent`; dark variant: yes): anything the coach says or does. Never used for user content.
- **Ember** (Color Set: `Ember`; dark variant: yes): warmth and streaks, and the top of the body-figure heat ramp. Below text contrast on white, so it colours marks and bars, never words.

### Background / Surface

- **Paper / Night** (Color Set: `Background`): brand backdrop for brand moments. Product screens use `Color(.systemBackground)` and the grouped backgrounds.
- **Card** (Color Sets: `Card`, `Surface`): brand card fill. Product cards use `Color(.secondarySystemBackground)` through `northSurfaceCard()` and `northCard()`.
- **Hairline** (Color Set: `Hairline`): the 0.5pt edge that holds a card apart from the page in Dark.

### Label / Text

- **Ink** (Color Set: `Foreground`): brand text. Product text uses `.primary`, `.secondary`, `.tertiary`.
- **Button Ink** (Color Set: `PrimaryForeground`): the label on the prominent button, chosen because the system's white label vanishes on light gold in Dark.

### Semantic / State

- **Brick** (Color Set: `Destructive`): errors, destructive confirmations, weak-password bars. Tinted at 10% opacity as a banner fill.
- **Sport hues** (`SportRun`, `SportRide`, `SportSwim`, `SportWalk`, `SportStrength`, `SportOther`): one per activity type, in charts and badges.
- **Day hues** (`DayWater`, `DayFood`, `DayProtein`, `DayCarb`, `DayFat`, `DayMove`, `DayExercise`, `DayStand`, `DaySleep`, `DayCaffeine`, `DaySun`, `DayScreen`, `DayNow`): one per tracker, shared by rings, gauges and timeline dots, identical to the web.

### Named Rules

**The Three Voices Rule.** Colour means signal (gold), coach (blue) or effort (ember and the sport and day hues). A colour that is none of these is decoration and is prohibited.

**The System Chrome Rule.** Navigation bars, lists, forms, sheets and their text use system semantic colours. `NorthColor` is for content the brand owns.

**The Catalog Rule.** No `Color(red:green:blue:)`, no hex, no `.white` or `.black` on a surface. Every colour is a `NorthColor` token or a system semantic colour.

## 3. Typography

**Display Font:** Marcellus (`Font.northDisplay(_:)`, bundled, one weight)
**Body Font:** Geist (`Font.north(_:)`, bundled variable font, sized from the system text style so it follows Dynamic Type)
**Numeric:** Geist with `.monospacedDigit()`; Geist Mono (`Font.northMono(_:)`) only for timers
**Chrome:** SF Pro through the stock text styles, inside `List`, `Form`, toolbars and auth controls

**Character:** A quiet geometric sans for content beside the platform's own face for controls, with a Roman-capital serif reserved for the name. The pairing says instrument, not magazine.

### Hierarchy

- **Display** (Marcellus, `largeTitle`, tracking 0.5): the wordmark on sign-in, a celebration, a recap headline. Never bold; it has one weight.
- **Title** (Geist semibold or bold, `title2`): the one statement a card makes, such as the next step or the plan name.
- **Briefing** (Geist medium, `title3`, line spacing 2): the coach's line for the day.
- **Body** (Geist regular or medium, `body`): row titles and prose. Cap prose at about 70 characters.
- **Supporting** (Geist regular, `subheadline` and `caption`, `.secondary`): details under a title.
- **Eyebrow** (Geist medium, `caption`, uppercase, tracking 1.5): `northEyebrow()`, the label above a value, a card or a group.
- **Number** (Geist semibold `largeTitle` or `title` via `NorthBigValue`; Geist light via `northDisplayNumber`): the figure a card is about, with tabular digits and `.contentTransition(.numericText())`.

### Named Rules

**The Dynamic Type Contract.** Every font call names a text style. `.font(.system(size:))` is prohibited for text and for symbols beside text. If a view clips at AX5, a font call or a fixed frame is wrong.

**The One Family Per Surface Rule.** Inside a card, every text is Geist. Inside a `List` or `Form` row, every text is SF Pro. Mixing the two in one row is drift.

**The Wordmark Rule.** Marcellus appears on brand moments only. It never sets a control, a label or a number.

## 4. Elevation

This system is flat by design. Depth comes from tone: a card is one grouped-background step above the page, an inset list is one step back down inside the card, and a 0.5pt `Hairline` stroke keeps the edge legible in Dark. There are no resting shadows. Navigation bars, tab bars and toolbars take the system's Liquid Glass untouched.

### Material Vocabulary

- **System bars** (stock iOS 26 glass): navigation, tab bar, toolbars. Never restyled.
- **Floating overlay** (`.regularMaterial`): the saving spinner over a list, the quick coach reply over Today, anything that genuinely floats over content. It is the only material tier in use.
- **Shadow** (two uses in the app, on the coach orb and the quick coach reply): reserved for objects that float free of the layout. Cards never cast one.

### Named Rules

**The No Shadow Rule.** Cards, rows and buttons do not cast shadows. If a surface needs separating, change its tone or add the hairline.

**The One Material Rule.** `.regularMaterial` is the only custom material. `.ultraThinMaterial` as a page or card background is prohibited.

## 5. Components

### Buttons

- **Prominent:** `northProminentButton()` (`NorthProminentButtonStyle`). `.borderedProminent` on the accent with a `PrimaryForeground` label; disabled, it keeps the system grey fill under a `.secondary` label. One per screen. Pair with `.controlSize(.large)`, and `.buttonBorderShape(.capsule)` inside a card.
- **Secondary:** stock `.bordered` or a plain tinted text button. No custom styles.
- **Loading:** an inline `ProgressView` replaces the label; the button stays its size and is disabled.
- **Destructive:** `role: .destructive` in swipe actions, menus and confirmation dialogs.
- **Social sign-in:** `SocialAuthButton`, 50pt minimum height, softly squared (12pt), `secondarySystemBackground` fill with a 0.5pt separator stroke. Google's four-colour mark is drawn as supplied and never tinted.

### Cards / Containers

- **Surface card:** `northSurfaceCard(padding:)`. Generous continuous corners (16pt), `secondarySystemBackground`, hairline stroke, 20pt padding (16pt for dense tiles).
- **Standalone card:** `northCard()`. Tighter corners (10pt), 16pt padding, no stroke.
- **Card header:** `NorthCardHeader`, an eyebrow with optional detail and a trailing action.
- **Inset list:** `NorthInsetList`, rows on a darker inset (12pt corners) with hairline dividers that start at the text.
- **Big value:** `NorthBigValue`, the number with its unit small beside it.
- **Nesting:** a card may hold one inset list. A card inside a card is prohibited.

### Inputs / Fields

- **Style:** `VaultTextField` on auth screens: leading symbol, `secondarySystemBackground` fill, 12pt continuous corners, 14pt by 16pt padding. Everywhere else, stock `Form` controls.
- **Focus:** a 1.5pt accent stroke, eased over 0.15s. Return moves to the next field and submits from the last.
- **Error:** inline under the field in `Destructive` at `caption`, or a banner tinted 10% `Destructive` with a filled warning symbol. Errors are announced to VoiceOver.

### Navigation

- `TabView` with five tabs (Today, Coach, Training, Progress, More), each a `NavigationStack`. Large titles on roots, inline titles on pushed screens.
- Secondary actions live in a toolbar `Menu` (`ellipsis.circle`). Creation flows are sheets; a live workout is a full-screen cover.
- Loading, failed and empty states: `ProgressView`, then `ContentUnavailableView` with `wifi.exclamationmark` and a Try Again button, or a `ContentUnavailableView` that names the first action.
- Session rows: `TrainingSessionRow`, weekday and badge leading, reminder time and count trailing; the trailing column moves under the text at accessibility sizes.

### SF Symbols usage

- **Rendering mode:** monochrome, tinted by the surrounding foreground style. Filled variants mark state (`checkmark.circle.fill`, `flame.fill`); outline variants mark actions.
- **Weight matching:** symbols take a text style and weight through `.font()`, so they scale and match adjacent text.
- **Recurring set:** `plus`, `trash`, `square.and.arrow.up`, `chevron.right`, `ellipsis.circle`, `sparkles` (AI), `figure.strengthtraining.traditional`, `figure.run`, `target`, `exclamationmark.triangle`, `wifi.exclamationmark`.
- **Badge:** `IconBadge`, a 44pt circle of `tertiarySystemFill` behind a semibold symbol, for timeline and fitness rows.

### Coach Orb

The one floating control: a brand orb at the bottom trailing corner of Today. Tap opens the coach, hold to speak. It is hidden during the tour and when AI is declined, and Today's scroll content is inset 88pt so the last card clears it.

### 3D Emblem

`Emblem3DView` shows the Khepri emblem as a RealityKit model on `LoginScreen`, in place of `NorthBrand.mark`. It is the one exception to "nothing loops" and to the brand rule against rotating or adding glow to the logo. The exception is limited to: a 600 ms entrance, a tilt toward a drag or hover (at most 8° yaw and 5° pitch), a ±12 % sun glow over 6 s, and a key light that sweeps the gold rules every 8 s. Values come from `emblem-motion.json`, a byte-for-byte copy of north-web-app `design/emblem-motion.json`. The flat mark shows until the first frame and stays under Reduce Motion and Low Power Mode. Promoted to every configuration, the App Store build included, on 2026-11-13 by the owner, before a device check.

### 3D Mascot

`Mascot3DView` shows the Khepri mascot as a RealityKit character on the onboarding `WelcomeStep`, in place of `KhepriMascot(.idle)`. The mascot is a character, so unlike the emblem it may blink and look. The exception is limited to: a 600 ms entrance; a slow hover (1.5 % of its height over 6 s); a ±15 % solar-core glow over 6 s; a scheduled blink (two per 7 s cycle, one a double blink, about 210 ms each); and a look toward a drag or hover, with the head at most 12° yaw and 6° pitch and the pupils following. Values come from `mascot-motion.json`, a byte-for-byte copy of north-web-app `design/mascot-motion.json` (ADR 0006 there). The flat mascot shows until the first frame and stays under Reduce Motion and Low Power Mode. Promoted to every configuration, the App Store build included, on 2026-11-13 by the owner, before a device check.

## 6. Do's and Don'ts

### Do:

- **Do** build a new card with `northSurfaceCard()`, `NorthCardHeader` and `northEyebrow()` before writing a background by hand.
- **Do** take radii from `NorthRadius` (`small` 6, `medium` 10, `control` 12, `large` 16) and spacing from the 4 / 8 / 12 / 16 / 20 / 24 scale.
- **Do** use `.north(_:)` for every text inside a card and stock text styles inside `List` and `Form`.
- **Do** format numbers, times and durations with `FormatStyle`, add `.monospacedDigit()`, and pluralise through the String Catalog.
- **Do** gate every animation on `accessibilityReduceMotion` and default to `.snappy`.
- **Do** give every icon-only button an `accessibilityLabel` and a 44pt hit area.
- **Do** stack side-by-side content when `dynamicTypeSize.isAccessibilitySize`.
- **Do** add every new string in en, es, pt-PT and pt-BR.

### Don't:

- **Don't** ship gym-bro energy: neon on black, flames, aggressive streak shaming, all-caps motivational copy.
- **Don't** ship gamified wellness clutter: confetti on every action, badges as decoration, points everywhere.
- **Don't** build generic SaaS dashboards: hero-metric tiles, identical card grids, gradient accents.
- **Don't** make chatbot-first screens where everything is a chat bubble and the data is hidden.
- **Don't** reach for the default SwiftUI tutorial stack: white `cornerRadius` cards with a drop shadow, a `List` for everything, system blue as the only brand expression.
- **Don't** use `Color(red:green:blue:)`, hex, `.white` or `.black` on a surface.
- **Don't** use `.font(.system(size:))`; it breaks Dynamic Type.
- **Don't** add a shadow to a card, or a material to anything that does not float.
- **Don't** set anything but the wordmark and brand moments in Marcellus, and never bold it.
- **Don't** put `Ember` on text over a light surface; it fails contrast.
- **Don't** edit `Theme.xcassets` by hand. Change the web CSS and run `scripts/sync-theme.py`.
- **Don't** use em dashes in copy.
