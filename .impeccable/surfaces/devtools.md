---
version: 1
slug: devtools
primary_target: App/DevTools
related_targets: [Packages/BrowserKit/Sources/BrowserKit/DevTools]
---

# Devtools workbench

Mode: Operate. Native macOS AppKit + SwiftUI; the web detector does not apply to shipping UI.

Audience/job: engineers investigating console errors, API requests, elements and site state during daily browsing. Public WebKit APIs only. All capture stays in memory.

## Direction contract

THESIS: A readable debugging workbench with balanced event lists and selected-item details, rather than an undifferentiated log dump.

OWN-WORLD: Inherit Nano's opaque neutral surfaces, hairlines, SF Pro labels, SF Mono data, semantic status colors and action-only teal. Controls retain native keyboard and accessibility behavior.

STORY: Find an error or request, select it without losing surrounding context, read the evidence and copy what is useful. Inspect an element or site storage without changing tabs.

FIRST VIEWPORT: Five section tabs and the inspected origin above a compact search/action toolbar. A resizable split assigns roughly 60% to events and 40% to details. Console input anchors the bottom. Small widths replace the list with selected details and Back. Detached tools retain the same composition and stay bound to their tab.

FORM: Tabbed workbench, seed ec1b2e71. User approved composition A, Split inspector, on 2026-10-28. Reference: .impeccable/mocks/workbench.html#split. Built-in image generation failed twice with HTTP 500, so three browser-rendered visual mockups replaced generated raster comps; all were shown before approval. No raster assets ship.

Signature interaction: Selecting evidence reveals full detail without moving the selection or scrolling the list; incoming logs do not steal reading position.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance


## Finished implementation

Shipped as native AppKit + SwiftUI in `App/DevTools`, with scripts and in-memory records owned by BrowserKit. Five tabs retain the approved balanced list/detail composition. Header 36pt, toolbar 40pt, minimum rows 28pt, count/status footer 24pt. Default dock is 300pt with a preferred 200pt minimum. The persisted split starts at 58%; below 760pt selected details replace the list with Back to list. Detaching retains the inspected tab binding.

Selected evidence rows stay neutral with primary/secondary text in active and inactive windows. Native selected segments and checkboxes use Theme.controlSelectionTint; action text uses text-safe Theme.accentText. No new identity, global ramp, type family or raster asset was introduced. DESIGN.md's Dev Panel entry records the finished component; its neutral rows and dock sizing match the updated devtools references in that file.

Evidence: 11 valid native snapshots in `.impeccable/review/devtools`, spanning light/dark docked, 1280pt detached and 640pt compact states. Fresh independent full review was followed by a ship verdict scoring the listed selected-row and control-label contrast corrections resolved. BrowserKit's 93 tests passed and the Debug app built. Review covers observed source and UI; no live VoiceOver or Increase Contrast session or raster pixel-diff score is claimed.
