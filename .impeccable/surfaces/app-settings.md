---
version: 1
slug: "app-settings"
primary_target: "App/Settings"
related_targets: []
---

# Settings page (koala://settings, rendered in a tab)

Scope: Koala's settings, moved out of a separate window into a native SwiftUI page hosted in a browser tab. Mode: Operate.

Audience/job: the engineer changes one setting and goes back to work: picks a search engine, edits a keyword, signs in to GitHub, points Koala at a code folder, enables or pins an extension, imports bookmarks, clears history. Success: any setting is found by typing a few letters, changed, and left in seconds.

Constraints: inherits the app-window world (DESIGN.md). Native controls (pickers, switches, buttons), SF Pro / SF Mono, light and dark equal. Nothing animates on the input path. Every setting keyboard-reachable; ⌘, opens or focuses the one settings tab.

## Direction contract

THESIS: Settings as a searchable page, not a dialog. One column you filter by typing, the command bar's idea applied to preferences. Refuses the stock tabbed preferences window and the System Settings sidebar clone.

OWN-WORLD: The app-window world unchanged: chrome-surface ground, one neutral ramp, 1px hairlines between flat rows, no cards. Teal only on the search field's focus ring and primary actions. Section index in dev-section-tab grammar (26pt, 5pt corners, neutral selected fill). Mono only for data: keywords, templates, paths, versions, counts, logins.

STORY: The engineer presses ⌘, and the settings tab opens (or comes forward) with the search field focused, types "pin" or "editor", sees only the matching rows with the match set in semibold, changes the setting, and closes or leaves the tab.

FIRST VIEWPORT: A pinned header in a centered 680pt column: "Settings" at 20pt semibold, a 32pt search field with an esc / ⌘F hint, the section index (General, GitHub, Keywords, Extensions, Browsing Data, with counts) and a hairline. Below, General's rows, then the GitHub account card with avatar, login and review-queue count. The search field is the primary action.

FORM: Search-first column, position 3 on the ordered list of seven structures; dealt lead of the surface roll, chosen by the user. Seed key 58b3f566.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
