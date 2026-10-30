# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS app (AppKit + SwiftUI). Impeccable ships no macOS platform reference, so Apple's Human Interface Guidelines for macOS are the platform authority: menu bar, keyboard shortcuts, window behavior, full screen, accessibility.

## Stack

Swift 6 · AppKit (window, tab strip, toolbar, web view hosting, menus) + SwiftUI (command bar, popovers, panels, settings) · WebKit (`WKWebView`, `WKWebExtension`) · macOS 26+ · XcodeGen project · GRDB for SQLite/FTS5. Not sandboxed (hardened runtime only), like Chrome: extensions' native messaging hosts can't run inside another app's sandbox. Engine chosen by the user after weighing Blink/CEF: WebKit for native API, footprint, and battery.

## Users

Software engineers who live in the browser between GitHub, docs, local apps, and the inspector. First user is the author (Josh), as his daily driver on a Mac. Success: Koala replaces Chrome/Arc for normal engineering work.

## Product Purpose

Koala is a fast, native Mac browser that understands the engineer's web. Pages lead; chrome recedes; the context an engineer needs (which repo, which PR, is CI green, what the console says) shows up where the eye already is, without opening another tab.

## Positioning

A native WebKit browser that treats GitHub and devtools as first-class parts of the browser rather than as websites like any other: PR and CI state live in the tab strip, a native dev panel shows console, network, site storage, and page tools. Traditional layout (top tab strip + toolbar), not a sidebar browser.

## Operating Context

- Long sessions with many tabs: PRs, issues, code views, docs (MDN, crates, npm), localhost apps, dashboards.
- Keyboard-first driving: command bar, tab switching, copy link, split view for PR + preview or docs + app.
- Constant back-and-forth with a local editor (VS Code, Cursor, Xcode) and terminal.

## Capabilities and Constraints

v1 scope:
- Tabs (pinned, reorder, tear-off), address field, full macOS menu with standard shortcuts.
- Command bar (Cmd+K): tabs, commands, keyword search (`gh`, `mdn`, `npm`, `crates`, `pypi`, `go`, `so`, `docs`), GitHub, bookmarks, history, web suggestions.
- Peek (Shift+click link opens floating preview; promote to tab without reload). Split view (two pages in one tab).
- History and bookmarks, each with a native page (`koala://history`, `koala://bookmarks`), import from Chrome / Brave / Arc / Safari. Session restore (optional), recently closed.
- Private windows: one in-memory data store shared by open private windows, gone when the last closes; no history, session, favicons, or extensions.
- Sites: camera and microphone choices remembered per site, per-site zoom, session-only certificate exceptions, website data, all in Settings › Sites. An address field warning for insecure, mixed, or accepted-certificate pages.
- Robustness: HTTP auth prompts, Visit Anyway for untrusted certificates, crash recovery, reload when a refused local server comes back, background tabs sleep (configurable) unless they hold typed text or play sound. Tab audio indicator and mute.
- Downloads manager. Web extensions via `WKWebExtension`: Chrome Web Store installs, a compatibility script that stands in for Chrome APIs WebKit lacks, and Chrome's native messaging hosts.
- GitHub (GitHub App device flow, token in Keychain): PR/issue state and CI status in tabs, review queue (and Dock badge), permalinks, open failing check.
- Devtools: Web Inspector (public API only: `isInspectable`, opened from the context menu) plus a resizable bottom-docked or detached native workbench bound to its inspected tab. Four sections: Console (argument snapshots, repeated-message groups, evaluation/history, preserve log and follow controls); Network (resource timing plus explicitly enabled per-tab fetch/XHR capture, script-visible headers, bounded text payloads, formatted/raw JSON and Copy as cURL); Storage (current-site cookies and editable local/session storage); Page (force light/dark, responsive widths, enable/disable JS, reload from origin, view source, copy screenshot, save PDF and observed performance). JSON viewer remains a page utility.
- Detailed network capture is limited to 64 KiB per body and an 8 MiB retained payload budget; closing tools or crossing origins stops it. Browser-added credentials, iframe requests and binary/streaming bodies are unavailable. Inspection records stay in memory; presentation preferences may persist. Page performance values are local observations, not field scores or a complete INP measurement.
- Copy as Markdown, Share, Handoff. Link context menu: Peek, Split View, Copy as Markdown.

Explicitly out of v1: password manager, spaces/profiles, tab auto-archive, automatic localhost dev mode, private WebKit SPI (two exceptions, each because macOS WKWebView has no public equivalent: `_setAllowsPictureInPictureMediaPlayback:` for Picture in Picture, and `_isPlayingAudio` with `_setPageMuted:` for the tab audio indicator and mute), implementing Chrome-only extension APIs (they get inert stand-ins).

Terminology: "tab strip", "toolbar", "address field", "command bar", "Peek", "split view", "dev panel", "review queue".

## Brand Commitments

- Name: **Koala**. Bundle ID `com.joshoettinger.koala`. App icon: a koala silhouette.
- Must not read as an Arc or Safari clone. Must never feel laggy on input. Must never feel non-native.
- Standing visual preference: grounded in modern pro Mac software, no metaphor worlds. Craft bar: Linear and Zed.

## Evidence on Hand

Koala silhouette app icon. No screenshots or users beyond the author. Do not fabricate testimonials, benchmarks, or adoption claims.

## Product Principles

1. Input latency is a feature: every keystroke, tab switch, and panel open is measured against a budget.
2. Native before custom: use AppKit, WebKit, and macOS conventions unless a custom control is clearly better.
3. The page leads: chrome is thin, quiet, and gives space back.
4. Every action is keyboard-reachable and lives in the menu bar.
5. Engineer context surfaces where the eye already is: tab strip, toolbar, command bar.

## Accessibility & Inclusion

Full VoiceOver labels for custom chrome (tab strip, chips, panels), full keyboard access, respect Reduce Motion, Reduce Transparency, and Increase Contrast.
