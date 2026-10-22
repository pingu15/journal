# Journal

A premium, minimal, editorial journaling app. Native iOS, Swift + SwiftUI, **iPhone only**.

## Design direction
- **Style:** minimal / editorial. Lots of whitespace, serif type (New York via `design: .serif`), restrained color, no ornament.
- **Palette:** https://colorhunt.co/palette/3434348e8b82e9dcbef3f3f3
  | Token | Hex | Role |
  |---|---|---|
  | ink | `#343434` | Primary text (light) |
  | stone | `#8E8B82` | Secondary text, metadata, hairlines, Markdown syntax |
  | sand | `#E9DCBE` | The single accent — button fills, highlights (always ink text on top) |
  | paper | `#F3F3F3` | Background (light) / primary text (dark) |
  | night | `#121212` | Background (dark) — deliberately deeper than ink (not from the palette link) |
- Use semantic tokens from `Journal/Design/Theme.swift` (`Theme` for SwiftUI, `UITheme` for UIKit, `Typography`, `Spacing`) — never hardcode colors, fonts, or spacing in views.
- Titles: every tab puts a `LargePageTitle` (large serif, optional meta line) at the top of its scrolling content (Calendar/Insights pass `topPadding: Spacing.xs` so it sits higher than Home's) and `.inlinePageTitle(_:scroll:)` fades a small centered title into the bar once it scrolls away, driven by a `TitleScroll` observable (`.tracksTitleScroll(_:)` on the scroll view; progress 0→1 continuously, like a system large title).
- Home: title = journal name + year span ("2025 – 2026"); the inline title says "Journal". Month / "On this day" labels are plain rows (`SectionLabel`), not section headers, so they never pin under the bar. Search: the top-left button hands off to `ExpandingSearchBar`, drawn as an overlay on the bar row (a field inside a toolbar item can't span the bar — iOS collapses it into a ⋯ overflow menu) that grows sideways out of the button; while searching the bar has no buttons and the title row is hidden. Trailing: filter + `SettingsButton`.
- Every tab has `SettingsButton` (gear → Settings sheet) at the trailing edge. Calendar: Today (`<day>.square`) + settings.
- Tab bar is icons only (`TabIcon` keeps the name as the accessibility label).
- Journal name: `@AppStorage(JournalName.storageKey)`, default "Journal", editable in Settings; shown as the home title and on the lock screen. Use `JournalName.display(_:)` (empty → default).
- New entries: round sand `NewEntryButton` floating bottom-right of the Journal and Calendar tabs (Calendar writes for the selected day; hidden for future days).
- Appearance is applied by setting `overrideUserInterfaceStyle` on every window (`Appearance.apply`), not `.preferredColorScheme`, so open sheets and the lock window switch together.
- Stone on paper is low contrast: use it only for secondary/meta text, never for body copy.
- Always support Dynamic Type and dark mode.

## Stack
- iOS 18.0+, Swift 6, default actor isolation = MainActor.
- SwiftData for persistence. Keep models CloudKit-compatible (defaults on every property, no `@Attribute(.unique)`, relationships optional) — iCloud sync is planned.
- LocalAuthentication for the optional Face ID lock (`Services/AppLock.swift`). The lock screen lives in its own `UIWindow` above everything (`PrivacyShield`) so sheets and full-screen covers are hidden too; Face ID is only requested once the scene is `.active`.
- WeatherKit (`Services/WeatherFetcher.swift`) — signed with team `L3957C4ZBL`, WeatherKit enabled on the App ID (works in the Simulator too). If requests fail with `WDSJWTAuthenticatorServiceListener.Errors error 2`, the build isn't carrying the team/entitlement. Weather is fetched when a place is set or changed, when the date changes, and when an entry with a place but no weather opens. Entitlement is in `Journal.entitlements`. **Apple's WeatherKit attribution was removed from Settings at the user's request — it must be shown somewhere (e.g. the editor header) before App Store submission.**
- CoreLocation + MapKit for places (`Services/LocationService.swift`).
- No third-party dependencies, no analytics.

## Features
- **Journal tab:** "On this day" section (same `EntryRow`, day + year) above month-grouped entries; rows are plain buttons (no disclosure chevrons). Search ("Search by text, date, or tag") via `Entry.matches`: text/tags/place by substring (image tokens excluded), dates by whole token ("Oct 6" ≠ Oct 16). Filter = All Entries | Recently Deleted (soft delete via `deletedAt`, purged after 30 days on launch). No summary line.
- **Editor:** `Entry.text` is **Markdown**. A custom `UITextView` (`Views/Editor/MarkdownEditor.swift`) shows literal Markdown styled live (`MarkdownStyler`), with photos embedded inline as `![](image:<Attachment.identifier>)` tokens rendered as `ImageAttachment`s. The header (date/time, place + weather) is a hosted SwiftUI view inside the text view, so the whole page scrolls together. Keyboard bar (`MarkdownToolbar`): photo, heading, bold, italic, strike, bullets, numbers, checklist, quote, code, link, tag, divider, ✓. Return continues lists; tapping `[ ]` ticks it; tapping a photo opens the viewer. First line = title, `#hashtags` = tags. Deleting a photo token removes the photo on exit.
- **Cover image:** `Entry.coverImageID` (falls back to the first embedded photo) → `Entry.coverPhoto`. Set it from the photo viewer's ⋯ menu ("Set as Cover Image"); the viewer also has delete (removes the token from the text via `MarkdownEditorController.removeImage`).
- **Calendar tab:** horizontally paged months (`TabView` page style, −120…+12 months), rounded-square days; a written day shows the cover photo of its earliest entry with one (else sand). Today = `<day>.square` icon. Day's entries below; the new-entry button writes for the selected (past) day. Thumbnails via `ThumbnailCache`.
- **Insights tab:** words tile spanning the top, then streak / longest streak / entries / days written in a 2×2 grid, 18-week activity grid (written / not written — `Theme.activityFilled`/`activityEmpty`, no legend), top tags (tapping one opens the Journal tab searching for it via `AppRouter.search(for:)` / `pendingSearch`).
- **Settings:** journal name, appearance (system/light/dark), daily reminder, Face ID lock, Export (button → Markdown or PDF dialog → share sheet). `JournalExport.write` builds the file; `JournalPDF` typesets a book-style PDF (title page, entries via TextKit with formatted Markdown and photos, page numbers, entries starting near a page foot move to the next page).
- **Location sheet** ("Set Location"): custom search field pre-filled with the current place, a non-interactive map (camera set in `init` — the Map ignores changes made in `onAppear`) with a custom ink pin, then Current Location / Remove / place suggestions.
- No favorites, no writing prompts, no mood (all removed deliberately).
- **App Shortcut:** "New entry in Journal" (`App/NewEntryIntent.swift`) via `AppRouter.shared`.

## Project layout
- `Journal.xcodeproj` uses a file-system-synchronized group: any file added under `Journal/` is in the target automatically — no need to edit `project.pbxproj`.
- `App` entry point, tabs, lock handling, router, intents · `Models` SwiftData models (`Entry`, `Attachment`) · `Design` theme tokens + shared components · `Views/<Feature>` screens · `Services` non-UI logic (Markdown helpers, stats, export, reminders, location, weather, image processing).
- Queries for live entries must filter `deletedAt == nil`. Use `entry.moveToTrash()` rather than `context.delete` for user-facing deletes.
- Blank entries are created eagerly on "New entry"; the editor deletes them on exit, and `Entry.deleteBlankEntries` sweeps leftovers on launch and when a navigation stack returns to root (skipping `AppRouter.openEntries`).
- Save explicitly (`try? context.save()`) after leaving the editor, destructive actions, and when the scene leaves `.active` — don't rely on autosave timing for a journal.
- Editor clipboard: copy/cut put **Markdown** (with photo tokens) on the pasteboard; paste rebuilds photos inline (`resolvePastedImage` copies photos from other entries, and duplicates get their own `Attachment`), images from other apps are imported, and photos can't be dragged. Pasted photos always get their own line.
- Live styling is incremental (`MarkdownStyler.style(_:in:)` restyles only edited paragraphs, tracked via `NSTextStorageDelegate`) — keep every styling rule line-local. Rendered photos are cached by id (`ImageAttachment.cached`).
- `SystemPrompts.shared.during { … }` wraps any permission prompt (Face ID, location, notifications) so the privacy shield doesn't flash up while the scene is briefly inactive.
- Journal name is capped at `JournalName.maxLength` (40).
- Don't push onto a NavigationStack while `.searchable` is dismissing (the push gets dropped); `EntriesView.newEntry` closes search first.

## Debugging
- Launch with `-seedSampleData` (DEBUG only) to fill an empty store with ~4 months of entries:
  `xcrun simctl launch booted com.maxsun.journal -seedSampleData`
- Simulator Face ID: enroll with `xcrun simctl spawn booted notifyutil -s com.apple.BiometricKit.enrollmentChanged 1 && xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit.enrollmentChanged`; pass a prompt with `xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit_Sim.pearl.match` (`.nomatch` to fail).
- Simulated taps on iOS 26 switches need a ~0.2s press to register. Injected taps right after a launch, or very short ones, are often dropped by the simulator — use ~0.15s taps and don't read a missed first tap as an app bug.
- Launch with `-lockEnabled NO` to skip the Face ID lock for one run without changing the stored setting.
- Read the store directly: `sqlite3 "$(xcrun simctl get_app_container booted com.maxsun.journal data)/Library/Application Support/default.store" "select ZTEXT from ZENTRY"`.

## Build
```bash
xcodebuild -project Journal.xcodeproj -scheme Journal -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build build
```

## Git
- One commit per distinct fix or feature — never group unrelated changes into one commit. When the working tree holds several, stage and commit them separately (`git add <files>` / `git add -p`), each with its own message. Docs that describe a change go in that change's commit.

## Roadmap (not yet)
- iCloud sync (needs a CloudKit container on the team), widgets (needs an extension target + App Group).
- AI features (on-device Foundation Models: prompts, reflections) — later.
- Monetization / StoreKit — later. **No paywall for now.**
