---
version: 1
slug: "app-pages-homepage-swift"
primary_target: "App/Pages/HomePage.swift"
related_targets: []
---

# Home page (blank tab: sidebar + Reviews)

Scope: what a blank tab shows (⌘T, new window): a native page with a sidebar nav built to grow, first section Reviews. Mode: Operate.

Audience/job: the engineer opens a tab between tasks, sees every PR waiting on their review (direct and team requests together) or their own open PRs, narrows by typing or a facet chip, and opens one. The caret stays in the address field so a URL typed at once still goes straight there. Success: the right PR is open within seconds, and a new tab never feels slower than before.

Constraints: inherits the app-window world (DESIGN.md). Native SwiftUI, light and dark equal, nothing animates on the input path, every action keyboard-reachable (⌘F search, ⌘R refresh, arrows and Return). The zero-state dropdown no longer opens on focus; typing still opens it.

## Direction contract

THESIS: The new tab is a work queue, not a launcher. One dense flat list per tab, filtered by typing and facet chips, the Settings page's search-first idea applied to PRs. Refuses the speed-dial grid, the greeting, and the card dashboard.

OWN-WORLD: The app-window world unchanged: chrome-surface ground, one neutral ramp, 1px hairlines, flat 36pt rows with hover fill, no cards. Sidebar rows and the tab switch in dev-section-tab grammar. Facet chips in field well at 5pt. Teal only on the search focus ring and Sign In. State hues only as the PR glyph and 7pt checks dot; diffstat neutral mono.

STORY: The engineer presses ⌘T, sees Review Requested with counts, types "api" or picks Repo ▾, reads title, repo#number, author, size, checks and age on the first line and what the PR is about (gist, areas, reviews, files, comments) on the second, glances at the detail pane for the overview on a wide page, presses Return, and the PR loads in that tab.

FIRST VIEWPORT: 200pt sidebar left (Reviews selected, count). Right, a column up to 960pt: "Reviews" 20pt semibold with refresh and updated-ago; Review Requested / My PRs tabs with mono counts; 32pt search field; facet chips row with Sort trailing; hairline; then two-line rows from the top. From 1180pt of section width the column grows to 1280pt with a 320pt detail pane beside the list. The address field holds the caret; the search field is one ⌘F away.

FORM: Flat list + facets, position 2 on the ordered list of seven structures; seed key ea4a404d.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
