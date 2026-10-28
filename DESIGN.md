---
name: Nano
description: A fast, native Mac browser that understands the engineer's web.
colors:
  accent: "#0E8F80"
  accent-dark: "#2CC3AE"
  accent-deep: "#0B7A6D"
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
    fontFamily: "SF Mono, ui-monospace, SFMono-Regular, monospace"
    fontSize: "12pt"
    fontWeight: 400
    fontFeature: "tnum"
  mono-small:
    fontFamily: "SF Mono, ui-monospace, SFMono-Regular, monospace"
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
  context-chip:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.text-secondary}"
    typography: "{typography.mono-small}"
    rounded: "{rounded.control}"
    height: "24pt"
  command-bar:
    backgroundColor: "{colors.chrome-surface}"
    rounded: "{rounded.panel}"
    width: "640pt"
  command-row:
    textColor: "{colors.text-primary}"
    typography: "{typography.field}"
    rounded: "{rounded.control}"
    height: "40pt"
    padding: "0 10pt"
  command-row-selected:
    backgroundColor: "{colors.hover-fill}"
  dev-chip:
    textColor: "{colors.text-tertiary}"
    typography: "{typography.label}"
    rounded: "{rounded.inner}"
    height: "22pt"
    padding: "0 8pt"
  dev-chip-on:
    backgroundColor: "{colors.hover-fill}"
    textColor: "{colors.text-primary}"
  dev-section-tab:
    textColor: "{colors.text-secondary}"
    typography: "{typography.body}"
    rounded: "{rounded.inner}"
    height: "24pt"
    padding: "0 10pt"
  peek-card:
    backgroundColor: "{colors.chrome-surface}"
    rounded: "{rounded.panel}"
  error-retry:
    backgroundColor: "{colors.accent-deep}"
    textColor: "{colors.field-editing}"
    rounded: "{rounded.control}"
    padding: "5px 12px"
---

# Design System: Nano

## Overview

**Creative North Star: "The Editor Pane"**

Nano's chrome is built like a pro editor's frame: neutral, opaque, dense, and exact, at Linear's typographic care and Zed's density. Every surface, hairline, and text color is a step on one 11-step neutral ramp; chroma appears only where it carries meaning (focus, selection, the primary action, and engineering state). The chrome is two thin rows (40pt tab strip, 36pt toolbar) and then the page runs edge to edge below one hairline. Nothing in the chrome is decorative.

The world is native first. SF Pro Text sets the chrome at 11 to 13pt, SF Mono carries anything an engineer would copy (URLs, paths, refs, counts, timings), SF Symbols are the only icon set, and system-owned containers (menus, NSPopover, the Settings window, alerts) keep their platform material. Depth comes from tonal steps and 1px hairlines; shadow exists only where a surface floats above the page. Motion is short and never on the input path. It rejects Safari's soft glass toolbar and Arc's color-drenched sidebar.

**Key Characteristics:**
- One neutral ramp, light and dark derived, is the only tonal scale.
- One accent (Nano teal) for focus, selection, and the primary action only.
- Engineer-convention state colors: pass green, pending amber, fail red, merged purple.
- Opaque flat fills, 1px hairlines, no gradients.
- 6pt radius on controls, 10pt on floating panels.
- SF Mono with tabular figures for URLs, code, and figures; SF Pro for everything else.
- 80ms hover, 120ms ease-out panels, zero under Reduce Motion.

## Colors

A cool, nearly achromatic zinc ramp with one teal and four conventional state hues. Every token is a dynamic color resolved per appearance; the `-dark` key is the same role under Dark Aqua.

### Primary
- **Nano Teal** (accent / accent-dark): the editing ring on the address field (1.5pt), the split view focus line (2pt), the page-load progress bar (2pt), the filled bookmark star, the downloads badge, and command glyphs in the command bar. In light appearance it is a non-text color (3.8:1 on chrome surface); it does not set small text.
- **Deep Teal** (accent-deep): the light-appearance accent wherever accent fills a control behind white text, as on the error page's retry button (5.2:1). Dark appearance uses accent-dark with on-accent-dark text.

### Secondary
- **Pass Green** (pass / pass-dark): open PRs and issues, passing checks.
- **Pending Amber** (pending / pending-dark): running checks, console warnings.
- **Fail Red** (fail / fail-dark): closed PRs, failing checks, console error counts, find with no match, download errors.
- **Merged Purple** (merged / merged-dark): merged PRs, issues closed as completed.

State colors draw glyphs, 7pt dots, timing bars, and badge numerals. In light appearance pass and pending are below 4.5:1 on the chrome surface, so the words beside a state stay in text tokens.

### Neutral
The ramp, step 0 to 10. Light: #FFFFFF, #FAFAFA, #F4F4F5, #EBEBED, #DEDEE1, #C8C8CD, #A0A0A8, #6C6C75, #4E4E56, #2E2E33, #18181B. Dark: #111113, #18181B, #1E1E21, #26262A, #303035, #3E3E44, #5A5A62, #8A8A93, #A6A6AE, #D4D4D8, #F4F4F5.
- **Strip Ground** (strip-ground, step 3 light / 0 dark): behind the tab strip and the page content area.
- **Chrome Surface** (chrome-surface, step 1 / 2): toolbar, selected tab, bookmarks bar, find bar, dev panel, command bar, Peek card, Nano-authored web pages.
- **Field Well** (field-fill, step 3 / 1): the resting address field and the context chip.
- **Editing Field** (field-editing, step 0 / 0): the address field while focused.
- **Hover** (hover-fill, step 4 / 3) and **Pressed** (pressed-fill, step 5 / 4): tabs, icon buttons, bookmarks, chips, selected command row.
- **Hairline** (hairline, step 4 / 4): every 1px separator and every floating-panel border.
- **Text** primary (step 10), secondary (step 8), tertiary (step 7), disabled (step 5).

### Named Rules
**The Action-Only Accent Rule.** Teal marks focus, selection, progress, and the primary action. It never fills a resting surface, never tints a header, and never decorates. The selected command row and selected dev tab are neutral (hover fill), not teal.

**The Convention Rule.** State hues mean exactly what an engineer expects (green pass, amber pending, red fail, purple merged) and nothing else. A draft or not-planned state is tertiary text, not a fifth hue.

**The Legible Favicon Rule.** In dark appearance, a glyph-on-transparent favicon that is dark and near-monochrome (mean luminance under 0.22, chroma under 0.15, under 70% coverage) is drawn as a template in secondary text. SVG favicons are rendered from their light variant with their `prefers-color-scheme: dark` blocks removed, so the icon keeps its full shape. Filled or colorful favicons are untouched.

## Typography

**Body Font:** SF Pro Text (system font)
**Label/Mono Font:** SF Mono (monospaced system font), tabular figures

**Character:** Platform type at small, careful sizes; weight, not size, carries hierarchy (the selected tab goes from 400 to 500 at the same 12pt). Mono marks anything machine-readable, so a URL or a duration reads as data at a glance.

### Hierarchy
- **Command input** (400, 16pt): the command bar's query field only.
- **Panel heading** (600, 14pt): the PR title in the GitHub context popover. The GitHub sign-in panel's heading is 15pt semibold and its device code 28pt semibold mono.
- **Title** (600, 13pt): popover titles (Downloads, Review queue).
- **Field** (400, 13pt): address field text and placeholder, command row titles (500 when selected).
- **Body** (400, 12pt): tab titles, dev panel section tabs, popover body copy, bookmarks, find field.
- **Label** (400, 11pt): row subtitles, guide-word titles, dev filter chips, metadata.
- **Mono** (400, 12pt): the address field's path at rest, Peek host, console text, storage keys (500) and values, repo slug and branch refs.
- **Mono small** (11pt): command row URLs, context chip (500), timing columns, review-queue refs; 10pt for guide-word counts (500) and ruler ticks.
- **Badge** (600, 9pt, tabular): error, queue, and download counts on toolbar buttons.

Nano-authored web pages use the same faces through `-apple-system, system-ui` and `ui-monospace, SFMono-Regular`: 13px/1.5 body, 20px/600 heading at -0.01em, 12px mono code; the JSON viewer and view source are 12px mono at 1.6 and 1.55.

### Named Rules
**The Mono Means Data Rule.** SF Mono sets URLs and paths, refs and slugs, counts, timings, and code. Prose, titles, and labels are never mono, and figures that sit in a line of SF Pro use tabular (monospaced) digits.

**The Host First Rule.** A URL reads host in primary SF Pro, remainder in tertiary SF Mono, with scheme and "www." dropped. The address field, command rows, and Peek header all follow it; focusing the address field shows the full URL, selected.

## Layout

The window is a fixed vertical stack: tab strip (40pt, the native compact titlebar height, so traffic lights center untouched; 80pt leading inset, 12pt in full screen), toolbar (36pt), optional bookmarks bar (28pt, off by default), optional find bar (32pt), the page edge to edge, and the optional dev panel at the bottom (resizable from 120pt to 80% of window height). Each chrome row ends in one hairline.

Tabs run 120 to 200pt wide with 4pt gaps and a centered 16pt hairline separator between unselected neighbors; pinned tabs are 40pt icon-only. Past the minimum width the strip scrolls whole tabs and shows a guide word at each overflowing edge. The toolbar holds back, forward, reload at left (28pt buttons, 2pt apart, 8pt from the edge), the flexing address field, then the right cluster.

Spacing is a 4pt grid for structure (row heights, gaps, insets of 4, 8, 12, 16, 20pt) with 2pt half steps inside controls (2pt between buttons, 6pt list padding, 10pt and 14pt control insets). Popovers pad 14pt; sheets and Settings pad 20pt. The command bar is 640pt wide (window width minus 48pt when narrower), centered, 12pt below the chrome. Peek insets its card 7% of width (min 24pt) and 5% of height (min 16pt). Split view divides the content with a 1pt hairline.

## Elevation & Depth

Nano is flat. Docked chrome conveys depth only by tonal step: strip ground sits one or two ramp steps below the chrome surface, and the selected tab shares the toolbar's surface so the two read as one plane. Floating surfaces (command bar, address dropdown) are opaque chrome surface with a 1px hairline border and the standard macOS window shadow. Peek separates from the page with a scrim of text-primary at 18% opacity behind a hairline-bordered card.

### Shadow Vocabulary
- **Floating panel** (system `NSWindow.hasShadow`): command bar and address dropdown only.

### Named Rules
**The Floating-Only Shadow Rule.** Shadow belongs only to surfaces that float above the page. Docked chrome, tabs, chips, buttons, and panels never cast one.

**The Opaque Rule.** Every Nano-drawn surface is an opaque ramp step. Translucency, blur, and gradients are not part of this world; the only alpha in the chrome is the Peek scrim and the 7% fail/pending tint on console error and warning rows.

## Shapes

Continuous-curve corners throughout. Controls (tabs, icon buttons, address field, context chip, command rows, web buttons and inputs) take 6pt; floating panels (command bar, address dropdown, Peek card) take 10pt; inner chips inside panels (dev section tabs, console level chips, bookmark items) take 5pt; the tab close button takes 4pt; status dots are 7pt circles. The selected tab rounds only its top corners and runs down into the toolbar; unselected tab hover fills are fully rounded and inset 3pt top and bottom. Borders are 1px hairlines, or 1.5pt teal for the editing ring.

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
- **Editing:** editing-field fill and a 1.5pt teal ring; the full URL, all selected; the star hides.
- **Dropdown:** command rows in a 10pt floating panel with a hairline border.

### Context Chip
On any GitHub page: field well, 6pt, 24pt tall, `owner/repo · #number` in 11pt medium mono secondary, a leading state glyph and a trailing 7pt checks dot. Hover and pressed fills match the icon button.

### Command Bar
- **Container:** 640pt, 10pt radius, chrome surface, 1px hairline border, system shadow; 16pt query field with an 18pt search glyph, a hairline under the field.
- **Rows:** 40pt tall, 10pt inset, 6pt radius, 16pt icon, 10pt gap; 13pt title, URL subtitle in 11pt mono (host secondary, path tertiary) or 11pt tertiary text; trailing hint (Switch to Tab, Search, Open, or the shortcut) in 11pt tertiary tabular.
- **Selected:** hover fill and a medium-weight title. Pointer hover moves the selection; streaming results never move the selected row.

### Dev Panel
An editor pane on chrome surface below a draggable hairline.
- **Header:** 32pt, section tabs 24pt tall at 5pt radius, 12pt (medium and primary when selected, on hover fill); the console tab carries a fail-red error count.
- **Level chips:** 22pt, 5pt, 11pt; on: hover fill, primary text, level glyph in its state color; off: no fill, tertiary.
- **Tables:** 11 to 12pt mono rows; column headers 11pt medium in a 22pt row above a hairline; key columns 180 to 200pt in medium mono; error and warning rows tinted 7%.
- **Network timing:** every bar shares one exact time scale with the ruler; 6pt bars, hairline ticks, 10pt mono tick labels.

### Peek Card
The linked page floats over the current one: the scrim, then a 10pt card on chrome surface with a hairline border; a 36pt header with the host in 12pt mono secondary and three icon buttons (split, tab, close). Opens with a 0.97 to 1 scale and fade over 120ms ease-out.

### Split View Focus Line
Two pages share the content area divided by a 1pt hairline (5pt drag target). The focused pane carries a 2pt teal line along its top edge; one pane has no line.

### Nano Web Pages
The error page, JSON viewer, and view source mirror the chrome tokens through CSS variables with light and dark sets: chrome surface background, primary text, tertiary muted text, hairline rules, accent for focus and selection (30% mix for `::selection`). The error page is a 520px column with a 20px heading, muted body, the URL in mono above a hairline, and one filled retry button (deep teal light, accent dark) with a 2px accent focus outline. Viewer controls are 6px-radius hairline-bordered inputs and buttons with hover fill and an accent border on focus.

## Do's and Don'ts

### Do:
- **Do** take every surface, separator, and text color from the neutral ramp, in both appearances.
- **Do** keep chrome surfaces opaque and flat, separated by 1px hairlines one ramp step apart.
- **Do** reserve teal for focus, selection, progress, and the primary action; use accent-deep behind white text in light appearance.
- **Do** use pass, pending, fail, and merged only for their engineering meanings, as glyphs, dots, bars, and counts.
- **Do** set URLs, paths, refs, counts, timings, and code in SF Mono with tabular figures, host first.
- **Do** use 6pt radius on controls and 10pt on floating panels, continuous curve.
- **Do** animate hover at 80ms and panels at 120ms ease-out, and drop to zero under Reduce Motion.
- **Do** tint dark monochrome favicons in dark appearance rather than leaving them invisible.
- **Do** let system containers (menus, popovers, Settings, alerts) keep their native macOS material.

### Don't:
- **Don't** add gradients, glass, blur, or translucency to Nano-drawn chrome.
- **Don't** cast shadows from docked chrome, tabs, chips, or buttons; shadow is for floating surfaces only.
- **Don't** fill resting surfaces or selected list rows with teal.
- **Don't** set prose, titles, or labels in SF Mono.
- **Don't** set small text in light-appearance teal, pass, or pending; their words stay in text tokens.
- **Don't** animate anything on the input path (typing, tab switching, row selection).
- **Don't** introduce a second icon family; SF Symbols only.
