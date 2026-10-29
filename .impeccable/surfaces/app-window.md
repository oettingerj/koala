---
version: 1
slug: "app-window"
primary_target: "App/Window"
related_targets: []
---

# Browser window (tab strip, toolbar, command bar, panels)

Scope: Koala's main window chrome and its floating surfaces (command bar, Peek, popovers, dev panel). Mode: Operate.

Audience/job: engineers driving many tabs by keyboard between GitHub, docs, and localhost. Success: chrome is read at a glance, never waited on.

Constraints: native macOS conventions (HIG), macOS 26+, appearance follows the system (light and dark are equal citizens). Craft bar: Linear and Zed. Not an Arc or Safari clone; no metaphor world (user re-rolled two conceptual hands and asked for grounding in modern pro Mac software).

## Direction contract

THESIS: A pro tool's browser. Neutral, opaque, precise chrome at Linear's typographic care and Zed's density and instant response. Refuses Safari's soft glass toolbar and Arc's color-drenched sidebar.

OWN-WORLD: One 11-step neutral ramp is the only tonal token set (light and dark derived). One accent, Koala teal, marks only focus, selection, and the primary action. State colors follow engineer convention: pass green, pending amber, fail red, merged purple. SF Pro Text for chrome at 12–13pt; SF Mono for URLs paths, refs, counts, and timings with tabular figures. Opaque surfaces, 1px hairlines one ramp step apart, 6pt radius on tabs and controls, 10pt on floating panels, shadow only on floating surfaces. 4pt grid everywhere.

STORY: The engineer sees which tab is which PR and whether CI is green without opening it, opens anything with Cmd+K in under a frame's notice, and reads console and timing in a panel that feels like an editor pane.

FIRST VIEWPORT: Row 1 (40pt, the native compact titlebar, so traffic lights center without repositioning): traffic lights, pinned tabs (icon only), tabs (max 200pt, min 120pt, then whole-tab horizontal scroll with guide words at the edges: a drawn chevron, the hidden count in mono, the nearest hidden tab's title; clicking reveals that tab), new-tab button. Selected tab is the toolbar's surface, joined to it; others sit on the strip ground. Row 2 (36pt toolbar): back, forward, reload at left; address field flexes (domain in primary text, path in tertiary mono when unfocused, full URL on focus); right cluster: GitHub context chip on GitHub pages, downloads (only once a download exists), extension actions, review queue, dev panel toggle with error count. Page edge-to-edge below one hairline. The bookmarks bar is an optional third row, off by default (⇧⌘B). Primary action is the address field.

FORM: Category canon executed at Linear/Zed craft (standing exit taken after two re-rolls). Seed key e8fb75b0. Kept disciplines: accent is action-only; closed tabs leave a struck stub as undo for a few seconds; command bar top result preconnects before Enter; dev panel timing bars share one exact time scale; flat fills, no gradients. The command bar and address dropdown share one sectioned list, with local sections above streamed ones, and a preview pane for the selected row.

Signature interaction: Cmd+K command bar opens instantly (pre-built panel), results stream in without moving the highlighted row. Motion grammar: 120ms ease-out for panel open, 80ms for hover/selection, none when Reduce Motion is on; nothing animates on the input path.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
