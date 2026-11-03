---
name: Koala
description: A fast, native Mac browser that understands the engineer's web.
colors:
  accent: "#0E8F80"
  accent-dark: "#2CC3AE"
  accent-deep: "#0B7A6D"
  dev-accent-text: "#0B7A6D"
  dev-accent-text-dark: "#2CC3AE"
  dev-control-selection: "#4E4E56"
  dev-control-selection-dark: "#3E3E44"
  switch-tint: "#4E4E56"
  switch-tint-dark: "#8A8A93"
  on-accent: "#FFFFFF"
  on-accent-dark: "#0B1F1C"
  pass: "#248A57"
  pass-dark: "#3DD68C"
  pending: "#B07A0A"
  pending-dark: "#F5A524"
  fail: "#D1343A"
  fail-dark: "#F2555A"
  merged: "#8E4EC6"
  merged-dark: "#B57FE8"
  strip-ground: "#EBEBED"
  strip-ground-dark: "#111113"
  chrome-surface: "#FAFAFA"
  chrome-surface-dark: "#1E1E21"
  field-fill: "#EBEBED"
  field-fill-dark: "#18181B"
  field-editing: "#FFFFFF"
  field-editing-dark: "#111113"
  hover-fill: "#DEDEE1"
  hover-fill-dark: "#26262A"
  pressed-fill: "#C8C8CD"
  pressed-fill-dark: "#303035"
  hairline: "#DEDEE1"
  hairline-dark: "#303035"
  text-primary: "#18181B"
  text-primary-dark: "#F4F4F5"
  text-secondary: "#4E4E56"
  text-secondary-dark: "#A6A6AE"
  text-tertiary: "#6C6C75"
  text-tertiary-dark: "#8A8A93"
  text-disabled: "#C8C8CD"
  text-disabled-dark: "#3E3E44"
typography:
  command-input:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "16pt"
    fontWeight: 400
  panel-heading:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "14pt"
    fontWeight: 600
  title:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "13pt"
    fontWeight: 600
  field:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "13pt"
    fontWeight: 400
  body:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "12pt"
    fontWeight: 400
  tab-title:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "12pt"
    fontWeight: 400
  tab-title-selected:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "12pt"
    fontWeight: 500
  label:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "11pt"
    fontWeight: 400
  mono:
    fontFamily: "0xProto, ui-monospace, SFMono-Regular, monospace"
    fontSize: "12pt"
    fontWeight: 400
    fontFeature: "tnum"
  mono-small:
    fontFamily: "0xProto, ui-monospace, SFMono-Regular, monospace"
    fontSize: "11pt"
    fontWeight: 400
    fontFeature: "tnum"
  badge:
    fontFamily: "SF Pro Text, -apple-system, system-ui"
    fontSize: "9pt"
    fontWeight: 600
    fontFeature: "tnum"
rounded:
  dot: "3.5pt"
  close: "4pt"
  inner: "5pt"
  control: "6pt"
  panel: "10pt"
spacing:
  hair: "2pt"
  xs: "4pt"
  sm: "8pt"
  md: "12pt"
  lg: "16pt"
  xl: "20pt"
components:
  tab:
    textColor: "{colors.text-secondary}"
    typography: "{typography.tab-title}"
    rounded: "{rounded.control}"
    height: "28pt"
    width: "120-200pt"
    padding: "0 10pt"
  tab-hover:
    backgroundColor: "{colors.hover-fill}"
  tab-selected:
    backgroundColor: "{colors.chrome-surface}"
    textColor: "{colors.text-primary}"
    typography: "{typography.tab-title-selected}"
    rounded: "{rounded.control}"
    height: "32pt"
  icon-button:
    textColor: "{colors.text-secondary}"
    rounded: "{rounded.control}"
    size: "28pt"
  icon-button-hover:
    backgroundColor: "{colors.hover-fill}"
  icon-button-pressed:
    backgroundColor: "{colors.pressed-fill}"
  address-field:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.text-primary}"
    typography: "{typography.field}"
    rounded: "{rounded.control}"
    height: "28pt"
    padding: "0 10pt"
  address-field-editing:
    backgroundColor: "{colors.field-editing}"
    textColor: "{colors.text-primary}"
  command-bar:
    backgroundColor: "{colors.chrome-surface}"
    rounded: "{rounded.panel}"
    width: "820pt"
  command-row:
    textColor: "{colors.text-primary}"
    typography: "{typography.field}"
    rounded: "{rounded.control}"
    height: "40pt"
    padding: "0 10pt"
  command-row-selected:
    backgroundColor: "{colors.hover-fill}"
  dev-panel:
    backgroundColor: "{colors.chrome-surface}"
    textColor: "{colors.text-primary}"
  dev-section-tab:
    textColor: "{colors.text-secondary}"
    typography: "{typography.body}"
    rounded: "{rounded.inner}"
    height: "26pt"
    padding: "0 9pt"
  dev-section-tab-selected:
    backgroundColor: "{colors.hover-fill}"
    textColor: "{colors.text-primary}"
  dev-search:
    backgroundColor: "{colors.field-fill}"
    typography: "{typography.body}"
    rounded: "{rounded.inner}"
    height: "26pt"
    padding: "0 8pt"
  dev-row:
    textColor: "{colors.text-primary}"
    typography: "{typography.mono}"
    padding: "5pt 12pt"
  dev-row-selected:
    backgroundColor: "{colors.hover-fill}"
    textColor: "{colors.text-primary}"
  peek-card:
    backgroundColor: "{colors.chrome-surface}"
    rounded: "{rounded.panel}"
  error-retry:
    backgroundColor: "{colors.accent-deep}"
    textColor: "{colors.field-editing}"
    rounded: "{rounded.control}"
    padding: "5px 12px"
  settings-page:
    backgroundColor: "{colors.chrome-surface}"
    width: "680pt"
    padding: "24pt 20pt 40pt"
  settings-search:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.text-primary}"
    typography: "{typography.field}"
    rounded: "{rounded.control}"
    height: "32pt"
    padding: "0 10pt"
  settings-search-focused:
    backgroundColor: "{colors.field-editing}"
  settings-row:
    textColor: "{colors.text-primary}"
    typography: "{typography.field}"
    height: "44pt"
    padding: "12pt 0"
  settings-section-heading:
    textColor: "{colors.text-primary}"
    typography: "{typography.panel-heading}"
  settings-button-primary:
    backgroundColor: "{colors.dev-accent-text}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.control}"
    height: "24pt"
    padding: "0 12pt"
  settings-keyword-chip:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.text-primary}"
    typography: "{typography.mono}"
    rounded: "{rounded.inner}"
    height: "22pt"
    width: "64pt"
    padding: "0 6pt"
  home-sidebar:
    backgroundColor: "{colors.chrome-surface}"
    width: "200pt"
    padding: "24pt 10pt"
  home-sidebar-row:
    textColor: "{colors.text-secondary}"
    typography: "{typography.body}"
    rounded: "{rounded.inner}"
    height: "28pt"
    padding: "0 8pt"
  home-sidebar-row-selected:
    backgroundColor: "{colors.hover-fill}"
    textColor: "{colors.text-primary}"
  reviews-column:
    backgroundColor: "{colors.chrome-surface}"
    width: "960pt"
    padding: "24pt 20pt 40pt"
  facet-chip:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.text-secondary}"
    typography: "{typography.body}"
    rounded: "{rounded.inner}"
    height: "24pt"
    padding: "0 8pt"
  facet-chip-active:
    backgroundColor: "{colors.hover-fill}"
    textColor: "{colors.text-primary}"
  review-row:
    textColor: "{colors.text-primary}"
    typography: "{typography.field}"
    rounded: "{rounded.inner}"
    height: "52pt"
    padding: "8pt 8pt"
  review-row-hover:
    backgroundColor: "{colors.hover-fill}"
  review-row-selected:
    backgroundColor: "{colors.pressed-fill}"
    textColor: "{colors.text-primary}"
---

# Design System: Koala

## Overview

**Creative North Star: "The Editor Pane"**

Koala's chrome is built like a pro editor's frame: neutral, opaque, dense, and exact, at Linear's typographic care and Zed's density. Every surface, hairline, and text color is a step on one 11-step neutral ramp; chroma appears only where it carries meaning (focus, selection, the primary action, and engineering state). The chrome is two thin rows (40pt tab strip, 36pt toolbar) and then the page runs edge to edge below one hairline. Nothing in the chrome is decorative.

The world is native first. SF Pro Text sets the chrome at 11 to 13pt, 0xProto carries anything an engineer would copy (URLs, paths, refs, counts, timings), SF Symbols are the only icon set, and system-owned containers (menus, NSPopover, alerts) keep their platform material. Settings is not one of them: it is a Koala-drawn page in a tab, on chrome surface. Depth comes from tonal steps and 1px hairlines; shadow exists only where a surface floats above the page. Motion is short and never on the input path. It rejects Safari's soft glass toolbar and Arc's color-drenched sidebar.

**Key Characteristics:**
- One neutral ramp, light and dark derived, is the only tonal scale.
- One accent (Koala teal) for focus, selection, and the primary action only.
- Engineer-convention state colors: pass green, pending amber, fail red, merged purple.
- Opaque flat fills, 1px hairlines, no gradients.
- 6pt radius on controls, 10pt on floating panels.
- 0xProto with tabular figures for URLs, code, and figures; SF Pro for everything else.
- 80ms hover, 120ms ease-out panels, zero under Reduce Motion.

## Colors

A cool, nearly achromatic zinc ramp with one teal and four conventional state hues. Every token is a dynamic color resolved per appearance; the `-dark` key is the same role under Dark Aqua.

### Primary
- **Koala Teal** (accent / accent-dark): the editing ring on the address field (1.5pt), the split view focus line (2pt), the page-load progress bar (2pt), the filled bookmark star, the downloads badge, and command glyphs in the command bar. In light appearance it is a non-text color (3.8:1 on chrome surface); it does not set small text.
- **Deep Teal** (accent-deep): the light-appearance accent wherever accent fills a control behind white text, as on the error page's retry button (5.2:1). Dark appearance uses accent-dark with on-accent-dark text. The Settings page's filled primary button takes the same pair through Theme.accentText (dev-accent-text) as its fill and Theme.onAccent (on-accent / on-accent-dark) as its text.

### Secondary
- **Pass Green** (pass / pass-dark): open PRs and issues, passing checks.
- **Pending Amber** (pending / pending-dark): running checks, console warnings.
- **Fail Red** (fail / fail-dark): closed PRs, failing checks, console error counts, find with no match, download errors.
- **Merged Purple** (merged / merged-dark): merged PRs, issues closed as completed.

State colors draw glyphs, 7pt dots, timing bars, and badge numerals. In light appearance pass and pending are below 4.5:1 on the chrome surface, so the words beside a state stay in text tokens.

### Neutral
The ramp, step 0 to 10. Light: #FFFFFF, #FAFAFA, #F4F4F5, #EBEBED, #DEDEE1, #C8C8CD, #A0A0A8, #6C6C75, #4E4E56, #2E2E33, #18181B. Dark: #111113, #18181B, #1E1E21, #26262A, #303035, #3E3E44, #5A5A62, #8A8A93, #A6A6AE, #D4D4D8, #F4F4F5.
- **Strip Ground** (strip-ground, step 3 light / 0 dark): behind the tab strip and the page content area.
- **Chrome Surface** (chrome-surface, step 1 / 2): toolbar, selected tab, bookmarks bar, find bar, dev panel, command bar, Peek card, the Settings page, the home page, Koala-authored web pages.
- **Field Well** (field-fill, step 3 / 1): the resting address field, resting facet chips, and the home page's loading placeholders and unloaded avatars.
- **Editing Field** (field-editing, step 0 / 0): the address field while focused.
- **Hover** (hover-fill, step 4 / 3) and **Pressed** (pressed-fill, step 5 / 4): tabs, icon buttons, bookmarks, chips, selected command row; set facet chips take hover fill; the keyboard-selected review row takes pressed fill.
- **Hairline** (hairline, step 4 / 4): every 1px separator and every floating-panel border.
- **Text** primary (step 10), secondary (step 8), tertiary (step 7), disabled (step 5).

### Named Rules
**The Action-Only Accent Rule.** Teal marks focus, selection, progress, and the primary action. It never fills a resting surface, never tints a header, and never decorates. The selected command row and selected dev tab are neutral (hover fill), not teal. The home page's review list is the one list where hover and keyboard selection coexist on the same rows, so its selected row goes one step deeper, to pressed fill, with tertiary text stepped up to secondary.

**The Convention Rule.** State hues mean exactly what an engineer expects (green pass, amber pending, red fail, purple merged) and nothing else. A draft or not-planned state is tertiary text, not a fifth hue.

**The Legible Favicon Rule.** In dark appearance, a glyph-on-transparent favicon that is dark and near-monochrome (mean luminance under 0.22, chroma under 0.15, under 70% coverage) is drawn as a template in secondary text. SVG favicons are rendered from their light variant with their `prefers-color-scheme: dark` blocks removed, so the icon keeps its full shape. Filled or colorful favicons are untouched.

## Typography

**Body Font:** SF Pro Text (system font)
**Label/Mono Font:** 0xProto (bundled, Regular and Bold; semibold and heavier set Bold), tabular figures

**Character:** Platform type at small, careful sizes; weight, not size, carries hierarchy (the selected tab goes from 400 to 500 at the same 12pt). Mono marks anything machine-readable, so a URL or a duration reads as data at a glance.

### Hierarchy
- **Command input** (400, 16pt): the command bar's query field only.
- **Page title** (600, 20pt): the Settings page title and the home page's section title, matching the Koala web page heading.
- **Panel heading** (600, 14pt): the PR title in the GitHub context popover, and Settings section headings. The GitHub sign-in panel's heading is 15pt semibold and its device code 28pt semibold mono.
- **Title** (600, 13pt): popover titles (Downloads, Review queue).
- **Field** (400, 13pt): address field text and placeholder, command row and review row titles (500 when selected).
- **Body** (400, 12pt): tab titles, dev panel section tabs, popover body copy, bookmarks, find field.
- **Label** (400, 11pt): row subtitles, guide-word titles, dev filter chips, metadata.
- **Mono** (400, 12pt): the address field's path at rest, Peek host, console text, storage keys (500) and values, repo slug and branch refs.
- **Mono small** (11pt): command row URLs, timing columns, review-queue refs, review rows' `repo#number`, team slug, login, and diffstat; 10pt for guide-word, sidebar, and tab counts (500) and ruler ticks.
- **Badge** (600, 9pt, tabular): error, queue, and download counts on toolbar buttons.

Koala-authored web pages use the same faces through `-apple-system, system-ui` and an embedded 0xProto `@font-face` (falling back to `ui-monospace, SFMono-Regular`): 13px/1.5 body, 20px/600 heading at -0.01em, 12px mono code; the JSON viewer and view source are 12px mono at 1.6 and 1.55.

### Named Rules
**The Mono Means Data Rule.** 0xProto sets URLs and paths, refs and slugs, counts, timings, and code. Prose, titles, and labels are never mono, and figures that sit in a line of SF Pro use tabular (monospaced) digits.

**The Host First Rule.** A URL reads host in primary SF Pro, remainder in tertiary 0xProto, with scheme and "www." dropped. The address field, command rows, and Peek header all follow it; focusing the address field shows the full URL, selected.

## Layout

The window is a fixed vertical stack: tab strip (40pt, the native compact titlebar height, so traffic lights center untouched; 80pt leading inset, 12pt in full screen), toolbar (36pt), optional bookmarks bar (28pt, off by default), optional find bar (32pt), the page edge to edge, and the optional dev panel at the bottom (300pt by default, preferred minimum 200pt, capped to 80% of available content height). Each chrome row ends in one hairline.

Tabs run 120 to 200pt wide with 4pt gaps and a centered 16pt hairline separator between unselected neighbors; pinned tabs are 40pt icon-only. Past the minimum width the strip scrolls whole tabs and shows a guide word at each overflowing edge. The toolbar holds back, forward, reload at left (28pt buttons, 2pt apart, 8pt from the edge), the flexing address field, then the right cluster.

Spacing is a 4pt grid for structure (row heights, gaps, insets of 4, 8, 12, 16, 20pt) with 2pt half steps inside controls (2pt between buttons, 6pt list padding, 10pt and 14pt control insets). Popovers pad 14pt; sheets pad 20pt. The Settings page is a centered 680pt column with a 20pt minimum gutter: 24pt above the title and above the first section, 40pt between sections and before the footer, 40pt at the end. The command bar is 820pt wide (window width minus 48pt when narrower), centered, 12pt below the chrome; below 720pt it drops its preview pane. Peek insets its card 7% of width (min 24pt) and 5% of height (min 16pt). Split view divides the content with a 1pt hairline. The home page puts a 200pt sidebar and a 1px vertical hairline beside its section, folding the sidebar away below 900pt of page width; Reviews centers a column up to 960pt with 20pt minimum gutters; from 1180pt of section width the column grows to 1280pt and splits into the list, a 12pt gap, a 1px vertical hairline, and a 320pt detail pane. When the list is narrower than 680pt its rows drop the login, team, diffstat, decision words, and second-line facts.

## Elevation & Depth

Koala is flat. Docked chrome conveys depth only by tonal step: strip ground sits one or two ramp steps below the chrome surface, and the selected tab shares the toolbar's surface so the two read as one plane. Floating surfaces (command bar, address dropdown) are opaque chrome surface with a 1px hairline border and the standard macOS window shadow. Peek separates from the page with a scrim of text-primary at 18% opacity behind a hairline-bordered card.

### Shadow Vocabulary
- **Floating panel** (system `NSWindow.hasShadow`): command bar and address dropdown only.

### Named Rules
**The Floating-Only Shadow Rule.** Shadow belongs only to surfaces that float above the page. Docked chrome, tabs, chips, buttons, and panels never cast one.

**The Opaque Rule.** Every Koala-drawn surface is an opaque ramp step. Translucency, blur, and gradients are not part of this world; the only alpha in the chrome is the Peek scrim. Console rows remain neutral; severity appears in semantic glyphs and counts.

## Shapes

Continuous-curve corners throughout. Controls (tabs, icon buttons, address field, command rows, web buttons and inputs) take 6pt; floating panels (command bar, address dropdown, Peek card) take 10pt; inner chips inside panels (dev section tabs, console level chips, bookmark items, home sidebar rows, facet chips, review rows) take 5pt; the tab close button takes 4pt; status dots are 7pt circles. The selected tab rounds only its top corners and runs down into the toolbar; unselected tab hover fills are fully rounded and inset 3pt top and bottom. Borders are 1px hairlines, or 1.5pt teal for the editing ring.

## Components

### Tab
Quiet at rest, joined when selected.
- **Shape:** 6pt; 28pt hover body, 32pt selected body.
- **Default:** no fill on strip ground, 16pt favicon at a 10pt inset, 8pt gap, 12pt regular title in secondary text, 16pt hairline separator.
- **Hover:** hover fill, 80ms; the close button (9pt xmark, 4pt radius) appears.
- **Selected:** chrome surface with bottom corners square, joined to the toolbar; 12pt medium title in primary text; neighbor separators hide; close button always shown.
- **GitHub:** a PR or issue tab shows its state glyph in its state color in place of the favicon, plus a 7pt checks dot on the icon's corner ringed 1.5pt in the tab's own fill. A split tab names both pages joined by a fraction slash.
- **Loading:** a small system spinner replaces the icon.

### Guide Words
The overflow edge of a scrolling strip: a 9pt semibold drawn chevron in tertiary, the hidden count in 10pt medium mono tertiary (omitted for one), and the nearest hidden tab's title in 11pt secondary. Clicking reveals that tab.

### Icon Button
- **Shape:** 28pt square, 6pt radius, SF Symbol at 12 to 13pt medium in secondary text.
- **Hover / Pressed:** hover fill / pressed fill. **Disabled:** disabled text, no fill.
- **Badge:** a 9pt semibold tabular count at the top trailing corner: fail red for console errors, secondary for the review queue, teal for downloads.

### Address Field
The primary action of the window.
- **Resting:** field well, 6pt, 28pt tall, 10pt inset; host in 13pt primary, path in 12pt tertiary mono; a bookmark star at the trailing edge (tertiary, teal when filled).
- **Editing:** editing-field fill and a 1.5pt teal ring and a teal caret; the full URL, all selected; the star hides.
- **Dropdown:** the command bar's sectioned list in a 10pt floating panel with a hairline border, as wide as the field; a field 720pt or wider also shows the preview pane. Focusing the field opens nothing, on a new tab or a page URL: a blank tab's home page stands in for the zero state. Typing opens the list.

### Command Bar
- **Container:** 820pt, so the list and its preview fit side by side and the width never changes while typing; 10pt radius, chrome surface, 1px hairline border, system shadow; 16pt query field with an 18pt search glyph, a hairline under the field. The list scrolls past 520pt; reaching a section's first row by keyboard scrolls its header into view.
- **Sections:** the top hit comes first without a header: navigate, search, keyword, or GitHub shorthand rows, plus the strongest tab, bookmark, or command when it is a whole-title prefix match. Then come Tabs, Bookmarks, and Commands (local, 8 rows in all with the top hit), then GitHub (up to 3), History (4), and Suggestions (4), which stream in. Headers are 30pt, 11pt medium tertiary, aligned to the row titles and set 3pt above the first row, so more space sits above a header than below it. Headers are accessibility headings and are not selectable.
- **Rows:** 40pt tall, 10pt inset, 6pt radius, 16pt icon, 10pt gap; 13pt title, URL subtitle in 11pt mono (host secondary, path tertiary) or 11pt tertiary text; trailing hint (Switch to Tab, Search, Open, Reopen, the keyword's engine, the shortcut, or a history row's relative time such as "3h ago") in 11pt tertiary tabular. A GitHub PR or issue shows its state glyph and checks dot, as its tab does; rows for items not open in a tab fetch their state once, in one request. A keyword row leads with the keyword chip (field well, 5pt, 22pt, 12pt medium mono).
- **Icons:** the host's cached favicon, else its parent domain's (api.github.com shows GitHub's), else `/favicon.ico`, which is fetched only for hosts already in history. Dark monochrome favicons follow the Legible Favicon Rule.
- **Selected:** hover fill and a medium-weight title. Pointer hover moves the selection only when the pointer actually moves, so rows that stream in, rebuild, or scroll under a resting pointer never take the highlight.
- **Preview pane:** 288pt on chrome surface behind a 1px hairline, describing only the selected row, at least 232pt tall. The header has a 20pt icon, the title in 13pt semibold (up to 3 lines), the URL host first in 11pt mono wrapping, and a repository description or queue reason in 12pt secondary. Below a hairline is a facts grid: 11pt tertiary labels, 12pt primary values, and mono for counts, refs, and hosts. Facts: Visited (`12×  ·  3h ago`, with the exact date as help; a Frequent host counts visits across the host), Bookmark folder, Tab, the GitHub state, checks ("3 of 4 passing"), `head → base` and review, the engine a search uses, and a command's menu path and shortcut. A 32pt footer names what Return does ("↩ Open in New Tab", "↩ Switch to Tab", "↩ Run"; the address field adds "⌘↩ New Tab"). Content swaps instantly with the selection; facts that load later fill a row that is already reserved.
- **Inline completion:** when one address is clearly meant, the field fills it in ahead of the caret, with the added part in the system text selection: "gith" shows "github.com", and "github.com/sw" shows the full address from history. Its row leads the list and is selected, so Return opens what the field shows; moving the selection off it takes the completion back out. Only hosts complete until a "/" is typed. A candidate needs real intent (a host visited twice; an address typed once or visited three times) and must outscore its nearest unrelated rival 1.5× (3× on two letters). Scores are visits plus twice the typed visits, halved every 30 days, and an address absorbs the pages beneath it. Nothing completes on one letter, whitespace, a bare keyword ("gh"), a paste, an edit away from the end, or composing input. Typing through a completion keeps it, and deleting one suppresses it until editing ends.
- **Zero state:** an empty query shows Review Queue (up to 4, when signed in), Recently Closed (up to 3, which reopen with their back history), and Frequent (up to 5 hosts by visits). With all three empty, only the field shows.

### Dev Panel
A native debugging workbench on chrome surface, docked below a draggable hairline or detached into a normal, resizable macOS window bound to its inspected tab.
- **Frame:** default dock height 300pt, preferred minimum 200pt, capped to 80% of available content height. The detached window restores its frame and has a 480 × 320pt minimum.
- **Header:** 36pt; Console, Network, Storage, Page. Section tabs are 26pt tall with 5pt corners and 9pt horizontal insets; selected tabs use neutral hover fill and 12pt semibold primary text. Origin and capture indicator yield space to tabs and window actions when needed. Console errors use a red count.
- **Toolbar:** 40pt with 12pt side insets, 10pt gaps and small native controls. Search uses a 26pt field well with 5pt corners. Overflow actions scroll horizontally rather than compressing labels.
- **Evidence and details:** Console, Network and Storage use a draggable list/detail split, initially 58% list. At 760pt and wider, the list has a 300pt minimum and details retain roughly 320pt; below 760pt, selection replaces the list with details and a 30pt Back to list row. Split proportion persists and can be adjusted with arrow keys and accessibility actions.
- **Rows:** virtualized native lists, minimum 28pt rows with 5pt vertical and 12pt horizontal insets; table headings are 26pt. Data uses 11–12pt 0xProto, headings and controls 11–12pt SF Pro, and compact timestamps/footer counts 10pt. Selected rows use neutral hover fill with primary/secondary text in both active and inactive windows. Console rows use neutral backgrounds; semantic glyphs carry severity.
- **Control selection:** native selected segments and checkboxes use dev-control-selection (Theme.controlSelectionTint) behind white system labels. Action text and capture status use dev-accent-text (Theme.accentText), the text-safe teal role; ordinary row selection stays neutral.
- **Detail reading:** 12pt selectable mono code, 4pt added line spacing, semibold 12pt section headings and explicit Copy actions. Network exposes native Overview/Headers/Payload/Response segments, formatted JSON and Raw. Resource timing bars use a shared time scale and neutral bars, with fail red for errors.
- **Anchors:** Console input stays below the evidence area; Console, Network and Storage end in 24pt count/status footers. Empty states state the next useful action; unavailable data is named explicitly.
- **Other sections:** Page groups native controls and observed performance in a scroll view. No raster assets or authored entrance animations are used.

### Peek Card
The linked page floats over the current one: the scrim, then a 10pt card on chrome surface with a hairline border; a 36pt header with the host in 12pt mono secondary and three icon buttons (split, tab, close). Opens with a 0.97 to 1 scale and fade over 120ms ease-out.

### Split View Focus Line
Two pages share the content area divided by a 1pt hairline (5pt drag target). The focused pane carries a 2pt teal line along its top edge; one pane has no line.

### Koala Web Pages
The error page, JSON viewer, and view source mirror the chrome tokens through CSS variables with light and dark sets: chrome surface background, primary text, tertiary muted text, hairline rules, accent for focus and selection (30% mix for `::selection`). The error page is a 520px column with a 20px heading, muted body, the URL in mono above a hairline, and one filled retry button (deep teal light, accent dark) with a 2px accent focus outline. Viewer controls are 6px-radius hairline-bordered inputs and buttons with hover fill and an accent border on focus.

### Settings Page
A searchable native page (koala://settings) in a browser tab, not a window: one column you filter by typing, on chrome surface, flat rows between hairlines, no cards.
- **Column:** 680pt maximum with a 20pt minimum gutter. It centers on the full page width even while a scroller is visible, so nothing shifts as results change.
- **Pinned header:** "Settings" in 20pt semibold primary; a 32pt search field (field well, 6pt, 10pt inset, 13pt magnifying glass and text) that takes editing fill, a 1.5pt teal ring, and a teal caret when focused, with a trailing 11pt tertiary hint, ⌘F at rest and esc plus a clear button while a query is present. Below it the section index (General, GitHub, Keywords, Shortcuts, Extensions, Sites, Browsing Data) in dev-section-tab grammar: 26pt, 5pt corners, 9pt insets, 12pt text, current section in hover fill and semibold primary. While searching, each chip shows its match count in 10pt medium mono tertiary and a zero-match chip is disabled. A hairline closes the header; the search field is focused when the page appears.
- **Sections:** 14pt semibold heading, 12pt tertiary one-line summary 4pt below, 12pt to the first row; 40pt between sections.
- **Rows:** flat, at least 44pt, 12pt vertical insets, a 1px hairline above each. 13pt primary title, 11pt tertiary detail 3pt below, the native control trailing with a 16pt minimum gap.
- **Search:** every query word must start a word in the row's section, title, detail, or terms (as in the command bar); non-matching rows and empty sections disappear, and matched word starts are set semibold at the text's own size and face. No matches shows a centered message and a Clear Search button.
- **Controls:** native pickers, bordered buttons, and small switches; switches are tinted switch-tint (Theme.switchTint: ramp step 8 light, step 7 dark, so the on track stays above 3:1 on chrome surface), never teal. The one filled primary button (Sign In…) is 24pt, 6pt, 12pt insets, 13pt medium, accentText fill with onAccent text.
- **GitHub account:** a row, not a card: a 40pt circular avatar with a hairline ring, semibold name, mono `@login` in secondary and a tabular review-queue count in tertiary.
- **Keywords:** a 64pt column holding the keyword chip (field well, 5pt, 22pt, 12pt medium mono), then the name and the template read host first in 11pt mono (host secondary, remainder tertiary, scheme and "www." dropped). A row expands in place to a native field grid; problems show as a fail-red glyph and line.
- **Shortcuts:** one row per menu bar command in menu order, the menu's name as detail. Trailing is the shortcut in a field-well chip (5pt, 22pt, at least 72pt wide, 12pt medium SF with tabular figures, not mono; "None" in tertiary). Click the chip to record: it reads "Press keys" in secondary with a 1.5pt teal ring, and key presses go nowhere else. Esc cancels, Delete removes the shortcut, and a click elsewhere ends recording. A key without ⌘, ⌃, or ⌥ (an F-key alone is fine), a key with fn, or one another command already uses, keeps recording and shows why in an 11pt fail-red line. A changed row adds a tertiary `arrow.uturn.backward` reset button. Restore Defaults closes the list, as in Keywords.
- **Extensions:** 32pt icon, semibold name with the version in 11pt mono tertiary, 12pt secondary description, 11pt tertiary access summary, then inline 11pt borderless Pin to Toolbar, Options…, and Remove… (Remove in tertiary) tinted accentText. A disabled extension dims its icon and content; its switch stays at full strength.
- **Footer:** the version and build in 11pt mono tertiary, selectable.
- **Tab integration:** the tab and command rows show the `gearshape` SF Symbol in place of a favicon; the address field reads "Settings" at rest and shows the koala:// URL while editing; reload is disabled; ⌘F focuses the page search instead of the find bar; ⌘, reveals the one settings tab (focusing its search) or opens it.

### Home Page
What a blank tab shows (no URL and no web view yet; ⌘T, a new window): a native page on chrome surface, a sections sidebar beside the current section, Reviews first. The address field keeps the caret, so an address typed at once goes straight there. Flat list and facets, no cards, no greeting.
- **Sidebar:** 200pt, 24pt top and 10pt side insets, rows 2pt apart, then a 1px vertical hairline. Rows in dev-section-tab grammar at 28pt: 8pt insets, 5pt corners, a 16pt-wide 13pt medium SF Symbol (tertiary, primary when current), 8pt gap, 12pt title in secondary (semibold primary on hover fill when current), and a trailing 10pt medium mono tertiary count. Below 900pt of page width the sidebar folds away.
- **Column:** up to 960pt with 20pt minimum gutters, centered; 24pt above the header, 10pt below it, then a hairline across the section.
- **Header:** "Reviews" in 20pt semibold primary on a 28pt line, trailing "Updated just now" in 11pt tabular tertiary and a 28pt refresh icon button (13pt medium arrow.clockwise in secondary, a small spinner while refreshing). 12pt below, the Review Requested / My PRs tabs in dev-section-tab grammar (26pt, 5pt, 9pt insets, 2pt apart), each with a 10pt medium mono tertiary count, on ⌥⌘1 and ⌥⌘2. 12pt below, the shared 32pt page search field. 10pt below, the 24pt facet row with the sort menu trailing.
- **Facet chips:** 24pt, 5pt corners, 8pt insets, 6pt apart, scrolling horizontally rather than wrapping. A menu chip (Repository, Author, Checks) at rest is field well with its 12pt name in secondary and an 8pt semibold tertiary chevron; set, it takes hover fill, shows the value in 12pt medium primary (mono for repository and author), and ends in an 18pt clear button (8pt bold xmark, tertiary). Toggle chips (Direct only, shown only when team requests exist; Hide drafts) take hover fill, 12pt medium primary, and a 9pt bold checkmark when on. While anything is filtered a borderless 12pt secondary Clear follows, with hover fill. Sort is a borderless menu: 12pt secondary title and 8pt semibold chevron. Switching tabs clears every filter.
- **Rows:** two lines, 52pt (8pt insets, an 18pt first line, 2pt, a 16pt second line), 5pt corners, flat, no separators. A 16pt column with the 12pt state glyph (open or draft) on the first line. The first line: the 13pt primary title, which truncates first; `repo#number` in 11pt mono (repository secondary, number tertiary), which never truncates; a team request adds a 9pt medium person.2 and the team slug in 11pt mono tertiary. Trailing, 12pt apart: a 120pt column holding a 16pt avatar (hairline ring, field-well disc until it loads) and the author's login in 11pt mono secondary on Review Requested, or on My PRs the review decision (a 10pt semibold glyph in its convention color, checkmark pass, exclamationmark fail, circle.dotted tertiary, beside its words in 11pt secondary); the diffstat `+48 −9` in 11pt mono tertiary, neutral, right-aligned in 84pt; the 7pt checks dot; the age (now, 5m, 3h, 2d, 6w, 4mo) in 11pt tabular tertiary, right-aligned in 30pt. The second line says what the pull request is about: the gist in 12pt secondary, led by a 9pt tertiary `apple.intelligence` glyph when Apple Intelligence wrote it (the author's first paragraph of prose otherwise), truncating first; then up to two areas it touches in 11pt mono tertiary (`App/Cache · App/Storage +2`). Its trailing facts sit under the first line's columns: in the 120pt column, approvals and requests for changes as 9pt semibold convention glyphs with 11pt mono counts, the first glyph in a 16pt slot so its count starts under the login (on My PRs, an hourglass and the people still asked to review, under the decision's words); `14 files` right-aligned under the diffstat; `bubble.left` and the comment count under the dot and age. With no gist the areas lead, then `head → base`; while a gist is written over an empty description a static 160×8pt field-well bar holds the place. Matched word starts are semibold at their own size and face, as in Settings. Search also matches labels and area names.
- **Hover / Selected:** pointer hover takes hover fill. The keyboard-selected row takes pressed fill, one ramp step deeper, so Return's target is never ambiguous; its title goes to 500, its tertiary text steps up to secondary to clear 4.5:1 on that fill, and its review glyphs go to secondary, since the state hues fall under 3:1 there. Click opens the pull request in a new tab and brings it forward, so Reviews stays put; ⌘-click opens it in a background tab. The context menu offers Open in New Tab, Open in Background Tab, Open in This Tab, Copy Link, Copy Branch, and Copy Checkout Command.
- **States:** signed out, the header keeps only its title, and 32pt below the hairline sit a 13pt secondary sentence and the Sign In… primary button. Loading shows six static two-line skeleton rows in field well that mirror the row's columns (glyph, title bar, avatar and login, diffstat, dot, age, then a gist bar), with the pane's space held empty on wide pages, while the tabs, search, and facets hold their space invisibly so rows land where the placeholders sit. A failed first load gives that space back and shows the error line (11pt fail triangle, 12pt secondary message, small Try Again); a later failure shows the same line above the rows. Empty is a 13pt secondary sentence over a 12pt tertiary line; filtered empty is "No pull requests match." with a small Clear Filters. Search and facets stay hidden until there is something to filter. A truncated list ends 16pt below the rows with "Showing the N most recently updated of M." in 11pt tabular tertiary and an 11pt medium secondary Open on GitHub.
- **Detail pane:** on wide pages, beside the list behind a 1px hairline, 320pt on chrome surface, filling the height below the header and scrolling on its own; 16pt leading, 8pt trailing, 16pt top insets. It describes the row last pointed at (only real pointer movement counts, so rows scrolling under a still pointer don't take it), reached by arrow keys, or focused by VoiceOver, else the selection, else the first row; content swaps instantly. Header: the state glyph and the title in 14pt semibold (up to 4 lines), `repo#number` in 11pt mono, then a 16pt avatar, login in 11pt mono secondary, and "opened 2 days ago" in 11pt tertiary. Then "Summary" in 11pt tertiary with a 10pt `apple.intelligence` glyph (help: "Summarized on this Mac by Apple Intelligence") over the overview in 12pt primary, then "Description" over the author's first paragraph in 12pt secondary; with no summary, the author's paragraph alone in primary; while one is written, three static field-well bars. Below a hairline, the command bar's facts grid: Branch `head → base`, Changes `+48 −9 · 4 files`, Areas (up to 5, mono, with file counts), Checks (dot and word), Reviews (a convention glyph and login per reviewer, then "Waiting on …"), Labels (neutral text; label colors are never used), Comments, Updated. No footer: rows are the targets.
- **Summaries:** written on this Mac by Apple Intelligence (Foundation Models), one at a time, review requests first, the previewed pull request jumping the queue; kept in the database under a fingerprint of title, description, and files, so each is written once per change. Settings › GitHub › Summarize pull requests turns them off; where Apple Intelligence can't run, the switch is off and disabled with the reason beneath.
- **Keyboard:** ⌘F focuses the search field instead of the find bar; ⌘R and the reload button refresh the list; the arrow keys in the search field move the selection and scroll it into view, Return opens it (or the first row) in a new tab in front, ⌘Return in a background tab, and Esc clears the query. Zoom, print, and view source are disabled.
- **Accent:** teal appears on this page only as the search field's focus ring and caret and the Sign In… button.

## Do's and Don'ts

### Do:
- **Do** take every surface, separator, and text color from the neutral ramp, in both appearances.
- **Do** keep chrome surfaces opaque and flat, separated by 1px hairlines one ramp step apart.
- **Do** reserve teal for focus, selection, progress, and the primary action; use accent-deep behind white text in light appearance.
- **Do** use pass, pending, fail, and merged only for their engineering meanings, as glyphs, dots, bars, and counts.
- **Do** set URLs, paths, refs, counts, timings, and code in 0xProto with tabular figures, host first.
- **Do** use 6pt radius on controls and 10pt on floating panels, continuous curve.
- **Do** animate hover at 80ms and panels at 120ms ease-out, and drop to zero under Reduce Motion.
- **Do** tint dark monochrome favicons in dark appearance rather than leaving them invisible.
- **Do** let system containers (menus, popovers, alerts) keep their native macOS material; Settings is a Koala-drawn page on chrome surface.

### Don't:
- **Don't** add gradients, glass, blur, or translucency to Koala-drawn chrome.
- **Don't** cast shadows from docked chrome, tabs, chips, or buttons; shadow is for floating surfaces only.
- **Don't** fill resting surfaces or selected list rows with teal.
- **Don't** set prose, titles, or labels in 0xProto.
- **Don't** set small text in light-appearance teal, pass, or pending; their words stay in text tokens.
- **Don't** animate anything on the input path (typing, tab switching, row selection).
- **Don't** introduce a second icon family; SF Symbols only.
