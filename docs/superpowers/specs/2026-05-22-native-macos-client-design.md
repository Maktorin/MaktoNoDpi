# MaktoNoDpi macOS Client - Design

**Date:** 2026-05-22
**Status:** Approved (design)
**Source project studied:** https://github.com/Maktorin/MaktoNoDpi (Electron, v2.0.16)

## Goal

Replace the Electron-based MaktoNoDpi macOS client with a native Swift/SwiftUI
application at **full feature parity**, distributed as a direct `.app`/`.dmg`
(not via the Mac App Store, not sandboxed).

## Locked decisions

- **Platform / tech:** native macOS, Swift + SwiftUI.
- **Distribution:** direct `.app`/`.dmg`, no App Store, not sandboxed.
- **Scope:** full parity with the Electron client.
- **tpws binary:** bundled in the `.app` (universal arm64+x86_64) AND updatable
  from the network when available.
- **Privilege elevation:** on-demand `osascript … with administrator
  privileges`, batching all privileged commands of one connection into a single
  password prompt (variant A). A signed `SMAppService` privileged helper is not
  viable without a Developer ID certificate.
- **App auto-updates:** Sparkle (with an appcast feed) in v1.

## Background: how the Electron app works (facts from source)

MaktoNoDpi is an Electron wrapper around `zapret` (bol-van). It has no network
logic of its own; it runs external binaries and manages system settings.

macOS branch (the only one relevant here):

- Binary: `tpws` - a TCP-only SOCKS5 proxy listening on `127.0.0.1:1080`.
- Enabling bypass: `networksetup` sets a system SOCKS proxy + clean DNS
  (1.1.1.1 / 8.8.8.8), `pfctl` blocks UDP 443 (QUIC) and Discord voice port
  ranges (forcing TCP through tpws), and `/etc/hosts` is updated for Discord
  voice servers.
- Strategy auto-select: `startProxy` iterates ~45 flag combinations
  (split/disorder/oob/tlsrec/methodeol/multi-profile), starting with the last
  known-working one. For each: spawn tpws -> wait ~2s -> verify port 1080 is
  listening -> enable system SOCKS proxy -> real connectivity test. First
  strategy that passes is kept and saved as `lastWorkingStrategy`.
- Connectivity test: `curl --socks5-hostname` to YouTube + Discord API/CDN, plus
  a raw TLS WebSocket handshake to `gateway.discord.gg` (the check Discord itself
  performs to load).
- Cleanup on any exit (normal, crash, kill): system proxy / DNS / pf are
  restored - this is an advertised feature.
- tpws is downloaded at runtime from zapret GitHub releases into a writable
  userData dir (fragile: GitHub may be the very thing being blocked).
- IPC surface (preload): start/stop/getStatus, settings (autostart/autoconnect),
  strategies, logs, custom domains, updates; events status/log/download-progress.

## Architecture

A native Swift/SwiftUI app reproducing the proven scheme: **tpws as a child
SOCKS5 process + system SOCKS proxy**. Only the surrounding harness changes:

| Electron | Native |
|---|---|
| `child_process.spawn` | `Foundation.Process` |
| `sudo-prompt` | `osascript ... with administrator privileges` (batched) |
| Electron `Tray` | `NSStatusItem` |
| `electron-updater` | Sparkle |
| `app.setLoginItemSettings` | `SMAppService.mainApp` login item |
| renderer + IPC | SwiftUI views + `ProxyController` (`@MainActor ObservableObject`) |

The SwiftUI layer is fully decoupled from Core via `ProxyController`, which
publishes state (`disconnected/searching/connected/error`, strategy progress,
ring-buffer log) and accepts `connect`/`stop` commands - mirroring the current
IPC contract.

## Components (single responsibility each)

| Module | Responsibility | Depends on |
|---|---|---|
| `ProxyController` | UI-facing state, connect/stop commands, log/status events | ProxyEngine |
| `ProxyEngine` | strategy iteration loop (analog of `startProxy`): spawn tpws -> port listening? -> proxy on -> test -> remember working | Strategies, SystemConfig, ConnectivityTester, BinaryManager |
| `Strategies` | ~45 darwin strategies, ported 1:1 from `buildDarwinStrategies`; `lastWorkingStrategy` first | - |
| `BinaryManager` | bundled tpws (Resources) -> copy to Application Support bin dir, `chmod 755`; network update; generate host-lists and `.bin` pattern files (fake QUIC initial / TLS ClientHello) | - |
| `SystemConfig` | `networksetup` (SOCKS proxy + DNS), enumerate active network services | PrivilegedRunner |
| `PrivilegedRunner` | batch privileged commands (pfctl QUIC block + `/etc/hosts` edit) into one `osascript ... with administrator privileges` | - |
| `ConnectivityTester` | `curl --socks5-hostname` to YouTube + Discord API/CDN + raw TLS WebSocket handshake to gateway (ported 1:1) | - |
| `SettingsStore` | UserDefaults: autoStart, autoConnect, selectedStrategy, customInclude/Exclude domains | - |
| `TrayController` | NSStatusItem menu: status, Connect/Disconnect/Quit | ProxyController |
| `LoginItem` | autostart via `SMAppService.mainApp` (no signing required) | - |
| `Updater` | Sparkle + appcast | - |

## Data: ported constants (byte-for-byte parity)

Ported verbatim from `main.js` so generated files match the Electron client:

- Host lists: `HOST_LIST_GENERAL`, `HOST_LIST_GOOGLE`, `HOST_LIST_DISCORD`,
  `HOST_LIST_EXCLUDE`, `IPSET_EXCLUDE`, `IPSET_ALL`; derived `list-all.txt`.
- Pattern files: fake QUIC initial packet and fake TLS ClientHello generators
  (`quic_initial_www_google_com.bin`, `tls_clienthello_www_google_com.bin`,
  `_4pda_to.bin`, `_max_ru.bin`).
- The ~45 darwin strategy definitions (tiers 1-14).
- Discord voice-server hosts entries (all regions).

## Connection flow (`ProxyEngine.connect()`)

1. Ensure binary (bundled -> copy out; optionally check network update),
   generate host-lists + `.bin` files.
2. Enumerate active network services. One `osascript` prompt: load pf rules
   (block UDP 443 / Discord voice ranges) + update `/etc/hosts` + (if it needs
   root) set clean DNS.
3. Iterate strategies: `spawn tpws --port 1080 --socks ...` -> wait ~2s ->
   verify 1080 is listening -> `networksetup` enable system SOCKS ->
   `ConnectivityTester` (YouTube + Discord + gateway WS). First pass ->
   `connected`, save as `lastWorking`, break.
4. All fail -> `error(.allStrategiesFailed)`, full revert.

**Cleanup (critical, matches FAQ):** on `stop()`, tpws crash, app quit, and any
termination - disable system proxy, restore DNS, reload clean `/etc/pf.conf`,
kill tpws (`pkill -f tpws`). Register on `NSApplication.willTerminate` plus
SIGTERM/SIGINT handlers. Proxy/DNS revert should be promptless where possible;
whether pf-restore needs root will be verified on a real Mac (see Open risks).

## Error handling

Same codes as today, modeled as a Swift `enum ProxyError`: `downloadFailed`,
`noBinary`, `networkUnavailable`, `allStrategiesFailed`, `processCrashed`.
Log is a ring buffer (last 100 entries; types info/success/warning/error),
published to the UI and to `os.Logger`. No `print` in production code.

## Testing

- **Unit:** `Strategies` (argument assembly correctness), `BinaryManager`
  (host-list / `.bin` generation byte-for-byte vs Electron), parsing of
  `networksetup -listallnetworkservices`.
- **Integration (real Mac):** full connect/stop; system proxy actually set/cleared
  (`networksetup -getsocksfirewallproxy`); pf reverts; no stray tpws process
  after quit.
- TDD for modules with pure logic (Strategies, parsers).

## Open risks (to resolve during planning/implementation)

1. **Building tpws for macOS.** A universal binary is needed for bundling.
   zapret releases may not ship a macOS build, so tpws may need to be compiled
   from source (`make`) for arm64 + x86_64 and combined with `lipo`. This is a
   separate build step - to be confirmed during planning.
2. **Does `networksetup` need root?** The Electron code calls it without sudo.
   To be verified on a real Mac; if it does, fold it into the same batched
   `osascript`.

## Project location

New repository at `~/maktonodpi/` (separate from the Electron clone).
This spec lives at
`~/maktonodpi/docs/superpowers/specs/2026-05-22-native-macos-client-design.md`.
