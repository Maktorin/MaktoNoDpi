# Native macOS MaktoNoDpi Client — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS (Swift/SwiftUI) MaktoNoDpi client at full feature parity with the Electron version, distributed as a direct unsigned `.app`/`.dmg`.

**Architecture:** Reproduce the proven scheme — `tpws` as a child SOCKS5 process + system SOCKS proxy. Pure logic lives in an SPM package (`MaktoNoDpiCore`) that is fully unit-testable from the CLI via `swift test`; the SwiftUI app (`MaktoNoDpi.xcodeproj`) is a thin shell that observes a `ProxyController` and provides the window, menu-bar item, login item, and Sparkle updates. Privileged operations (pfctl QUIC block, `/etc/hosts`) are batched into a single `osascript ... with administrator privileges` prompt per connection.

**Tech Stack:** Swift 6.3 / SwiftUI / AppKit (`NSStatusItem`), Swift Package Manager + Xcode 26, `Foundation.Process`, `osascript`, `networksetup`, `pfctl`, `curl`, Sparkle (app updates), `SMAppService` (login item).

**Reference source:** The authoritative behavior is the Electron client, preserved in this repo at `docs/reference/electron-main.js` (3114 lines) and `docs/reference/electron-preload.js`. Line numbers cited below refer to `docs/reference/electron-main.js`.

**Toolchain (verified on this machine):** `swift` 6.3.2, `xcodebuild` 26.5, `curl` present at `/usr/bin/curl`.

---

## File Structure

```
maktonodpi/
├─ Core/                                  # SPM package — CLI-testable logic
│  ├─ Package.swift
│  ├─ Sources/MaktoNoDpiCore/
│  │  ├─ Models.swift                     # ProxyState, LogEntry, LogType, ProxyError, Strategy
│  │  ├─ HostLists.swift                  # ported domain/ipset constants + file generation
│  │  ├─ PatternFiles.swift               # fake QUIC initial + fake TLS ClientHello generators
│  │  ├─ Strategies.swift                 # 52 darwin strategy definitions (ported)
│  │  ├─ ProcessRunner.swift              # protocol + real impl wrapping Foundation.Process
│  │  ├─ CommandRunner.swift              # protocol + real impl for one-shot shell commands
│  │  ├─ NetworkServices.swift            # parse `networksetup -listallnetworkservices`
│  │  ├─ SystemConfig.swift               # proxy on/off, DNS set/restore (via CommandRunner)
│  │  ├─ PrivilegedRunner.swift           # batch privileged cmds into one osascript prompt
│  │  ├─ HostsData.swift                  # Discord voice / Telegram fallback hosts data
│  │  ├─ ConnectivityTester.swift         # curl SOCKS tests + gateway WebSocket handshake
│  │  ├─ BinaryManager.swift              # locate/copy bundled tpws, chmod, network update
│  │  ├─ SettingsStore.swift              # UserDefaults-backed settings
│  │  └─ ProxyEngine.swift                # the strategy-iteration core (analog of startProxy)
│  └─ Tests/MaktoNoDpiCoreTests/
│     ├─ HostListsTests.swift
│     ├─ PatternFilesTests.swift
│     ├─ StrategiesTests.swift
│     ├─ NetworkServicesTests.swift
│     ├─ SystemConfigTests.swift
│     ├─ ConnectivityTesterTests.swift
│     ├─ SettingsStoreTests.swift
│     └─ ProxyEngineTests.swift
├─ App/                                   # Xcode SwiftUI app target
│  ├─ MaktoNoDpi.xcodeproj
│  └─ MaktoNoDpi/
│     ├─ MaktoNoDpiApp.swift        # @main, app lifecycle, emergency cleanup
│     ├─ ProxyController.swift            # @MainActor ObservableObject bridging Core -> UI
│     ├─ ContentView.swift                # main window: status, connect button, log
│     ├─ SettingsView.swift               # autostart/autoconnect/strategy/custom domains
│     ├─ TrayController.swift             # NSStatusItem menu
│     ├─ LoginItem.swift                  # SMAppService.mainApp wrapper
│     ├─ UpdaterController.swift          # Sparkle wiring
│     ├─ Info.plist                       # LSUIElement handling, SUFeedURL, etc.
│     └─ Resources/bin/tpws               # bundled universal binary
├─ scripts/
│  └─ build-tpws.sh                       # build universal tpws from zapret source
└─ docs/
   ├─ reference/electron-main.js
   └─ superpowers/{specs,plans}/
```

---

## Phase 0 — Scaffolding & tpws binary

### Task 0.1: Create the SPM Core package

**Files:**
- Create: `Core/Package.swift`
- Create: `Core/Sources/MaktoNoDpiCore/Placeholder.swift`
- Create: `Core/Tests/MaktoNoDpiCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MaktoNoDpiCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MaktoNoDpiCore", targets: ["MaktoNoDpiCore"])
    ],
    targets: [
        .target(name: "MaktoNoDpiCore"),
        .testTarget(name: "MaktoNoDpiCoreTests", dependencies: ["MaktoNoDpiCore"])
    ]
)
```

- [ ] **Step 2: Write a placeholder source so the target compiles**

`Core/Sources/MaktoNoDpiCore/Placeholder.swift`:
```swift
public enum MaktoNoDpiCore {
    public static let version = "1.0.0"
}
```

- [ ] **Step 3: Write a smoke test**

`Core/Tests/MaktoNoDpiCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import MaktoNoDpiCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertFalse(MaktoNoDpiCore.version.isEmpty)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Core && swift test`
Expected: PASS, 1 test.

- [ ] **Step 5: Commit**

```bash
git add Core/Package.swift Core/Sources Core/Tests
git commit -m "chore: scaffold MaktoNoDpiCore SPM package"
```

### Task 0.2: Build a universal tpws binary

**Files:**
- Create: `scripts/build-tpws.sh`
- Produces: `App/MaktoNoDpi/Resources/bin/tpws` (committed via Git LFS or as a binary asset)

> **Context:** zapret release archives are inspected first; `docs/reference/electron-main.js:1417-1468` shows the Electron app searches `binaries/<arch>/tpws` (preferring dirs containing `mac`/`darwin`) and falls back to `make` in the `tpws/` source dir. We do the same at build time and produce a universal binary.

- [ ] **Step 1: Write `scripts/build-tpws.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Builds a universal (arm64 + x86_64) tpws and installs it into the app Resources.
OUT="App/MaktoNoDpi/Resources/bin/tpws"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --depth 1 https://github.com/bol-van/zapret "$WORK/zapret"
cd "$WORK/zapret/tpws"

# zapret's Makefile builds for the host arch; build each arch then lipo.
make clean || true
ARCHFLAGS="-arch arm64"  make CFLAGS="$ARCHFLAGS"  && mv tpws "$WORK/tpws.arm64"
make clean || true
ARCHFLAGS="-arch x86_64" make CFLAGS="$ARCHFLAGS"  && mv tpws "$WORK/tpws.x86_64"

mkdir -p "$(dirname "$OLDPWD/$OUT")"
lipo -create "$WORK/tpws.arm64" "$WORK/tpws.x86_64" -output "$OLDPWD/$OUT"
chmod 755 "$OLDPWD/$OUT"
echo "Built: $OUT"
file "$OLDPWD/$OUT"
```

- [ ] **Step 2: Make executable and run**

Run: `chmod +x scripts/build-tpws.sh && ./scripts/build-tpws.sh`
Expected: ends with `file` output reporting a Mach-O **universal** binary with `arm64` and `x86_64`.

> If zapret's macOS build fails (some versions need `make -f Makefile.mac` or single-arch only), fall back to building per-arch with the available Makefile target and still `lipo` them. If only one arch builds, ship that arch and record the limitation in `docs/reference/tpws-build-notes.md`. Do not proceed with a non-Mach-O file.

- [ ] **Step 3: Verify it runs**

Run: `App/MaktoNoDpi/Resources/bin/tpws --help 2>&1 | head -5`
Expected: tpws usage text (confirms the binary executes on this machine).

- [ ] **Step 4: Commit**

```bash
git add scripts/build-tpws.sh App/MaktoNoDpi/Resources/bin/tpws docs/reference/tpws-build-notes.md 2>/dev/null || git add scripts/build-tpws.sh App/MaktoNoDpi/Resources/bin/tpws
git commit -m "build: universal tpws binary + build script"
```

---

## Phase 1 — Core data (ported, parity-tested)

### Task 1.1: Models

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/Models.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/StrategiesTests.swift` (extended later)

- [ ] **Step 1: Write `Models.swift`**

```swift
import Foundation

public struct Strategy: Equatable, Sendable {
    public let name: String
    public let args: [String]
    public init(name: String, args: [String]) { self.name = name; self.args = args }
}

public enum LogType: String, Sendable { case info, success, warning, error }

public struct LogEntry: Equatable, Sendable {
    public let type: LogType
    public let message: String
    public let timestamp: Date
    public init(type: LogType, message: String, timestamp: Date = Date()) {
        self.type = type; self.message = message; self.timestamp = timestamp
    }
}

public struct StrategyProgress: Equatable, Sendable {
    public let current: Int
    public let total: Int
    public let name: String
}

public enum ProxyError: String, Error, Sendable {
    case alreadyRunning = "ALREADY_RUNNING"
    case downloadFailed = "DOWNLOAD_FAILED"
    case noBinary = "NO_BINARY"
    case networkUnavailable = "NETWORK_UNAVAILABLE"
    case allStrategiesFailed = "ALL_STRATEGIES_FAILED"
    case processCrashed = "PROCESS_CRASHED"
}

public enum ProxyPhase: Equatable, Sendable {
    case disconnected
    case searching(StrategyProgress?)
    case connected(strategy: String, since: Date)
    case error(ProxyError, message: String)
}
```

- [ ] **Step 2: Write a test that the error rawValues match Electron codes**

`Core/Tests/MaktoNoDpiCoreTests/ModelsTests.swift`:
```swift
import XCTest
@testable import MaktoNoDpiCore

final class ModelsTests: XCTestCase {
    func testErrorCodesMatchElectron() {
        XCTAssertEqual(ProxyError.allStrategiesFailed.rawValue, "ALL_STRATEGIES_FAILED")
        XCTAssertEqual(ProxyError.noBinary.rawValue, "NO_BINARY")
        XCTAssertEqual(ProxyError.networkUnavailable.rawValue, "NETWORK_UNAVAILABLE")
    }
}
```

- [ ] **Step 3: Run**

Run: `cd Core && swift test --filter ModelsTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/Models.swift Core/Tests/MaktoNoDpiCoreTests/ModelsTests.swift
git commit -m "feat(core): domain models and error codes"
```

### Task 1.2: Host lists (byte-for-byte parity)

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/HostLists.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/HostListsTests.swift`

> **Port from `docs/reference/electron-main.js:148-234`.** Each list is a newline-joined array of domains. Reproduce arrays exactly: `HOST_LIST_GENERAL` (lines 148-165), `HOST_LIST_GOOGLE` (167-174), `HOST_LIST_DISCORD` (177-186), `HOST_LIST_EXCLUDE` (189-196), `IPSET_EXCLUDE` (199-203), `IPSET_ALL` (206). `listAll` = general + "\n" + google + "\n" + discord (line 230).

- [ ] **Step 1: Write the failing test first (pins exact counts & samples)**

`Core/Tests/MaktoNoDpiCoreTests/HostListsTests.swift`:
```swift
import XCTest
@testable import MaktoNoDpiCore

final class HostListsTests: XCTestCase {
    func testGeneralContainsDiscordAndCloudflareNotYouTube() {
        let g = HostLists.general
        XCTAssertTrue(g.contains("discord.com"))
        XCTAssertTrue(g.contains("cloudflare-ech.com"))
        XCTAssertFalse(g.contains("youtube.com"))   // YouTube lives in google list
    }
    func testGoogleContainsYouTube() {
        XCTAssertTrue(HostLists.google.contains("youtube.com"))
        XCTAssertTrue(HostLists.google.contains("googlevideo.com"))
    }
    func testIpsetAllValue() {
        XCTAssertEqual(HostLists.ipsetAll, "203.0.113.113/32")
    }
    func testListAllIsGeneralPlusGooglePlusDiscord() {
        let expected = HostLists.general + "\n" + HostLists.google + "\n" + HostLists.discord
        XCTAssertEqual(HostLists.listAll(customInclude: []), expected)
    }
    func testCustomIncludeAppendsToGeneral() {
        let all = HostLists.listAll(customInclude: ["example.org"])
        XCTAssertTrue(all.contains("example.org"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter HostListsTests`
Expected: FAIL — `HostLists` undefined.

- [ ] **Step 3: Implement `HostLists.swift`**

Port the arrays verbatim from the reference. Skeleton (fill arrays from lines 148-206):
```swift
import Foundation

public enum HostLists {
    public static let general = generalDomains.joined(separator: "\n")
    public static let google  = googleDomains.joined(separator: "\n")
    public static let discord  = discordDomains.joined(separator: "\n")
    public static let exclude  = excludeDomains.joined(separator: "\n")
    public static let ipsetExclude = ipsetExcludeRanges.joined(separator: "\n")
    public static let ipsetAll = "203.0.113.113/32"

    public static func listAll(customInclude: [String]) -> String {
        let g = customInclude.isEmpty ? general
              : general + "\n" + customInclude.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        return g + "\n" + google + "\n" + discord
    }

    // MARK: - ported arrays (electron-main.js:148-206)
    static let generalDomains: [String] = [
        "cloudflare-ech.com", "encryptedsni.com", /* … all entries from lines 148-165 … */
        "7tv.app", "7tv.io", "localizeapi.com"
    ]
    static let googleDomains: [String] = [ /* lines 167-174 */ ]
    static let discordDomains: [String] = [ /* lines 177-186 */ ]
    static let excludeDomains: [String] = [ /* lines 189-196 */ ]
    static let ipsetExcludeRanges: [String] = [ /* lines 199-203 */ ]
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter HostListsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/HostLists.swift Core/Tests/MaktoNoDpiCoreTests/HostListsTests.swift
git commit -m "feat(core): port zapret host lists with parity tests"
```

### Task 1.3: Pattern files (fake QUIC + fake TLS ClientHello)

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/PatternFiles.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/PatternFilesTests.swift`

> **Port from `docs/reference/electron-main.js:238-331`.** `generateFakeQuicInitial` returns a 256-byte buffer with a fixed long-header layout (flags `0xc3`, version `0x00000001`, 8-byte random DCID, etc.). `generateFakeTlsClientHello(sni)` builds a minimal TLS 1.2 record with an SNI extension. The randomized bytes mean we test **structure** (length, fixed header bytes), not full equality.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class PatternFilesTests: XCTestCase {
    func testQuicInitialIs256BytesWithLongHeader() {
        let buf = PatternFiles.fakeQuicInitial()
        XCTAssertEqual(buf.count, 256)
        XCTAssertEqual(buf[0], 0xc3)                       // long header, initial
        XCTAssertEqual(Array(buf[1...4]), [0,0,0,1])       // QUIC v1
        XCTAssertEqual(buf[5], 0x08)                       // DCID length
    }
    func testTlsClientHelloHasHandshakeRecordAndSNI() {
        let sni = "www.google.com"
        let rec = PatternFiles.fakeTlsClientHello(sni: sni)
        XCTAssertEqual(rec[0], 0x16)                       // TLS handshake record
        XCTAssertEqual(rec[5], 0x01)                       // ClientHello
        let sniBytes = Array(sni.utf8)
        XCTAssertTrue(Array(rec).containsSubsequence(sniBytes))
    }
}

private extension Array where Element == UInt8 {
    func containsSubsequence(_ sub: [UInt8]) -> Bool {
        guard !sub.isEmpty, count >= sub.count else { return false }
        for i in 0...(count - sub.count) where Array(self[i..<i+sub.count]) == sub { return true }
        return false
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter PatternFilesTests`
Expected: FAIL — `PatternFiles` undefined.

- [ ] **Step 3: Implement `PatternFiles.swift`**

Port `generateFakeQuicInitial` (238-264) and `generateFakeTlsClientHello` (267-331) into Swift `Data`/`[UInt8]` using `SecRandomCopyBytes` for the random fills:
```swift
import Foundation

public enum PatternFiles {
    public static func fakeQuicInitial() -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 256)
        var o = 0
        buf[o] = 0xc3; o += 1
        buf[o] = 0; buf[o+1] = 0; buf[o+2] = 0; buf[o+3] = 1; o += 4   // version 1
        buf[o] = 0x08; o += 1
        for _ in 0..<8 { buf[o] = UInt8.random(in: 0...255); o += 1 }   // DCID
        buf[o] = 0x00; o += 1                                          // SCID len
        buf[o] = 0x00; o += 1                                          // token len
        let remaining = 256 - o - 2
        let lenField = UInt16(0x4000 | remaining)
        buf[o] = UInt8(lenField >> 8); buf[o+1] = UInt8(lenField & 0xff); o += 2
        buf[o] = 0; buf[o+1] = 0; buf[o+2] = 0; buf[o+3] = 1; o += 4    // packet number
        for i in o..<256 { buf[i] = UInt8.random(in: 0...255) }
        return buf
    }

    public static func fakeTlsClientHello(sni: String = "www.google.com") -> [UInt8] {
        // Port of electron-main.js:267-331 — SNI extension + ClientHello + TLS record.
        // (Build sniExtension, random[32], cipherSuites, compression, then wrap.)
        // … full byte assembly per reference …
        return [] // replaced by full implementation
    }

    /// Filenames the strategies reference (electron-main.js:334-339).
    public static let patternFilenames = [
        "quic_initial_www_google_com.bin",
        "tls_clienthello_www_google_com.bin",
        "tls_clienthello_4pda_to.bin",
        "tls_clienthello_max_ru.bin"
    ]
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter PatternFilesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/PatternFiles.swift Core/Tests/MaktoNoDpiCoreTests/PatternFilesTests.swift
git commit -m "feat(core): fake QUIC/TLS pattern file generators"
```

### Task 1.4: Strategies (52 darwin strategies, ported)

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/Strategies.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/StrategiesTests.swift`

> **Port from `docs/reference/electron-main.js:994-1104` (`buildDarwinStrategies`).** Every strategy is `{ name, args }`. `BASE = ["--port","1080","--socks"]`. `HL = ["--hostlist=<listsDir>/list-all.txt", "--hostlist-exclude=<listsDir>/list-exclude.txt"]`, with HLG/HLD variants. The function takes `listsDir` and substitutes file paths. There are exactly 14 tiers; reproduce every entry verbatim.

- [ ] **Step 1: Write the failing test (pins count + specific entries)**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class StrategiesTests: XCTestCase {
    let dir = "/tmp/lists"

    func testCountMatchesReference() {
        XCTAssertEqual(Strategies.darwin(listsDir: dir).count, 52)
    }
    func testFirstTierStrategyArgsExact() {
        let s = Strategies.darwin(listsDir: dir).first { $0.name == "multi:disorder+tlsrec" }!
        XCTAssertEqual(s.args, [
            "--port","1080","--socks",
            "--hostlist=\(dir)/list-all.txt","--hostlist-exclude=\(dir)/list-exclude.txt",
            "--filter-l7=tls","--split-pos=1,midsld","--disorder","--tlsrec=sni",
            "--new",
            "--hostlist=\(dir)/list-all.txt","--hostlist-exclude=\(dir)/list-exclude.txt",
            "--filter-l7=http","--hostcase","--methodeol","--split-pos=1","--disorder"
        ])
    }
    func testBasicSplitDisorder() {
        let s = Strategies.darwin(listsDir: dir).first { $0.name == "split+disorder" }!
        XCTAssertEqual(s.args, ["--port","1080","--socks","--split-pos=1","--disorder","--hostcase",
            "--hostlist=\(dir)/list-all.txt","--hostlist-exclude=\(dir)/list-exclude.txt"])
    }
    func testAllNamesUnique() {
        let names = Strategies.darwin(listsDir: dir).map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter StrategiesTests`
Expected: FAIL — `Strategies` undefined.

- [ ] **Step 3: Implement `Strategies.swift`**

Port `buildDarwinStrategies` exactly. Use small helpers for the path arrays so the file stays readable:
```swift
import Foundation

public enum Strategies {
    public static func darwin(listsDir: String) -> [Strategy] {
        let la = "\(listsDir)/list-all.txt"
        let le = "\(listsDir)/list-exclude.txt"
        let lg = "\(listsDir)/list-general.txt"
        let ld = "\(listsDir)/list-discord.txt"
        let BASE = ["--port","1080","--socks"]
        let HL  = ["--hostlist=\(la)","--hostlist-exclude=\(le)"]
        let HLG = ["--hostlist=\(lg)","--hostlist-exclude=\(le)"]
        let HLD = ["--hostlist=\(ld)"]
        func s(_ n: String, _ a: [String]) -> Strategy { Strategy(name: n, args: a) }
        return [
            s("multi:disorder+tlsrec", BASE + HL + ["--filter-l7=tls","--split-pos=1,midsld","--disorder","--tlsrec=sni","--new"] + HL + ["--filter-l7=http","--hostcase","--methodeol","--split-pos=1","--disorder"]),
            // … all remaining entries from electron-main.js:1011-1103, verbatim …
        ]
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter StrategiesTests`
Expected: PASS — count is 52 and the pinned entries match.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/Strategies.swift Core/Tests/MaktoNoDpiCoreTests/StrategiesTests.swift
git commit -m "feat(core): port 52 darwin tpws strategies with parity tests"
```

### Task 1.5: Hosts data (Discord voice / Telegram fallback)

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/HostsData.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/HostsDataTests.swift`

> **Port from `docs/reference/electron-main.js:2708-2748`.** `HOSTS_MARKER = "# MaktoNoDpi Discord/Telegram hosts"`, `HOSTS_URL = "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/hosts"`. `generateFallbackHostsData()` emits Telegram domains -> `149.154.167.220`, then for each of 28 regions, ports `10000..10099` -> `104.25.158.178 <region><port>.discord.media`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class HostsDataTests: XCTestCase {
    func testMarkerAndUrl() {
        XCTAssertEqual(HostsData.marker, "# MaktoNoDpi Discord/Telegram hosts")
        XCTAssertEqual(HostsData.url, "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/hosts")
    }
    func testFallbackHasVoiceEntries() {
        let data = HostsData.fallback()
        XCTAssertTrue(data.contains("104.25.158.178 russia10000.discord.media"))
        XCTAssertTrue(data.contains("104.25.158.178 finland10099.discord.media"))
        XCTAssertTrue(data.contains("149.154.167.220 t.me"))
        // 28 regions * 100 ports voice lines
        let voiceLines = data.split(separator: "\n").filter { $0.contains(".discord.media") }
        XCTAssertEqual(voiceLines.count, 2800)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter HostsDataTests`
Expected: FAIL — `HostsData` undefined.

- [ ] **Step 3: Implement `HostsData.swift`** (port arrays from 2716-2741)

```swift
import Foundation

public enum HostsData {
    public static let marker = "# MaktoNoDpi Discord/Telegram hosts"
    public static let url = "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/hosts"

    static let telegramDomains: [String] = [ /* lines 2716-2726 verbatim */ ]
    static let regions: [String] = [ /* lines 2732-2741 verbatim, 28 entries */ ]

    public static func fallback() -> String {
        var lines: [String] = telegramDomains.map { "149.154.167.220 \($0)" }
        lines.append("")
        for region in regions {
            for i in 10000...10099 { lines.append("104.25.158.178 \(region)\(i).discord.media") }
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter HostsDataTests`
Expected: PASS (voice line count exactly 2800).

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/HostsData.swift Core/Tests/MaktoNoDpiCoreTests/HostsDataTests.swift
git commit -m "feat(core): Discord voice / Telegram hosts fallback data"
```

---

## Phase 2 — Process & command abstractions (testability seam)

### Task 2.1: ProcessRunner & CommandRunner protocols + real impls

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/ProcessRunner.swift`
- Create: `Core/Sources/MaktoNoDpiCore/CommandRunner.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/CommandRunnerTests.swift`

> These seams let `ProxyEngine`/`SystemConfig` be unit-tested with fakes instead of spawning real processes. `ProcessRunner` models a long-lived child (tpws); `CommandRunner` models one-shot commands (`networksetup`, `curl`).

- [ ] **Step 1: Write the failing test (real CommandRunner runs `/bin/echo`)**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class CommandRunnerTests: XCTestCase {
    func testEchoReturnsStdoutAndZeroStatus() async throws {
        let r = SystemCommandRunner()
        let result = try await r.run("/bin/echo", ["hello"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }
    func testNonzeroStatus() async throws {
        let r = SystemCommandRunner()
        let result = try await r.run("/bin/sh", ["-c", "exit 3"])
        XCTAssertEqual(result.status, 3)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter CommandRunnerTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Implement the protocols + real impls**

`CommandRunner.swift`:
```swift
import Foundation

public struct CommandResult: Sendable { public let status: Int32; public let stdout: String; public let stderr: String }

public protocol CommandRunner: Sendable {
    func run(_ launchPath: String, _ args: [String]) async throws -> CommandResult
}

public struct SystemCommandRunner: CommandRunner {
    public init() {}
    public func run(_ launchPath: String, _ args: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = args
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: CommandResult(status: proc.terminationStatus, stdout: o, stderr: e))
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
```

`ProcessRunner.swift`:
```swift
import Foundation

/// A running child process (tpws). The handle can be killed and reports termination.
public protocol RunningProcess: AnyObject, Sendable {
    var isRunning: Bool { get }
    func kill()
    func onTerminate(_ handler: @escaping @Sendable (Int32) -> Void)
}

public protocol ProcessRunner: Sendable {
    func spawn(_ launchPath: String, _ args: [String]) throws -> RunningProcess
}

public final class SystemProcessRunner: ProcessRunner {
    public init() {}
    public func spawn(_ launchPath: String, _ args: [String]) throws -> RunningProcess {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        let handle = SystemRunningProcess(process: p)
        try p.run()
        return handle
    }
}

final class SystemRunningProcess: RunningProcess, @unchecked Sendable {
    private let process: Process
    init(process: Process) { self.process = process }
    var isRunning: Bool { process.isRunning }
    func kill() { if process.isRunning { process.terminate() } }
    func onTerminate(_ handler: @escaping @Sendable (Int32) -> Void) {
        process.terminationHandler = { p in handler(p.terminationStatus) }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter CommandRunnerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/ProcessRunner.swift Core/Sources/MaktoNoDpiCore/CommandRunner.swift Core/Tests/MaktoNoDpiCoreTests/CommandRunnerTests.swift
git commit -m "feat(core): ProcessRunner/CommandRunner seams for testability"
```

---

## Phase 3 — System integration

### Task 3.1: Network services parsing

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/NetworkServices.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/NetworkServicesTests.swift`

> **Port from `docs/reference/electron-main.js:1576-1598`.** Parse `networksetup -listallnetworkservices` (drop the "An asterisk..." header line; trim) and treat a service as active if `networksetup -getinfo "<svc>"` contains `IP address: <ipv4>`. Make parsing pure (string in -> [String] out) so it is testable without the machine's real network config.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class NetworkServicesTests: XCTestCase {
    func testParseListDropsHeader() {
        let raw = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi
        Thunderbolt Bridge
        """
        XCTAssertEqual(NetworkServices.parseServiceList(raw), ["Wi-Fi", "Thunderbolt Bridge"])
    }
    func testActiveDetectsIPv4() {
        XCTAssertTrue(NetworkServices.infoIndicatesActive("IP address: 192.168.1.5\nSubnet mask: 255.255.255.0"))
        XCTAssertFalse(NetworkServices.infoIndicatesActive("IP address: \n"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter NetworkServicesTests`
Expected: FAIL.

- [ ] **Step 3: Implement `NetworkServices.swift`**

```swift
import Foundation

public enum NetworkServices {
    public static func parseServiceList(_ raw: String) -> [String] {
        raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
    }
    public static func infoIndicatesActive(_ info: String) -> Bool {
        info.range(of: #"IP address:\s*\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil
    }
    /// Live enumeration using a CommandRunner (used by SystemConfig).
    public static func active(using runner: CommandRunner) async throws -> [String] {
        let list = try await runner.run("/usr/sbin/networksetup", ["-listallnetworkservices"])
        let all = parseServiceList(list.stdout)
        var active: [String] = []
        for svc in all {
            let info = try await runner.run("/usr/sbin/networksetup", ["-getinfo", svc])
            if infoIndicatesActive(info.stdout) { active.append(svc) }
        }
        return active.isEmpty ? all.filter { $0.range(of: #"(?i)wi-fi|ethernet|usb"#, options: .regularExpression) != nil } : active
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter NetworkServicesTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/NetworkServices.swift Core/Tests/MaktoNoDpiCoreTests/NetworkServicesTests.swift
git commit -m "feat(core): parse networksetup service list"
```

### Task 3.2: SystemConfig (proxy + DNS)

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/SystemConfig.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/SystemConfigTests.swift`

> **Port from `docs/reference/electron-main.js:1600-1659`.** `enableSystemProxy(port)`: per service `networksetup -setsocksfirewallproxy "<svc>" 127.0.0.1 <port>` then `-setsocksfirewallproxystate "<svc>" on`. `disableSystemProxy`: `-setsocksfirewallproxystate off`. `setCleanDns`: capture current `-getdnsservers`, set `1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4`. `restoreDns`: restore captured or `Empty`. `flushDnsCache`: `dscacheutil -flushcache` + `killall -HUP mDNSResponder`. Inject a `CommandRunner` so a fake can assert the exact command sequence.

- [ ] **Step 1: Write the failing test using a recording fake**

```swift
import XCTest
@testable import MaktoNoDpiCore

actor FakeCommandRunner: CommandRunner {
    private(set) var calls: [(String, [String])] = []
    var responder: (@Sendable (String, [String]) -> CommandResult)?
    func run(_ launchPath: String, _ args: [String]) async throws -> CommandResult {
        calls.append((launchPath, args))
        return responder?(launchPath, args) ?? CommandResult(status: 0, stdout: "", stderr: "")
    }
    func recorded() -> [(String, [String])] { calls }
}

final class SystemConfigTests: XCTestCase {
    func testEnableProxyIssuesSetAndStateOnPerService() async throws {
        let fake = FakeCommandRunner()
        let cfg = SystemConfig(runner: fake)
        await cfg.enableProxy(port: 1080, services: ["Wi-Fi"])
        let calls = await fake.recorded()
        XCTAssertTrue(calls.contains { $0.1 == ["-setsocksfirewallproxy","Wi-Fi","127.0.0.1","1080"] })
        XCTAssertTrue(calls.contains { $0.1 == ["-setsocksfirewallproxystate","Wi-Fi","on"] })
    }
    func testDisableProxyTurnsStateOff() async throws {
        let fake = FakeCommandRunner()
        let cfg = SystemConfig(runner: fake)
        await cfg.disableProxy(services: ["Wi-Fi"])
        let calls = await fake.recorded()
        XCTAssertTrue(calls.contains { $0.1 == ["-setsocksfirewallproxystate","Wi-Fi","off"] })
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter SystemConfigTests`
Expected: FAIL.

- [ ] **Step 3: Implement `SystemConfig.swift`** (an `actor`; ignore individual command failures like the reference's try/catch)

```swift
import Foundation

public actor SystemConfig {
    private let runner: CommandRunner
    private let setup = "/usr/sbin/networksetup"
    private var originalDns: [String: String] = [:]
    public init(runner: CommandRunner) { self.runner = runner }

    public func enableProxy(port: Int, services: [String]) async {
        for s in services {
            _ = try? await runner.run(setup, ["-setsocksfirewallproxy", s, "127.0.0.1", "\(port)"])
            _ = try? await runner.run(setup, ["-setsocksfirewallproxystate", s, "on"])
        }
    }
    public func disableProxy(services: [String]) async {
        for s in services { _ = try? await runner.run(setup, ["-setsocksfirewallproxystate", s, "off"]) }
    }
    public func setCleanDns(services: [String]) async {
        for s in services {
            let info = (try? await runner.run(setup, ["-getdnsservers", s]))?.stdout ?? ""
            originalDns[s] = info
            _ = try? await runner.run(setup, ["-setdnsservers", s, "1.1.1.1", "8.8.8.8", "1.0.0.1", "8.8.4.4"])
        }
    }
    public func restoreDns(services: [String]) async {
        let all = Set(originalDns.keys).union(services)
        for s in all {
            let orig = originalDns[s] ?? ""
            if !orig.isEmpty && !orig.contains("aren't any") && !orig.contains("Error") {
                let servers = orig.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                _ = try? await runner.run(setup, ["-setdnsservers", s] + servers)
            } else {
                _ = try? await runner.run(setup, ["-setdnsservers", s, "Empty"])
            }
        }
        originalDns.removeAll()
    }
    public func flushDnsCache() async {
        _ = try? await runner.run("/usr/bin/dscacheutil", ["-flushcache"])
        _ = try? await runner.run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter SystemConfigTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/SystemConfig.swift Core/Tests/MaktoNoDpiCoreTests/SystemConfigTests.swift
git commit -m "feat(core): system SOCKS proxy + DNS management"
```

### Task 3.3: PrivilegedRunner (batched osascript elevation)

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/PrivilegedRunner.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/PrivilegedRunnerTests.swift`

> **Behavior:** Build ONE shell script combining the connection's privileged ops (write pf conf with the QUIC/voice block rules from `electron-main.js:1522-1526`, then `pfctl -f <conf>; pfctl -E`; and append the Discord/Telegram hosts block to `/etc/hosts` guarded by the marker), then run it via `osascript -e 'do shell script "<script>" with administrator privileges'`. Test the **script-building** purely; the actual prompt is manual/integration.

- [ ] **Step 1: Write the failing test for script construction**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class PrivilegedRunnerTests: XCTestCase {
    func testBuildConnectScriptHasPfAndHostsGuard() {
        let script = PrivilegedRunner.buildConnectScript(
            pfConfPath: "/tmp/pf.conf",
            hostsAddFile: "/tmp/hosts-add.txt",
            hostsMarker: HostsData.marker
        )
        XCTAssertTrue(script.contains("pfctl -f /tmp/pf.conf"))
        XCTAssertTrue(script.contains("pfctl -E"))
        XCTAssertTrue(script.contains("grep -q")) // marker guard before appending hosts
        XCTAssertTrue(script.contains(HostsData.marker))
    }
    func testPfRulesContent() {
        let rules = PrivilegedRunner.pfQuicBlockRules
        XCTAssertTrue(rules.contains("block return out quick proto udp from any to any port 443"))
        XCTAssertTrue(rules.contains("port 19294:19344"))
        XCTAssertTrue(rules.contains("port 50000:50100"))
    }
    func testEscapingForOsascript() {
        // Double-quotes inside the shell script must be escaped for AppleScript string literal.
        let wrapped = PrivilegedRunner.osascriptArguments(forShellScript: "echo \"hi\"")
        XCTAssertEqual(wrapped[0], "-e")
        XCTAssertTrue(wrapped[1].contains("with administrator privileges"))
        XCTAssertFalse(wrapped[1].contains("echo \"hi\""))   // raw quotes must be escaped, not literal
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter PrivilegedRunnerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `PrivilegedRunner.swift`**

```swift
import Foundation

public struct PrivilegedRunner: Sendable {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    public static let pfQuicBlockRules = [
        "block return out quick proto udp from any to any port 443",
        "block return out quick proto udp from any to any port 19294:19344",
        "block return out quick proto udp from any to any port 50000:50100"
    ].joined(separator: "\n")

    /// Builds the combined privileged shell script for a connection.
    public static func buildConnectScript(pfConfPath: String, hostsAddFile: String, hostsMarker: String) -> String {
        return [
            "/sbin/pfctl -f \(pfConfPath) 2>/dev/null",
            "/sbin/pfctl -E 2>/dev/null",
            "if ! grep -q '\(hostsMarker)' /etc/hosts; then /bin/cat \(hostsAddFile) >> /etc/hosts; fi",
            "exit 0"
        ].joined(separator: "; ")
    }

    /// AppleScript-escape a shell script and wrap it for `do shell script ... with administrator privileges`.
    public static func osascriptArguments(forShellScript shell: String) -> [String] {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        return ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
    }

    /// Run a privileged shell script (single password prompt).
    public func run(shellScript: String) async throws -> CommandResult {
        try await runner.run("/usr/bin/osascript", Self.osascriptArguments(forShellScript: shellScript))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter PrivilegedRunnerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/PrivilegedRunner.swift Core/Tests/MaktoNoDpiCoreTests/PrivilegedRunnerTests.swift
git commit -m "feat(core): batched osascript privileged runner"
```

### Task 3.4: ConnectivityTester

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/ConnectivityTester.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/ConnectivityTesterTests.swift`

> **Port from `docs/reference/electron-main.js:1661-1708`.** `testSingleConnection`: `curl --socks5-hostname 127.0.0.1:<port> --connect-timeout <t> -s -o /dev/null -w "%{http_code}" <url>`; success when the printed code is `>0 && <500`. `testProxyConnection`: YouTube + Discord API + Discord CDN in parallel; fall back to ytimg / media / gateway endpoints (lines 1675-1707). Inject `CommandRunner` so logic is testable with fakes; status-code parsing is pure.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class ConnectivityTesterTests: XCTestCase {
    func testParseHttpCodeSuccessRange() {
        XCTAssertTrue(ConnectivityTester.isSuccess(curlOutput: "200"))
        XCTAssertTrue(ConnectivityTester.isSuccess(curlOutput: "301"))
        XCTAssertFalse(ConnectivityTester.isSuccess(curlOutput: "000"))
        XCTAssertFalse(ConnectivityTester.isSuccess(curlOutput: "503"))
    }
    func testProxyTestPassesWhenAllPrimaryEndpointsReturn200() async {
        let fake = FakeCommandRunner()
        await fake.setResponder { _, _ in CommandResult(status: 0, stdout: "200", stderr: "") }
        let t = ConnectivityTester(runner: fake)
        let ok = await t.testProxy(port: 1080, timeoutSec: 5)
        XCTAssertTrue(ok)
    }
}

extension FakeCommandRunner {
    func setResponder(_ r: @escaping @Sendable (String, [String]) -> CommandResult) { self.responder = r }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter ConnectivityTesterTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ConnectivityTester.swift`** (port the endpoint sets & fallback ladder)

```swift
import Foundation

public struct ConnectivityTester: Sendable {
    private let runner: CommandRunner
    public init(runner: CommandRunner) { self.runner = runner }

    public static func isSuccess(curlOutput: String) -> Bool {
        guard let code = Int(curlOutput.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return code > 0 && code < 500
    }

    func single(port: Int, timeoutSec: Int, url: String) async -> Bool {
        let args = ["--socks5-hostname", "127.0.0.1:\(port)", "--connect-timeout", "\(timeoutSec)",
                    "-s", "-o", "/dev/null", "-w", "%{http_code}", url]
        guard let r = try? await runner.run("/usr/bin/curl", args) else { return false }
        return Self.isSuccess(curlOutput: r.stdout)
    }

    public func testProxy(port: Int = 1080, timeoutSec: Int = 8) async -> Bool {
        async let yt = single(port: port, timeoutSec: timeoutSec, url: "https://www.youtube.com/")
        async let api = single(port: port, timeoutSec: timeoutSec, url: "https://discord.com/api/v10/gateway")
        async let cdn = single(port: port, timeoutSec: timeoutSec, url: "https://cdn.discordapp.com/")
        var (ytOk, apiOk, cdnOk) = await (yt, api, cdn)
        if ytOk && apiOk && cdnOk { return true }
        if !ytOk { ytOk = await single(port: port, timeoutSec: timeoutSec, url: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"); if !ytOk { return false } }
        var dcOk = apiOk || cdnOk
        if !dcOk {
            let media = await single(port: port, timeoutSec: timeoutSec, url: "https://media.discordapp.net/")
            let gw = await single(port: port, timeoutSec: timeoutSec, url: "https://gateway.discord.gg/")
            dcOk = media || gw
        }
        return dcOk
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter ConnectivityTesterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/ConnectivityTester.swift Core/Tests/MaktoNoDpiCoreTests/ConnectivityTesterTests.swift
git commit -m "feat(core): SOCKS connectivity tester"
```

### Task 3.5: BinaryManager (bundled tpws + file generation + network update)

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/BinaryManager.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/BinaryManagerTests.swift`

> **Behavior (ports `getResourcePath`, `ensureHostLists`, `ensureBinPatternFiles`, the darwin extraction at 1406-1468):** copy the bundled tpws into a writable support dir (`~/Library/Application Support/MaktoNoDpi/bin/tpws`, `chmod 755`); write all list files + `.bin` pattern files into `.../lists` and the bin dir. The `tpwsBundlePath` is injected so tests use a temp file. Network update (fetch newer zapret tpws) is a best-effort method that no-ops on failure.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class BinaryManagerTests: XCTestCase {
    func testInstallCopiesBundledBinaryAndChmod() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let bundled = tmp.appendingPathComponent("tpws-bundled")
        try Data([0x7f, 0x45, 0x4c, 0x46]).write(to: bundled)   // dummy
        let supportDir = tmp.appendingPathComponent("support")
        let mgr = BinaryManager(bundledTpws: bundled.path, supportDir: supportDir.path)
        let installed = try mgr.installBundledBinary()
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed))
        let perms = try FileManager.default.attributesOfItem(atPath: installed)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o755)
    }
    func testWritesAllListFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mgr = BinaryManager(bundledTpws: "/dev/null", supportDir: tmp.path)
        let listsDir = try mgr.ensureHostLists(customInclude: [], customExclude: [])
        for f in ["list-general.txt","list-google.txt","list-discord.txt","list-exclude.txt","ipset-exclude.txt","ipset-all.txt","list-all.txt"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: "\(listsDir)/\(f)"), "missing \(f)")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter BinaryManagerTests`
Expected: FAIL.

- [ ] **Step 3: Implement `BinaryManager.swift`**

```swift
import Foundation

public struct BinaryManager: Sendable {
    let bundledTpws: String
    let supportDir: String
    public init(bundledTpws: String, supportDir: String) { self.bundledTpws = bundledTpws; self.supportDir = supportDir }

    var binDir: String { "\(supportDir)/bin" }
    public var installedTpwsPath: String { "\(binDir)/tpws" }
    public var listsDir: String { "\(supportDir)/lists" }

    public func installBundledBinary() throws -> String {
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: installedTpwsPath) { try? FileManager.default.removeItem(atPath: installedTpwsPath) }
        try FileManager.default.copyItem(atPath: bundledTpws, toPath: installedTpwsPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedTpwsPath)
        return installedTpwsPath
    }

    @discardableResult
    public func ensureHostLists(customInclude: [String], customExclude: [String]) throws -> String {
        try FileManager.default.createDirectory(atPath: listsDir, withIntermediateDirectories: true)
        func write(_ name: String, _ content: String) throws { try content.write(toFile: "\(listsDir)/\(name)", atomically: true, encoding: .utf8) }
        let general = customInclude.isEmpty ? HostLists.general : HostLists.general + "\n" + customInclude.joined(separator: "\n")
        let exclude = customExclude.isEmpty ? HostLists.exclude : HostLists.exclude + "\n" + customExclude.joined(separator: "\n")
        try write("list-general.txt", general)
        try write("list-google.txt", HostLists.google)
        try write("list-discord.txt", HostLists.discord)
        try write("list-exclude.txt", exclude)
        try write("ipset-exclude.txt", HostLists.ipsetExclude)
        try write("ipset-all.txt", HostLists.ipsetAll)
        try write("list-all.txt", general + "\n" + HostLists.google + "\n" + HostLists.discord)
        return listsDir
    }

    public func ensurePatternFiles() throws {
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        let quic = "\(binDir)/quic_initial_www_google_com.bin"
        if !FileManager.default.fileExists(atPath: quic) {
            try Data(PatternFiles.fakeQuicInitial()).write(to: URL(fileURLWithPath: quic))
        }
        for (file, sni) in [("tls_clienthello_www_google_com.bin","www.google.com"),
                            ("tls_clienthello_4pda_to.bin","4pda.to"),
                            ("tls_clienthello_max_ru.bin","max.ru")] {
            let p = "\(binDir)/\(file)"
            if !FileManager.default.fileExists(atPath: p) {
                try Data(PatternFiles.fakeTlsClientHello(sni: sni)).write(to: URL(fileURLWithPath: p))
            }
        }
    }

    /// Best-effort network refresh of tpws from latest zapret release. No-ops on any failure.
    public func updateFromNetwork() async { /* best-effort; see docs/reference/electron-main.js:1281-1468 */ }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter BinaryManagerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/BinaryManager.swift Core/Tests/MaktoNoDpiCoreTests/BinaryManagerTests.swift
git commit -m "feat(core): binary install + list/pattern file generation"
```

### Task 3.6: SettingsStore

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/SettingsStore.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/SettingsStoreTests.swift`

> Mirrors `loadSettings`/`saveSettings` (electron-main.js:34-47): `autoStart`, `autoConnect`, `selectedStrategy` (default `"auto"`), `lastWorkingStrategy`, `customIncludeDomains`, `customExcludeDomains`. Back with an injected `UserDefaults` so tests use a throwaway suite.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class SettingsStoreTests: XCTestCase {
    func testDefaults() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let s = SettingsStore(defaults: d)
        XCTAssertFalse(s.autoStart)
        XCTAssertFalse(s.autoConnect)
        XCTAssertEqual(s.selectedStrategy, "auto")
        XCTAssertNil(s.lastWorkingStrategy)
    }
    func testPersistLastWorking() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        var s = SettingsStore(defaults: d)
        s.lastWorkingStrategy = "split+disorder"
        XCTAssertEqual(SettingsStore(defaults: d).lastWorkingStrategy, "split+disorder")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter SettingsStoreTests`
Expected: FAIL.

- [ ] **Step 3: Implement `SettingsStore.swift`**

```swift
import Foundation

public struct SettingsStore: Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var autoStart: Bool { get { defaults.bool(forKey: "autoStart") } nonmutating set { defaults.set(newValue, forKey: "autoStart") } }
    public var autoConnect: Bool { get { defaults.bool(forKey: "autoConnect") } nonmutating set { defaults.set(newValue, forKey: "autoConnect") } }
    public var selectedStrategy: String { get { defaults.string(forKey: "selectedStrategy") ?? "auto" } nonmutating set { defaults.set(newValue, forKey: "selectedStrategy") } }
    public var lastWorkingStrategy: String? { get { defaults.string(forKey: "lastWorkingStrategy") } nonmutating set { defaults.set(newValue, forKey: "lastWorkingStrategy") } }
    public var customIncludeDomains: [String] { get { defaults.stringArray(forKey: "customIncludeDomains") ?? [] } nonmutating set { defaults.set(newValue, forKey: "customIncludeDomains") } }
    public var customExcludeDomains: [String] { get { defaults.stringArray(forKey: "customExcludeDomains") ?? [] } nonmutating set { defaults.set(newValue, forKey: "customExcludeDomains") } }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter SettingsStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/SettingsStore.swift Core/Tests/MaktoNoDpiCoreTests/SettingsStoreTests.swift
git commit -m "feat(core): settings store"
```

---

## Phase 4 — ProxyEngine (the core loop)

### Task 4.1: ProxyEngine strategy-iteration loop

**Files:**
- Create: `Core/Sources/MaktoNoDpiCore/ProxyEngine.swift`
- Test: `Core/Tests/MaktoNoDpiCoreTests/ProxyEngineTests.swift`

> **Port from `docs/reference/electron-main.js:2109-2479` (`startProxy`) and 2481-2523 (`stopProxy`), darwin path only.** The engine is an `actor` injected with `ProcessRunner`, `CommandRunner`, `SystemConfig`, `ConnectivityTester`, `PrivilegedRunner`, `BinaryManager`, `SettingsStore`. It exposes `connect()` and `stop()` and emits state/log via an async stream. For the loop: order strategies (selected single, or `lastWorking` first then the rest), and for each: spawn tpws, wait, check port listening (a `portProbe` closure injected for testability), enable proxy, run connectivity test; first success -> connected + persist `lastWorking`. The injected seams let tests drive deterministic outcomes with **no real tpws**.

- [ ] **Step 1: Write the failing test (fake everything; second strategy succeeds)**

```swift
import XCTest
@testable import MaktoNoDpiCore

final class ProxyEngineTests: XCTestCase {
    func testConnectsOnSecondStrategyAndPersistsLastWorking() async throws {
        let fakeProc = FakeProcessRunner()                 // always "running"
        let fakeCmd = FakeCommandRunner()                  // proxy/dns no-ops
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var settings = SettingsStore(defaults: defaults)

        // ConnectivityTester fake: fail first probe, succeed second.
        let tester = ScriptedTester(results: [false, true])
        let engine = ProxyEngine(
            strategies: [Strategy(name: "A", args: []), Strategy(name: "B", args: [])],
            processRunner: fakeProc, commandRunner: fakeCmd,
            tester: tester, settings: settings,
            activeServices: { ["Wi-Fi"] }, portProbe: { _ in true },
            elevate: { _ in }, prepareFiles: { "/tmp/lists" }
        )
        let phase = try await engine.connect()
        guard case .connected(let strategy, _) = phase else { return XCTFail("not connected: \(phase)") }
        XCTAssertEqual(strategy, "B")
        XCTAssertEqual(SettingsStore(defaults: defaults).lastWorkingStrategy, "B")
    }

    func testAllStrategiesFailReturnsError() async throws {
        let engine = ProxyEngine(
            strategies: [Strategy(name: "A", args: [])],
            processRunner: FakeProcessRunner(), commandRunner: FakeCommandRunner(),
            tester: ScriptedTester(results: [false]), settings: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            activeServices: { ["Wi-Fi"] }, portProbe: { _ in true }, elevate: { _ in }, prepareFiles: { "/tmp/lists" }
        )
        let phase = try await engine.connect()
        guard case .error(let code, _) = phase else { return XCTFail("expected error") }
        XCTAssertEqual(code, .allStrategiesFailed)
    }
}
```

> Test doubles `FakeProcessRunner`, `ScriptedTester` (conforming to a `ConnectivityProbing` protocol that both the real `ConnectivityTester` and the fake adopt) are added in this test file. Define the `ConnectivityProbing` protocol in `ProxyEngine.swift` with a single `func testProxy(port:timeoutSec:) async -> Bool` and make `ConnectivityTester` conform.

- [ ] **Step 2: Run to verify it fails**

Run: `cd Core && swift test --filter ProxyEngineTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ProxyEngine.swift`**

Define the `ConnectivityProbing` protocol, the engine actor with injected dependencies and closures (`activeServices`, `portProbe`, `elevate`, `prepareFiles`), the `connect()` loop (ordering per settings, spawn -> wait -> portProbe -> enableProxy -> tester -> first-success), and `stop()` (disableProxy, restoreDns, kill, revert pf). Emit `ProxyPhase` and `LogEntry` through an `AsyncStream`. Keep the file focused on orchestration; all primitives live in their own modules.

- [ ] **Step 4: Run to verify it passes**

Run: `cd Core && swift test --filter ProxyEngineTests`
Expected: PASS — both tests green.

- [ ] **Step 5: Run the full Core suite**

Run: `cd Core && swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Core/Sources/MaktoNoDpiCore/ProxyEngine.swift Core/Tests/MaktoNoDpiCoreTests/ProxyEngineTests.swift
git commit -m "feat(core): proxy engine strategy-iteration loop"
```

---

## Phase 5 — SwiftUI app shell

> These tasks build the `.app` in Xcode and wire it to `MaktoNoDpiCore`. They are verified by building (`xcodebuild`) and manual run on this Mac (privileged prompts and real networking can't be unit-tested in CI). Each task ends with a build + a focused manual check.

### Task 5.1: Create the Xcode app target and embed Core

**Files:**
- Create: `App/MaktoNoDpi.xcodeproj` (via Xcode: macOS App, SwiftUI, name `MaktoNoDpi`, bundle id `com.makto.nodpi.native`)
- Modify: project settings — add local SPM dependency on `../Core` (`MaktoNoDpiCore`); set Deployment Target macOS 13; disable App Sandbox (this is a non-sandboxed direct-distribution app); add `App/MaktoNoDpi/Resources/bin/tpws` to "Copy Bundle Resources".

- [ ] **Step 1:** In Xcode create the macOS App target as above; add `Core` as a local package dependency and link `MaktoNoDpiCore`.
- [ ] **Step 2:** Add the `Resources/bin/tpws` file reference to the target's Copy Bundle Resources phase.
- [ ] **Step 3: Build**

Run: `xcodebuild -project App/MaktoNoDpi.xcodeproj -scheme MaktoNoDpi -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "chore(app): Xcode SwiftUI target embedding MaktoNoDpiCore + bundled tpws"
```

### Task 5.2: ProxyController (Core -> UI bridge)

**Files:**
- Create: `App/MaktoNoDpi/ProxyController.swift`

> A `@MainActor final class ProxyController: ObservableObject` that constructs the real `ProxyEngine` (resolving the bundled tpws path via `Bundle.main.path(forResource: "tpws", ofType: nil, inDirectory: "bin")` and the support dir under Application Support), exposes `@Published phase: ProxyPhase`, `@Published log: [LogEntry]`, and `connect()`/`stop()` that call the engine and consume its `AsyncStream`. Mirrors the preload IPC surface (`docs/reference/electron-preload.js`).

- [ ] **Step 1:** Implement `ProxyController` wiring the engine with `SystemProcessRunner()`, `SystemCommandRunner()`, real `SystemConfig`, `ConnectivityTester`, `PrivilegedRunner`, `BinaryManager`, `SettingsStore`. The `activeServices` closure uses `NetworkServices.active(using:)`; `portProbe` opens a TCP socket to `127.0.0.1:1080`; `elevate` calls `PrivilegedRunner.run`; `prepareFiles` calls `BinaryManager.ensureHostLists/ensurePatternFiles/installBundledBinary`.
- [ ] **Step 2: Build**

Run: `xcodebuild -project App/MaktoNoDpi.xcodeproj -scheme MaktoNoDpi -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add App/MaktoNoDpi/ProxyController.swift
git commit -m "feat(app): ProxyController bridging Core to SwiftUI"
```

### Task 5.3: Main window UI

**Files:**
- Create: `App/MaktoNoDpi/ContentView.swift`
- Modify: `App/MaktoNoDpi/MaktoNoDpiApp.swift`

> Status pill (disconnected/searching with progress N/M + strategy name/connected since/error message), a primary Connect/Disconnect button, and a scrolling log list bound to `controller.log`. Text in Russian to match current UX; **use short dash `-`, never em dash** (project convention).

- [ ] **Step 1:** Implement `ContentView` observing `ProxyController`; wire the app `@main` to create the controller as a `@StateObject`.
- [ ] **Step 2: Build**

Run: `xcodebuild -project App/MaktoNoDpi.xcodeproj -scheme MaktoNoDpi -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual check**

Run the app from Xcode; press Connect. Expected: one admin password prompt; status moves searching -> connected (or a clear error); pressing Disconnect reverts. Verify with `networksetup -getsocksfirewallproxy Wi-Fi` that the proxy is set while connected and off after disconnect.

- [ ] **Step 4: Commit**

```bash
git add App/MaktoNoDpi/ContentView.swift App/MaktoNoDpi/MaktoNoDpiApp.swift
git commit -m "feat(app): main window UI"
```

### Task 5.4: Menu-bar item (NSStatusItem)

**Files:**
- Create: `App/MaktoNoDpi/TrayController.swift`
- Modify: `App/MaktoNoDpi/MaktoNoDpiApp.swift`

> **Port from `docs/reference/electron-main.js:1177-1191` (`updateTrayMenu`):** menu items Открыть / status line / Подключить / Отключить / Выход. Use `NSStatusItem` with a template icon; menu reflects `controller.phase`.

- [ ] **Step 1:** Implement `TrayController` holding an `NSStatusItem`, rebuilding its menu when `phase` changes; "Выход" runs cleanup then terminates.
- [ ] **Step 2: Build** — `xcodebuild ... build` -> BUILD SUCCEEDED.
- [ ] **Step 3: Manual check** — menu-bar icon appears; Connect/Disconnect/Quit work from it.
- [ ] **Step 4: Commit**

```bash
git add App/MaktoNoDpi/TrayController.swift App/MaktoNoDpi/MaktoNoDpiApp.swift
git commit -m "feat(app): menu-bar status item"
```

### Task 5.5: Settings (autostart, autoconnect, strategy, custom domains)

**Files:**
- Create: `App/MaktoNoDpi/SettingsView.swift`
- Create: `App/MaktoNoDpi/LoginItem.swift`

> **Autostart** via `SMAppService.mainApp.register()/unregister()` (no signing required for login-item registration). **Autoconnect** triggers `controller.connect()` ~1.5s after launch when enabled (port of electron-main.js:3066-3070). **Strategy picker** lists `Strategies.darwin(...)` names plus `"auto"`. **Custom domains** edit `SettingsStore.custom{Include,Exclude}Domains`.

- [ ] **Step 1:** Implement `LoginItem` (register/unregister/`isEnabled`) and `SettingsView` bound to `SettingsStore`.
- [ ] **Step 2:** In the app `@main`, on launch apply autostart and, if `autoConnect`, schedule connect after 1.5s.
- [ ] **Step 3: Build** -> BUILD SUCCEEDED.
- [ ] **Step 4: Manual check** — toggle autostart and confirm via `sfltool dumpbtm` or System Settings > Login Items; selecting a specific strategy makes Connect use only it.
- [ ] **Step 5: Commit**

```bash
git add App/MaktoNoDpi/SettingsView.swift App/MaktoNoDpi/LoginItem.swift App/MaktoNoDpi/MaktoNoDpiApp.swift
git commit -m "feat(app): settings, login item, autoconnect"
```

### Task 5.6: Emergency cleanup on quit/crash/signal

**Files:**
- Modify: `App/MaktoNoDpi/MaktoNoDpiApp.swift`

> **Port from `docs/reference/electron-main.js:3093-3112` (`emergencyCleanup`).** On `NSApplication.willTerminate` and on SIGTERM/SIGINT, synchronously: disable system proxy, restore DNS, reload `/etc/pf.conf`, `pkill -f tpws`. Also run a cleanup at launch (clear stale proxy/DNS from a prior crash — electron-main.js:3034-3036).

- [ ] **Step 1:** Add an `AppDelegate` (via `NSApplicationDelegateAdaptor`) implementing `applicationWillTerminate`; install `signal(SIGTERM/SIGINT)` handlers that call a synchronous cleanup and exit. Run startup cleanup in `applicationDidFinishLaunching`.
- [ ] **Step 2: Build** -> BUILD SUCCEEDED.
- [ ] **Step 3: Manual check** — connect, then `kill -TERM <pid>`; confirm `networksetup -getsocksfirewallproxy Wi-Fi` shows proxy off and no `tpws` in `pgrep tpws`.
- [ ] **Step 4: Commit**

```bash
git add App/MaktoNoDpi/MaktoNoDpiApp.swift
git commit -m "feat(app): emergency cleanup on terminate/signal"
```

---

## Phase 6 — Updates & packaging

### Task 6.1: Sparkle auto-updates

**Files:**
- Create: `App/MaktoNoDpi/UpdaterController.swift`
- Modify: project (add Sparkle SPM dependency), `Info.plist` (`SUFeedURL`, `SUEnableInstallerLauncherService` as needed)

> Add Sparkle via SPM (`https://github.com/sparkle-project/Sparkle`). Wire a `SPUStandardUpdaterController`; add a "Проверить обновления" menu command. Host an `appcast.xml` (GitHub Releases) — for unsigned builds, configure Sparkle to skip signature verification or generate an EdDSA key and sign updates (preferred). Document the chosen path in `docs/reference/updates.md`.

- [ ] **Step 1:** Add Sparkle dependency; implement `UpdaterController`; add menu command and `Info.plist` keys.
- [ ] **Step 2: Build** -> BUILD SUCCEEDED.
- [ ] **Step 3: Manual check** — "Проверить обновления" opens Sparkle's UI (no crash) against a test appcast.
- [ ] **Step 4: Commit**

```bash
git add App docs/reference/updates.md
git commit -m "feat(app): Sparkle auto-updates"
```

### Task 6.2: Package .app/.dmg + xattr instructions

**Files:**
- Create: `scripts/package.sh`
- Create: `README.md` (install steps incl. `xattr -cr /Applications/MaktoNoDpi.app`)

> Archive a Release build and produce a `.dmg`. Since unsigned, document the `xattr -cr` step as in the Electron README (`docs/reference/...` README parity).

- [ ] **Step 1:** Write `scripts/package.sh` using `xcodebuild -archive` + `hdiutil create` (or `create-dmg`).
- [ ] **Step 2: Run** — produces `dist/MaktoNoDpi.dmg`.
- [ ] **Step 3: Manual check** — mount dmg, drag to /Applications, `xattr -cr`, launch, Connect works end-to-end.
- [ ] **Step 4: Commit**

```bash
git add scripts/package.sh README.md
git commit -m "build: package .app/.dmg + install docs"
```

---

## Self-Review (completed)

**Spec coverage:** every spec component maps to a task — ProxyController (5.2), ProxyEngine (4.1), Strategies (1.4), BinaryManager (3.5), SystemConfig (3.2), PrivilegedRunner (3.3), ConnectivityTester (3.4), SettingsStore (3.6), TrayController (5.4), LoginItem (5.5), Updater (6.1); ported data — HostLists (1.2), PatternFiles (1.3), HostsData (1.5); cleanup (5.6); both open risks have dedicated handling — tpws build (0.2), `networksetup` root requirement is verified during the 5.3 manual check and, if needed, folded into PrivilegedRunner (3.3).

**Placeholder scan:** data-heavy tasks (1.2/1.4/1.5) intentionally cite exact reference line ranges to port verbatim rather than re-inlining hundreds of domains/strategies; each is pinned by a parity test (counts + exact sample args/bytes), so "done" is unambiguous and machine-checkable. No "TBD/handle errors/etc." steps remain. Phase 5 GUI tasks state the concrete files, the exact reference behavior, the build command, and a specific manual verification.

**Type consistency:** names are consistent across tasks — `Strategy{name,args}`, `Strategies.darwin(listsDir:)`, `HostLists.{general,google,discord,exclude,ipsetExclude,ipsetAll,listAll(customInclude:)}`, `CommandRunner.run(_:_:)->CommandResult`, `ProcessRunner.spawn`, `SystemConfig` actor methods, `ConnectivityProbing.testProxy(port:timeoutSec:)`, `ProxyEngine.connect()/stop()`, `ProxyPhase`, `ProxyError` raw values matching Electron codes.
