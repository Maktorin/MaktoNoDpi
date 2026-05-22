# Auto-Updates via Sparkle

## Setup

MaktoNoDpi uses [Sparkle 2.6+](https://sparkle-project.org/) for in-app auto-updates, integrated via Swift Package Manager.

- SPM package: `https://github.com/sparkle-project/Sparkle`, minimum version `2.6.0`
- Product used: `Sparkle` (framework target)
- Entry point: `UpdaterController.swift` - a thin `@MainActor` `ObservableObject` wrapping `SPUStandardUpdaterController`

The "Check for Updates" menu item lives under the application menu (`CommandGroup(after: .appInfo)`) and calls `updater.checkForUpdates()`.

## Info.plist Keys

| Key | Value |
|-----|-------|
| `SUFeedURL` | `https://github.com/Maktorin/MaktoNoDpi/releases/latest/download/appcast.xml` (placeholder - set real URL at release) |
| `SUEnableInstallerLauncherService` | `true` |
| `SUPublicEDKey` | `""` (placeholder - see EdDSA section below) |

## Unsigned Dev Builds

In development builds (`CODE_SIGNING_ALLOWED: NO`):

- Sparkle compiles and links without issue - the framework is a build-time dependency only.
- The "Check for Updates" menu item appears and Sparkle's UI opens normally.
- **Full auto-update installation requires the app to be signed with a Developer ID certificate.**
  Without signing, Sparkle can download an update but macOS will block installation of the
  unsigned bundle.
- This is a **runtime-only** concern, not a build failure.

## Release Path: Developer ID + EdDSA

The chosen distribution path is direct download (not Mac App Store), signed with a Developer ID:

1. **Sign the app** with a Developer ID Application certificate (`CODE_SIGN_IDENTITY: Developer ID Application: ...`)
2. **Generate an EdDSA key pair** using Sparkle's bundled tool:
   ```
   ./bin/generate_keys
   ```
   This outputs a private key (store securely, never commit) and a public key.
3. **Set `SUPublicEDKey`** in `project.yml` `info.properties` to the generated public key string.
4. **Sign each update** with `sign_update` before publishing to the appcast.
5. **Notarize** the app with `xcrun notarytool` before publishing (required for Gatekeeper on macOS 10.15+).

## Appcast Format

The `appcast.xml` at the `SUFeedURL` must be a valid Sparkle 2 appcast. Minimal structure:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MaktoNoDpi</title>
    <item>
      <title>Version 1.0.0</title>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <enclosure url="https://...MaktoNoDpi.dmg"
                 sparkle:edSignature="<signature from sign_update>"
                 length="<bytes>"
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

## Summary

- Dev builds: Sparkle links and UI works; full update install is blocked at runtime (unsigned).
- Release builds: sign with Developer ID, generate EdDSA keys, notarize, publish appcast.
- `SUPublicEDKey` in `project.yml` is a placeholder empty string - replace with the real key at release time.
