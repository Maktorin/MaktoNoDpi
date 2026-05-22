import Foundation

// Generate fake QUIC/TLS pattern files — ported from electron-main.js:238-331
// These are what Flowseal ships as .bin pattern files for zapret DPI bypass
public enum PatternFiles {

    public static let patternFilenames = [
        "quic_initial_www_google_com.bin",
        "tls_clienthello_www_google_com.bin",
        "tls_clienthello_4pda_to.bin",
        "tls_clienthello_max_ru.bin"
    ]

    /// Generate fake QUIC initial packet (256 bytes).
    /// Mirrors electron-main.js generateFakeQuicInitial().
    public static func fakeQuicInitial() -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 256)
        var offset = 0

        // Flags: Long Header, Initial packet type (0xc3)
        buf[offset] = 0xc3; offset += 1

        // Version: QUIC v1 (0x00000001) — big-endian
        buf[offset] = 0x00; offset += 1
        buf[offset] = 0x00; offset += 1
        buf[offset] = 0x00; offset += 1
        buf[offset] = 0x01; offset += 1

        // DCID Length = 8
        buf[offset] = 0x08; offset += 1
        // DCID: 8 random bytes
        for _ in 0..<8 { buf[offset] = UInt8.random(in: 0...255); offset += 1 }

        // SCID Length = 0
        buf[offset] = 0x00; offset += 1

        // Token Length = 0
        buf[offset] = 0x00; offset += 1

        // Length (2 bytes, remaining after this field) with QUIC variable-length encoding
        let remaining = 256 - offset - 2
        // Write as UInt16BE with 0x4000 flag (2-byte variable-length integer)
        let lengthWord = UInt16(0x4000) | UInt16(remaining)
        buf[offset] = UInt8((lengthWord >> 8) & 0xFF); offset += 1
        buf[offset] = UInt8(lengthWord & 0xFF); offset += 1

        // Packet Number (4 bytes, big-endian): 0x00000001
        buf[offset] = 0x00; offset += 1
        buf[offset] = 0x00; offset += 1
        buf[offset] = 0x00; offset += 1
        buf[offset] = 0x01; offset += 1

        // Fill rest with random data to look like encrypted payload
        for i in offset..<256 {
            buf[i] = UInt8.random(in: 0...255)
        }

        return buf
    }

    /// Generate fake TLS ClientHello with SNI extension.
    /// Mirrors electron-main.js generateFakeTlsClientHello(sni).
    public static func fakeTlsClientHello(sni: String = "www.google.com") -> [UInt8] {
        let sniBytes = Array(sni.utf8)

        // Build SNI extension (9 + sniBytes.count bytes)
        var sniExt = [UInt8](repeating: 0, count: 9 + sniBytes.count)
        var off = 0
        // Extension type: server_name (0x0000)
        sniExt[off] = 0x00; off += 1
        sniExt[off] = 0x00; off += 1
        // Extension data length = 5 + sniBytes.count
        let extDataLen = UInt16(5 + sniBytes.count)
        sniExt[off] = UInt8((extDataLen >> 8) & 0xFF); off += 1
        sniExt[off] = UInt8(extDataLen & 0xFF); off += 1
        // Server Name List Length = 3 + sniBytes.count
        let listLen = UInt16(3 + sniBytes.count)
        sniExt[off] = UInt8((listLen >> 8) & 0xFF); off += 1
        sniExt[off] = UInt8(listLen & 0xFF); off += 1
        // Server Name Type: host_name (0)
        sniExt[off] = 0x00; off += 1
        // Server Name Length
        let nameLen = UInt16(sniBytes.count)
        sniExt[off] = UInt8((nameLen >> 8) & 0xFF); off += 1
        sniExt[off] = UInt8(nameLen & 0xFF); off += 1
        // Server Name bytes
        for byte in sniBytes { sniExt[off] = byte; off += 1 }

        // Random (32 bytes)
        var random = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { random[i] = UInt8.random(in: 0...255) }

        // Cipher suites: 2 suites (4 bytes) + 2-byte length field
        let cipherSuites: [UInt8] = [
            0x00, 0x04,  // length: 2 suites (4 bytes)
            0x13, 0x01,  // TLS_AES_128_GCM_SHA256
            0x13, 0x02   // TLS_AES_256_GCM_SHA384
        ]

        // Compression methods: 1 method: null
        let compression: [UInt8] = [0x01, 0x00]

        // Extensions length (2 bytes)
        let extLen = UInt16(sniExt.count)
        let extensionsLen: [UInt8] = [UInt8((extLen >> 8) & 0xFF), UInt8(extLen & 0xFF)]

        // ClientHello body = TLS version + random + session ID length + cipher suites + compression + extensions
        var clientHelloBody = [UInt8]()
        clientHelloBody += [0x03, 0x03]    // TLS 1.2
        clientHelloBody += random
        clientHelloBody += [0x00]          // Session ID length: 0
        clientHelloBody += cipherSuites
        clientHelloBody += compression
        clientHelloBody += extensionsLen
        clientHelloBody += sniExt

        // Handshake header: type(1) + length(3)
        var handshake = [UInt8](repeating: 0, count: 4 + clientHelloBody.count)
        handshake[0] = 0x01  // ClientHello
        handshake[1] = 0x00
        let chLen = UInt16(clientHelloBody.count)
        handshake[2] = UInt8((chLen >> 8) & 0xFF)
        handshake[3] = UInt8(chLen & 0xFF)
        for (i, byte) in clientHelloBody.enumerated() { handshake[4 + i] = byte }

        // TLS record: type(1) + version(2) + length(2) + handshake
        var record = [UInt8](repeating: 0, count: 5 + handshake.count)
        record[0] = 0x16   // Handshake
        // TLS 1.0 record layer (0x0301)
        record[1] = 0x03
        record[2] = 0x01
        let hsLen = UInt16(handshake.count)
        record[3] = UInt8((hsLen >> 8) & 0xFF)
        record[4] = UInt8(hsLen & 0xFF)
        for (i, byte) in handshake.enumerated() { record[5 + i] = byte }

        return record
    }
}
