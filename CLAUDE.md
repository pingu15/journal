# Today: Daily Journal

A minimal, editorial journaling app. Native iOS: Swift 6 + SwiftUI, **iPhone only**, iOS 18+, default actor isolation = MainActor. No third-party dependencies, no analytics.

## Commands
```bash
# Build
xcodebuild -project Journal.xcodeproj -scheme Journal -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build

# Launch with sample data (DEBUG launch args below)
xcrun simctl launch booted com.maxsun.journal -seedSampleData

# Read the store (it lives in the App Group container)
sqlite3 "$(xcrun simctl get_app_container booted com.maxsun.journal group.com.maxsun.journal)/Library/Application Support/default.store" "select ZTEXT from ZENTRY"
```

DEBUG launch arguments:
- `-seedSampleData` — fill an empty store with `SampleJournal` (`Models/`): ~4 months of someone's life in New York, with places, weather, photos and the matching location history (place samples). With Photos access already granted (`xcrun simctl privacy booted grant photos com.maxsun.journal`) it also saves the photos to the Photos library, dated and geotagged, once (album "Today Sample Photos")
- `-seedSamplePlaces` — write that location history again, up to now, over whatever was noted; add `-trackPlaces YES` to track for that run (grant `location-always` with `simctl privacy` first)
- `-showOnboarding` — show onboarding again; with `-fakeICloudEntries N` to fake the "Syncing from iCloud" step
- `-lockEnabled NO` — skip the Face ID lock for one run

Simulator notes:
- Face ID: enroll with `xcrun simctl spawn booted notifyutil -s com.apple.BiometricKit.enrollmentChanged 1 && xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit.enrollmentChanged`; match with `notifyutil -p com.apple.BiometricKit_Sim.pearl.match` (`.nomatch` to fail).
- Injected taps right after launch or very short ones get dropped; use ~0.15s taps (~0.2s for iOS 26 switches). Don't read a missed first tap as an app bug.
- App settings live in the container's `Library/Preferences/com.maxsun.journal.plist`; `simctl spawn defaults` writes elsewhere, so edit it with `plutil` while the app isn't running.
- The simulator has no iCloud account unless signed in.

## Naming
App Store: **Today: Daily Journal**. Home screen / Siri / permission prompts: **Today** (`CFBundleDisplayName`); Siri alternatives in `INAlternativeAppNames`. Project, target, module and bundle ID (`com.maxsun.journal`) stay **Journal**. The app's product name is **Today** (`Today.app`, `CFBundleName`, with `PRODUCT_MODULE_NAME = Journal`): a bundle name of "Journal" is Apple's Journal app's, and App Store Connect rejects it (ITMS-90129). App Shortcut phrases must contain `.applicationName` or the build fails.

## Layout
- `Journal.xcodeproj` uses a file-system-synchronized group: files added under `Journal/` join the target automatically. Don't edit `project.pbxproj` for that.
- `App/` entry, tabs, lock, router, intents · `Models/` SwiftData (`Entry`, `Attachment`) · `Design/` theme tokens + shared components · `Views/<Feature>/` · `Services/` non-UI logic.
- `Journal/SampleMedia/` holds the sample journal's photos (from Unsplash, 1600px). They're in Debug builds only: Release leaves them out with `EXCLUDED_SOURCE_FILE_NAMES`.
- `website/` is the app's website (landing page and `privacy/`): static HTML, no build step, no third-party requests. `AppStore/Screenshots/` holds the App Store screenshots in two sets: `6.9-inch/` (1320×2868, required) and `6.3-inch/` (1206×2622, its optional slot). Keep both; never replace one set with the other.
- The root `Info.plist` holds what the generated plist can't (`UIBackgroundModes`, URL types, alternative app names). A plist under `Journal/` would be copied in as a resource.
- `JournalWidgets/` is the widget extension. Widgets read a JSON `WidgetSnapshot` (`Shared/`, compiled into both targets) from App Group `group.com.maxsun.journal`, written by `WidgetSync.update(in:)` (on launch, on every return to the foreground, and when an entry closes); they never read the store. The Today widget reads its photos from the library itself (`DayPhotos`, sharing the app's Photos access) and reloads every 15 minutes. Tapping a widget or the daily reminder opens the day sheet in the Calendar tab (`todayjournal://day[/yyyy-MM-dd]`, `AppRouter.openDay`). Style them with `WidgetStyle`, since the extension can't use `Theme`.

## Design rules
- Minimal and editorial: lots of whitespace, restrained color, no ornament.
- **Serif (`design: .serif`) in exactly three places:** page titles (`LargePageTitle`), entry-list day numbers (`Typography.dayNumber`), Insights tile numbers. Everything else is SF sans. Never add serif elsewhere. (The exported PDF is the one holdout.)
- Never hardcode colors, fonts or spacing. Use `Theme` / `UITheme` / `Typography` / `Spacing` / `Radius` from `Design/Theme.swift`. `Typography` is the whole type scale: a new role gets a new token. Settings is the exception and keeps iOS's own fonts.
- Palette: ink `#343434`, stone `#8E8B82`, sand `#DEAA73`, paper `#F3F3F3`, night `#121212`.
  - **Sand** is the single accent, for solid fills only, with white content on top (`Theme.onAccent`).
  - Quiet fills and highlights are stone washes (`Theme.surface`, `rowHighlight`, `card`), never sand.
  - Stone is only for secondary or meta text, never body copy.
- Section labels: `MetaLabel`. Explanatory and empty-state notes: `Typography.note` in secondary text. Empty pages: `EmptyState`.
- Button styles: plain buttons use `.borderless`; glass buttons use `.plain`; hand-drawn solid buttons use `TapPressStyle`.
- Toggles and checkmarks are sand. Swipe actions set their own tint (delete = `Theme.destructive`).
- Every delete confirms in an alert with Cancel.
- `Spacing.content` (20) is the edge inset for pages' lists and grids.
- Pages: every tab applies `.pageTitle(_:isFullScreen:)`. The card's position is shared across tabs (`PageCards`), and the nav bar is hidden whenever the card is off its resting place.
- Sheets: all go through `.sheetBackdrop()` on `Theme.background`. List popups follow Set Location's layout (bar title via `sheetTitle(_:)`, inset-grouped `List`). Only resizable sheets get a `Grabber`.
- Appearance is applied with `Appearance.apply` (`overrideUserInterfaceStyle` on every window), not `.preferredColorScheme`.
- Always support Dynamic Type and dark mode.

## Data
- SwiftData models must stay CloudKit-compatible: a default on every property, no `@Attribute(.unique)`, optional relationships, large data in `@Attribute(.externalStorage)`.
- Queries for live entries filter `deletedAt == nil`. User-facing deletes use `entry.moveToTrash()`, not `context.delete`. Trash is purged after 30 days on launch.
- Save explicitly (`try? context.save()`) after leaving the editor, after destructive actions, and when the scene leaves `.active`. For an animated list removal, call `save()` inside the `withAnimation`.
- Blank entries are created eagerly on New Entry. The editor deletes them on exit, and `Entry.deleteBlankEntries` sweeps leftovers.
- `Entry.text` is **Markdown**, edited as formatted text with no visible syntax (`MarkdownDocument` in `Views/Editor/MarkdownStyling.swift`).
  - Markdown → editor → Markdown must reproduce stored entries exactly.
  - Keep styling rules line-local, because styling is incremental.
  - Formatting comes only from the toolbar. Typed syntax stays literal and is escaped on save.
  - Photos and videos are `![](image:<Attachment.identifier>)` tokens. Photos on consecutive lines (no text or blank line between) show in the editor as one collage (`CollageAttachment`, `Views/Editor/PhotoCollage.swift`), a single character that writes back the same tokens.
  - An entry's title is its first line only when that line is in the Title style (`# `).
- iCloud sync (`Services/ICloudSync.swift`, opt-in). `ICloudSync.shared.container` is the app's `ModelContainer`.
  - **Never swap the container while a `@Query` is alive** (SwiftUI aborts). Swap only through `applySetting`, at safe moments: as onboarding finishes and in the Settings sheet's `onDismiss`.
  - Only entries and attachments sync. Place samples (JSON files in Application Support/Places) and settings stay on the device.

## Gotchas
- Wrap every permission prompt in `SystemPrompts.shared.during { … }` so the privacy shield doesn't flash.
- Nothing asks for a permission on launch. Each permission is asked the first time it's needed.
- The lock is iOS's own Face ID prompt over a blurred cover with the logo, in its own `UIWindow` (`PrivacyShield`); a tap on the cover asks again. The same cover hides the app in the app switcher. Face ID is asked again once the app has gone to the background (home screen, another app), not after a look at the app switcher, which only makes it inactive. Request it only once the scene is `.active`.
- Place tracking uses background updates only with Always. With While Using, iOS shows a Dynamic Island live activity.
- Don't push onto a `NavigationStack` while `.searchable` is dismissing: the push gets dropped.
- In the editor, don't decide anything from the text view's `typingAttributes`: UIKit resets them to the line above's after the editor sets them. Ask the controller (`context(at:)`, `emptyLineAttributes(at:)`). The caret on an empty line is computed from those, not taken from UIKit (`MarkdownTextView.caretRect`).
- The editor writes typing to `entry.text` once typing pauses (0.5s), not per keystroke: each write re-runs every `@Query` in the live tabs. Toolbar and photo edits write at once. In the editor, call `editor.flush()` before reading `entry.text` or saving.
- Hide the tab bar from the tab's `NavigationStack`, not from the pushed editor, or it comes back late.
- Calendar months are positioned by computation (`MonthLayout`), not measurement. Don't switch to `LazyVStack`.
- WeatherKit `WDSJWTAuthenticatorServiceListener.Errors error 2` means the build lacks team `L3957C4ZBL` or the WeatherKit entitlement.
- On This Day notifications never include entry text, because they show on the lock screen.

## Deliberately removed (don't re-add)
Favorites, writing prompts, mood, tags (a typed `#word` is plain text). No paywall for now.

## Before App Store submission
- The CloudKit schema is in Production (2026-11-16, entries, photos and videos). Deploy again after every model change: Production never creates fields itself.

## Git
One commit per distinct fix or feature; never group unrelated changes. Stage separately (`git add <files>` / `git add -p`). Docs describing a change go in that change's commit.

## Roadmap (not yet)
On-device AI (Foundation Models), monetization with StoreKit.
