# MaktoNoDpi

A native macOS app (Swift/SwiftUI) that bypasses DPI-based internet filtering. It provides automatic
strategy iteration, a menu-bar status item, a SOCKS5 proxy via a bundled `tpws` binary, DNS override,
QUIC block via `pfctl`, login item, and in-app update checks powered by Sparkle. The app lives entirely
in the menu bar (no Dock icon).

## Architecture

```
Core/                   Swift Package (SPM) - pure logic, CLI-testable with swift test
  Sources/MaktoNoDpiCore/
    ProxyEngine.swift   strategy iteration loop
    SystemConfig.swift  proxy on/off, DNS via networksetup
    BinaryManager.swift locate / chmod bundled tpws
    ...

App/                    Xcode SwiftUI app - thin shell over Core
  MaktoNoDpi/
    MaktoNoDpiApp.swift   @main, MenuBarExtra scene, AppDelegate, EmergencyCleanup
    ProxyController.swift @MainActor ObservableObject bridging Core to UI
    ContentView.swift     menu-bar popover dashboard (services, status, details, footer)
    SettingsView.swift    autostart / autoconnect / strategy / custom domains
    UpdaterController.swift Sparkle wrapper
    LoginItem.swift       SMAppService.mainApp wrapper

scripts/
  package.sh            build Release .app and produce dist/MaktoNoDpi.dmg
```

## Requirements

- macOS 13.0 or later
- Xcode 15+ with Swift 6 toolchain
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
# Regenerate the Xcode project (required after editing project.yml or adding sources)
cd App && xcodegen generate

# Build (Debug)
xcodebuild \
  -project App/MaktoNoDpi.xcodeproj \
  -scheme MaktoNoDpi \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

# Run Core unit tests (no Xcode needed)
cd Core && swift test
```

## Package (.app + .dmg)

```bash
bash scripts/package.sh
# Produces: dist/MaktoNoDpi.dmg
```

The script regenerates the project, builds a Release .app (unsigned), then stages it with an
`/Applications` symlink and compresses it into a UDZO DMG.

## Install

1. Open `dist/MaktoNoDpi.dmg`.
2. Drag `MaktoNoDpi.app` to `/Applications`.
3. **Remove the quarantine flag** (required because the app is unsigned):
   ```bash
   xattr -cr /Applications/MaktoNoDpi.app
   ```
   macOS Gatekeeper blocks unsigned apps downloaded from the internet. The `xattr -cr` command
   strips the `com.apple.quarantine` extended attribute so the app can launch. This is the standard
   approach for distributing unsigned macOS apps.
4. Open `MaktoNoDpi.app` - it appears in the menu bar.

## Notes

- The app is **unsigned** (no Developer ID). Full Sparkle auto-updates require a signed build;
  see `docs/reference/updates.md` for the release signing path.
- Privileged operations (pfctl QUIC block, /etc/hosts edits) are batched into a single
  `osascript ... with administrator privileges` prompt per connection attempt.
- The bundled `tpws` binary is a universal (arm64 + x86_64) macOS build. To rebuild it from
  source, run `bash scripts/build-tpws.sh`.
