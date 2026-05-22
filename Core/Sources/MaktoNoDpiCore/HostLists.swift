import Foundation

// Domain lists matching Flowseal/zapret-discord-youtube v1.9.6
// IMPORTANT: list-general = Discord + Cloudflare ONLY (no YouTube!)
// YouTube goes in list-google with separate filter rules
public enum HostLists {

    private static let generalArray: [String] = [
        "cloudflare-ech.com", "encryptedsni.com", "cloudflareaccess.com", "cloudflareapps.com",
        "cloudflarebolt.com", "cloudflareclient.com", "cloudflareinsights.com", "cloudflareok.com",
        "cloudflarepartners.com", "cloudflareportal.com", "cloudflarepreview.com", "cloudflareresolve.com",
        "cloudflaressl.com", "cloudflarestatus.com", "cloudflarestorage.com", "cloudflarestream.com",
        "cloudflaretest.com", "dis.gd", "discord-attachments-uploads-prd.storage.googleapis.com",
        "discord.app", "discord.co", "discord.com", "discord.design", "discord.dev", "discord.gift",
        "discord.gifts", "discord.gg", "discord.media", "discord.new", "discord.store", "discord.status",
        "discord-activities.com", "discordactivities.com", "discordapp.com", "discordapp.net",
        "discordcdn.com", "discordmerch.com", "discordpartygames.com", "discordsays.com",
        "discordsez.com", "discordstatus.com",
        "gateway.discord.gg", "cdn.discordapp.com", "media.discordapp.net",
        "images-ext-1.discordapp.net", "images-ext-2.discordapp.net",
        "dl.discordapp.net", "updates.discord.com", "router.discordapp.net",
        "sentry.io", "sentry-cdn.com",
        "frankerfacez.com", "ffzap.com", "betterttv.net",
        "7tv.app", "7tv.io", "localizeapi.com"
    ]

    private static let googleArray: [String] = [
        "yt3.ggpht.com", "yt4.ggpht.com", "yt3.googleusercontent.com",
        "googlevideo.com", "jnn-pa.googleapis.com", "stable.dl2.discordapp.net",
        "wide-youtube.l.google.com", "youtube-nocookie.com", "youtube-ui.l.google.com",
        "youtube.com", "youtubeembeddedplayer.googleapis.com", "youtubekids.com",
        "youtubei.googleapis.com", "youtu.be", "yt-video-upload.l.google.com",
        "ytimg.com", "ytimg.l.google.com"
    ]

    // Discord-only list: apply gentler desync to Discord TLS first, syndata for the rest
    private static let discordArray: [String] = [
        "discord.com", "discord.gg", "discordapp.com", "discordapp.net", "discord.media",
        "discord.co", "discord.gift", "discord.gifts", "discord.new", "discord.store", "discord.status",
        "discord.app", "discord.design", "discord.dev", "discord-activities.com", "discordactivities.com",
        "discordcdn.com", "discordmerch.com", "discordpartygames.com", "discordsays.com", "discordsez.com",
        "discordstatus.com", "dis.gd", "gateway.discord.gg", "cdn.discordapp.com", "dl.discordapp.net",
        "updates.discord.com", "discord-attachments-uploads-prd.storage.googleapis.com",
        "media.discordapp.net", "images-ext-1.discordapp.net", "images-ext-2.discordapp.net",
        "router.discordapp.net"
    ]

    // Exclude list — Russian/local services that should NOT be processed by DPI bypass
    private static let excludeArray: [String] = [
        "pusher.com", "live-video.net", "ttvnw.net", "twitch.tv",
        "mail.ru", "citilink.ru", "yandex.com", "nvidia.com", "donationalerts.com",
        "vk.com", "yandex.kz", "mts.ru", "multimc.org", "ya.ru", "dns-shop.ru",
        "habr.com", "3dnews.ru", "sberbank.ru", "ozon.ru", "wildberries.ru",
        "microsoft.com", "msi.com", "akamaitechnologies.com", "2ip.ru", "yandex.ru",
        "boosty.to", "tanki.su", "lesta.ru", "korabli.su", "tanksblitz.ru", "reg.ru"
    ]

    // Private/reserved IP ranges to exclude from processing
    private static let ipsetExcludeArray: [String] = [
        "0.0.0.0/8", "10.0.0.0/8", "127.0.0.0/8", "172.16.0.0/12",
        "192.168.0.0/16", "169.254.0.0/16", "224.0.0.0/4", "100.64.0.0/10",
        "::1", "fc00::/7", "fe80::/10"
    ]

    // IPSet for IP-based fallback rules (dummy IP = "none" mode, like reference default)
    public static let ipsetAll: String = "203.0.113.113/32"

    public static let general: String = generalArray.joined(separator: "\n")
    public static let google: String = googleArray.joined(separator: "\n")
    public static let discord: String = discordArray.joined(separator: "\n")
    public static let exclude: String = excludeArray.joined(separator: "\n")
    public static let ipsetExclude: String = ipsetExcludeArray.joined(separator: "\n")

    /// Mirrors electron-main.js ensureHostLists(): generalWithCustom + '\n' + google + '\n' + discord
    public static func listAll(customInclude: [String]) -> String {
        let filtered = customInclude.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let generalWithCustom: String
        if !filtered.isEmpty {
            generalWithCustom = general + "\n" + filtered.joined(separator: "\n")
        } else {
            generalWithCustom = general
        }
        return generalWithCustom + "\n" + google + "\n" + discord
    }
}
