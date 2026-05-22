import Foundation

// Discord voice / Telegram fallback hosts — ported from electron-main.js:2708-2748
public enum HostsData {

    public static let marker = "# MaktoNoDpi Discord/Telegram hosts"
    public static let url = "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/hosts"

    /// Embedded fallback hosts data — used when GitHub download fails.
    /// Includes Telegram web hosts and Discord voice servers.
    /// Mirrors electron-main.js generateFallbackHostsData().
    public static func fallback() -> String {
        var lines = [String]()

        // Telegram web
        let tgDomains = [
            "telegram.me", "telegram.dog", "telegram.space", "telesco.pe", "tg.dev",
            "kws2.web.telegram.org", "kws2-1.web.telegram.org", "kws1-1.web.telegram.org",
            "kws1.web.telegram.org", "telegram.org", "t.me", "api.telegram.org",
            "pluto.web.telegram.org", "pluto-1.web.telegram.org", "flora.web.telegram.org",
            "td.telegram.org", "venus.web.telegram.org", "web.telegram.org",
            "kws4-1.web.telegram.org", "kws4.web.telegram.org", "kws5-1.web.telegram.org",
            "kws5.web.telegram.org", "zws1-1.web.telegram.org", "zws1.web.telegram.org",
            "zws2-1.web.telegram.org", "zws2.web.telegram.org", "zws4-1.web.telegram.org",
            "zws5-1.web.telegram.org", "zws5.web.telegram.org"
        ]
        for d in tgDomains { lines.append("149.154.167.220 \(d)") }
        lines.append("")

        // Discord voice servers — ALL regions, ports 10000-10099
        let voiceIp = "104.25.158.178"
        let regions = [
            "finland", "russia",
            "us-east", "us-west", "us-south", "us-central",
            "eu-central", "eu-west",
            "brazil", "hongkong", "india", "japan", "singapore",
            "southafrica", "south-korea", "sydney",
            "bucharest", "tel-aviv", "newark", "milan",
            "rotterdam", "madrid", "stockholm", "buenos-aires",
            "atlanta", "seattle", "santa-clara", "oregon"
        ]
        for region in regions {
            for port in 10000...10099 {
                lines.append("\(voiceIp) \(region)\(port).discord.media")
            }
        }

        return lines.joined(separator: "\n")
    }
}
