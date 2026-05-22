import Foundation

public enum Strategies {
    public static func darwin(listsDir: String) -> [Strategy] {
        let la = "\(listsDir)/list-all.txt"
        let le = "\(listsDir)/list-exclude.txt"
        let lg = "\(listsDir)/list-general.txt"
        let ld = "\(listsDir)/list-discord.txt"
        let BASE = ["--port", "1080", "--socks"]
        let HL  = ["--hostlist=\(la)", "--hostlist-exclude=\(le)"]
        let HLG = ["--hostlist=\(lg)", "--hostlist-exclude=\(le)"]
        let HLD = ["--hostlist=\(ld)"]
        func s(_ n: String, _ a: [String]) -> Strategy { Strategy(name: n, args: a) }
        return [
            // === TIER 1: Multi-profile TLS+HTTP (best for Discord+YouTube combo) ===
            s("multi:disorder+tlsrec", BASE + HL +
              ["--filter-l7=tls", "--split-pos=1,midsld", "--disorder", "--tlsrec=sni",
               "--new"] + HL + ["--filter-l7=http", "--hostcase", "--methodeol", "--split-pos=1", "--disorder"]),
            s("multi:oob-tls+hostcase-http", BASE + HL +
              ["--filter-l7=tls", "--split-pos=1,midsld", "--oob", "--disorder",
               "--new"] + HL + ["--filter-l7=http", "--hostcase", "--hostdot", "--split-pos=1", "--disorder"]),
            s("multi:split-sniext+methodeol", BASE + HL +
              ["--filter-l7=tls", "--split-pos=1,sniext", "--disorder", "--tlsrec=sni",
               "--new"] + HL + ["--filter-l7=http", "--methodeol", "--hostcase", "--split-pos=2", "--disorder"]),

            // === TIER 2: Split+Disorder basics (proven, wide ISP compat) ===
            s("split+disorder",           BASE + ["--split-pos=1", "--disorder", "--hostcase"] + HL),
            s("split-midsld+disorder",    BASE + ["--split-pos=1,midsld", "--disorder", "--hostcase"] + HL),
            s("split2+disorder",          BASE + ["--split-pos=2", "--disorder", "--hostcase"] + HL),
            s("split-host+disorder",      BASE + ["--split-pos=host", "--disorder", "--hostcase"] + HL),
            s("split-endhost+disorder",   BASE + ["--split-pos=endhost", "--disorder", "--hostcase"] + HL),

            // === TIER 3: TLS record manipulation (effective against TSPU for YouTube) ===
            s("tlsrec+split+disorder",       BASE + ["--tlsrec=sni", "--split-pos=1", "--disorder", "--hostcase"] + HL),
            s("tlsrec+split-midsld+disorder",BASE + ["--tlsrec=sni", "--split-pos=1,midsld", "--disorder", "--hostcase"] + HL),
            s("tlsrec-sniext+disorder",      BASE + ["--tlsrec=sniext", "--split-pos=1", "--disorder", "--hostcase"] + HL),

            // === TIER 4: OOB — out-of-band data injection ===
            s("oob+split+disorder",     BASE + ["--oob", "--split-pos=1", "--disorder"] + HL),
            s("oob+split-midsld",       BASE + ["--oob", "--split-pos=1,midsld", "--disorder"] + HL),
            s("oob+tlsrec+split",       BASE + ["--oob", "--tlsrec=sni", "--split-pos=1", "--hostcase"] + HL),
            s("oob-tls+split+disorder", BASE + ["--oob=tls", "--split-pos=1,midsld", "--disorder", "--hostcase"] + HL),
            s("oob-0x01+split+disorder",BASE + ["--oob", "--oob-data=0x01", "--split-pos=1", "--disorder"] + HL),

            // === TIER 5: Multi-profile with Discord-specific rules ===
            s("multi:discord-split+general-disorder", BASE +
              HLD + ["--filter-l7=tls", "--split-pos=1,midsld", "--disorder", "--tlsrec=sni",
                     "--new"] + HLD + ["--filter-l7=http", "--hostcase", "--split-pos=1", "--disorder",
                     "--new"] + HLG + ["--filter-l7=tls", "--split-pos=1", "--disorder",
                     "--new"] + HLG + ["--filter-l7=http", "--hostcase", "--methodeol", "--split-pos=1"]),
            s("multi:discord-oob+general-split", BASE +
              HLD + ["--split-pos=1,midsld", "--oob", "--disorder",
                     "--new"] + HLG + ["--split-pos=1", "--disorder", "--hostcase"]),

            // === TIER 6: Host header manipulation ===
            s("methodeol+split",        BASE + ["--methodeol", "--split-pos=1", "--hostcase"] + HL),
            s("hostdot+split+disorder", BASE + ["--hostdot", "--split-pos=1,midsld", "--disorder"] + HL),
            s("hostpad+split+disorder", BASE + ["--hostpad=256", "--split-pos=1", "--disorder", "--hostcase"] + HL),
            s("domcase+split+disorder", BASE + ["--domcase", "--split-pos=1,midsld", "--disorder"] + HL),

            // === TIER 7: Combined aggressive strategies ===
            s("combined-v1",         BASE + ["--split-pos=1,midsld", "--disorder", "--hostcase", "--methodeol"] + HL),
            s("combined-v2",         BASE + ["--oob", "--methodeol", "--split-pos=1,midsld", "--disorder", "--hostcase", "--hostdot"] + HL),
            s("combined-v3",         BASE + ["--tlsrec=sni", "--hostpad=256", "--split-pos=2", "--disorder", "--hostcase"] + HL),
            s("oob+methodeol+split", BASE + ["--oob", "--methodeol", "--split-pos=1", "--hostcase"] + HL),
            s("combined-v4",         BASE + ["--oob", "--hostpad=256", "--split-pos=1,midsld", "--disorder", "--hostcase", "--methodeol"] + HL),
            s("combined-v5",         BASE + ["--tlsrec=sni", "--methodeol", "--hostdot", "--split-pos=2", "--disorder", "--hostcase"] + HL),
            s("combined-v6",         BASE + ["--oob=tls", "--tlsrec=sni", "--split-pos=1,midsld", "--disorder", "--hostcase"] + HL),
            s("combined-v7",         BASE + ["--domcase", "--oob", "--split-pos=host", "--disorder"] + HL),

            // === TIER 8: Multi-profile split-any-protocol (for edge cases) ===
            s("multi:splitany+disorder", BASE + HL +
              ["--split-pos=1,midsld", "--split-any-protocol", "--disorder",
               "--new"] + HL + ["--filter-l7=http", "--hostcase", "--methodeol"]),
            s("split-any+oob+disorder",  BASE + ["--split-pos=1", "--split-any-protocol", "--oob", "--disorder"] + HL),

            // === TIER 9: Extended split positions ===
            s("split3+disorder",       BASE + ["--split-pos=3", "--disorder", "--hostcase"] + HL),
            s("split-sniext+disorder", BASE + ["--split-pos=1,sniext", "--disorder", "--hostcase"] + HL),
            s("split-sld+disorder",    BASE + ["--split-pos=sld", "--disorder", "--hostcase"] + HL),
            s("split-endsld+disorder", BASE + ["--split-pos=endsld", "--disorder", "--hostcase"] + HL),

            // === TIER 10: Host header variants ===
            s("hosttab+split+disorder",    BASE + ["--hosttab", "--split-pos=1", "--disorder", "--hostcase"] + HL),
            s("hostnospace+split+disorder",BASE + ["--hostnospace", "--split-pos=1", "--disorder", "--hostcase"] + HL),
            s("hostpad512+split+disorder", BASE + ["--hostpad=512", "--split-pos=1", "--disorder", "--hostcase"] + HL),
            s("hostpad1024+split",         BASE + ["--hostpad=1024", "--split-pos=1,midsld", "--hostcase"] + HL),
            s("unixeol+split+disorder",    BASE + ["--unixeol", "--split-pos=1", "--disorder", "--hostcase"] + HL),

            // === TIER 11: TLS record + OOB variants ===
            s("tlsrec+disorder",     BASE + ["--tlsrec=sni", "--disorder", "--hostcase"] + HL),
            s("tlsrec+oob+split",    BASE + ["--tlsrec=sni", "--oob", "--split-pos=1", "--hostcase"] + HL),
            s("tlsrec+oob+disorder", BASE + ["--tlsrec=sni", "--oob", "--disorder", "--hostcase"] + HL),

            // === TIER 12: Multi-profile tamper-cutoff (reduce false positives) ===
            s("multi:cutoff-tls+cutoff-http", BASE + HL +
              ["--filter-l7=tls", "--split-pos=1,midsld", "--disorder", "--tlsrec=sni", "--tamper-cutoff=n5",
               "--new"] + HL + ["--filter-l7=http", "--hostcase", "--methodeol", "--split-pos=1", "--tamper-cutoff=n3"]),

            // === TIER 13: Minimal (last resort with hostlist) ===
            s("split-only",    BASE + ["--split-pos=1"] + HL),
            s("disorder-only", BASE + ["--disorder"] + HL),

            // === TIER 14: Fallback without hostlist ===
            s("split+disorder-nohl",        BASE + ["--split-pos=1", "--disorder", "--hostcase"]),
            s("split-midsld+disorder-nohl", BASE + ["--split-pos=1,midsld", "--disorder", "--hostcase"]),
            s("tlsrec+split+disorder-nohl", BASE + ["--tlsrec=sni", "--split-pos=1", "--disorder", "--hostcase"]),
            s("oob+split+disorder-nohl",    BASE + ["--oob", "--split-pos=1", "--disorder"]),
            s("multi:disorder+tlsrec-nohl", BASE +
              ["--filter-l7=tls", "--split-pos=1,midsld", "--disorder", "--tlsrec=sni",
               "--new", "--filter-l7=http", "--hostcase", "--methodeol", "--split-pos=1", "--disorder"]),
        ]
    }
}
