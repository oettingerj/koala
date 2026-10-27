# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS app (AppKit + SwiftUI). Impeccable ships no macOS platform reference, so Apple's Human Interface Guidelines for macOS are the platform authority: menu bar, keyboard shortcuts, window behavior, full screen, accessibility.

## Stack

Swift 6 · AppKit (window, tab strip, toolbar, web view hosting, menus) + SwiftUI (command bar, popovers, panels, settings) · WebKit (`WKWebView`, `WKWebExtension`) · macOS 26+ · XcodeGen project · GRDB for SQLite/FTS5. Engine chosen by the user after weighing Blink/CEF: WebKit for native API, footprint, and battery.

## Users

Software engineers who live in the browser between GitHub, docs, local apps, and the inspector. First user is the author (Josh), as his daily driver on a Mac. Success: Nano replaces Chrome/Arc for normal engineering work.

## Product Purpose

Nano is a fast, native Mac browser that understands the engineer's web. Pages lead; chrome recedes; the context an engineer needs (which repo, which PR, is CI green, what the console says) shows up where the eye already is, without opening another tab.

## Positioning

A native WebKit browser that treats GitHub and devtools as first-class parts of the browser rather than as websites like any other: PR and CI state live in the tab strip, a context chip names the repo and PR, a native dev panel shows console, network, storage, and vitals. Traditional layout (top tab strip + toolbar), not a sidebar browser.

## Operating Context

- Long sessions with many tabs: PRs, issues, code views, docs (MDN, crates, npm), localhost apps, dashboards.
- Keyboard-first driving: command bar, tab switching, copy link, split view for PR + preview or docs + app.
- Constant back-and-forth with a local editor (VS Code, Cursor, Xcode) and terminal.

## Capabilities and Constraints

v1 scope:
- Tabs (pinned, reorder, tear-off), address field, full macOS menu with standard shortcuts.
- Command bar (Cmd+T): tabs, commands, keyword search (`gh`, `mdn`, `npm`, `crates`, `pypi`, `go`, `so`, `docs`), GitHub, bookmarks, history, web suggestions.
- Peek (Shift+click link opens floating preview; promote to tab without reload). Split view (two pages in one tab).
- History, bookmarks, import from Chrome / Brave / Arc / Safari. Session restore, recently closed.
- Downloads manager. Web extensions via `WKWebExtension`.
- GitHub (OAuth device flow, token in Keychain): PR/issue state and CI status in tabs, toolbar context chip, review queue, permalinks, open in local editor.
- Devtools: Web Inspector (public API only: `isInspectable`, opened from the context menu), native dev panel (console, network timing, storage, vitals), page tools (force light/dark, hard reload, disable JS, view source, JSON viewer, responsive widths, full-page screenshot).
- Copy as Markdown.

Explicitly out of v1: password manager, spaces/profiles, tab auto-archive, automatic localhost dev mode, private WebKit SPI, Chrome-only extensions.

Terminology: "tab strip", "toolbar", "address field", "command bar", "Peek", "split view", "dev panel", "context chip", "review queue".

## Brand Commitments

- Name: **Nano**. Bundle ID `com.joshoettinger.nano`.
- Must not read as an Arc or Safari clone. Must never feel laggy on input. Must never feel non-native.
- Standing visual preference: grounded in modern pro Mac software, no metaphor worlds. Craft bar: Linear and Zed.

## Evidence on Hand

None. No logo, icon, screenshots, or users beyond the author. Do not fabricate testimonials, benchmarks, or adoption claims.

## Product Principles

1. Input latency is a feature: every keystroke, tab switch, and panel open is measured against a budget.
2. Native before custom: use AppKit, WebKit, and macOS conventions unless a custom control is clearly better.
3. The page leads: chrome is thin, quiet, and gives space back.
4. Every action is keyboard-reachable and lives in the menu bar.
5. Engineer context surfaces where the eye already is: tab strip, toolbar, command bar.

## Accessibility & Inclusion

Full VoiceOver labels for custom chrome (tab strip, chips, panels), full keyboard access, respect Reduce Motion, Reduce Transparency, and Increase Contrast.
