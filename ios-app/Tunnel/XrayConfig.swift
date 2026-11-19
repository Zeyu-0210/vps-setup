import Foundation

/// Builds the Xray JSON config that runs inside the packet tunnel.
///
/// Apps → iOS utun → Xray `tun` inbound → routing:
/// - DNS (port 53) is answered by Xray's DNS: Chinese domains through 223.5.5.5 (direct),
///   everything else through 1.1.1.1 over the proxy.
/// - Chinese domains and Chinese / private IPs go direct, so Chinese sites see a Chinese IP and stay fast.
/// - Everything else goes through VLESS + REALITY to the server.
enum XrayConfig {
    /// The DNS server iOS is told to use; it sits inside the tunnel, so its queries reach Xray.
    static let tunnelDNSServer = "172.19.0.2"

    static func make(node: VLESSLink, tunFileDescriptor: Int32, assetDirectory: String) throws -> String {
        let config: [String: Any] = [
            // Xray reads these as environment variables: the utun fd from NetworkExtension,
            // and where geoip.dat / geosite.dat are (bundled in the extension).
            "env": [
                "xray.tun.fd": String(tunFileDescriptor),
                "xray.location.asset": assetDirectory,
            ],
            "log": ["loglevel": "warning", "access": "none"],
            "dns": [
                "servers": [
                    [
                        "address": "223.5.5.5",
                        "domains": ["geosite:cn"],
                        "expectIPs": ["geoip:cn"],
                        "skipFallback": true,
                    ],
                    ["address": "1.1.1.1"],
                ],
                "queryStrategy": "UseIPv4",
            ],
            "inbounds": [
                [
                    "tag": "tun",
                    "port": 0,
                    "protocol": "tun",
                    "settings": ["name": "xray0", "mtu": 1500],
                    "sniffing": [
                        "enabled": true,
                        "destOverride": ["http", "tls", "quic"],
                        "routeOnly": true,
                    ],
                ],
            ],
            "outbounds": [
                proxyOutbound(node), // the first outbound is the default
                ["tag": "direct", "protocol": "freedom"],
                ["tag": "block", "protocol": "blackhole"],
                ["tag": "dns-out", "protocol": "dns"],
            ],
            "routing": [
                "domainStrategy": "IPIfNonMatch",
                "rules": [
                    ["inboundTag": ["tun"], "port": "53", "outboundTag": "dns-out"],
                    ["ip": ["1.1.1.1"], "outboundTag": "proxy"],
                    // Chinese domains always go direct, even when DNS returns an overseas IP:
                    // the server blocks them (install.sh), so through the proxy they would fail.
                    ["domain": ["geosite:cn"], "outboundTag": "direct"],
                    ["ip": ["geoip:cn", "geoip:private"], "outboundTag": "direct"],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func proxyOutbound(_ node: VLESSLink) -> [String: Any] {
        var reality: [String: Any] = [
            "serverName": node.serverName,
            "fingerprint": node.fingerprint,
            "publicKey": node.publicKey,
            "shortId": node.shortId,
        ]
        if !node.spiderX.isEmpty {
            reality["spiderX"] = node.spiderX
        }
        return [
            "tag": "proxy",
            "protocol": "vless",
            "settings": [
                "address": node.host,
                "port": node.port,
                "id": node.uuid,
                "flow": node.flow,
                "encryption": "none",
            ],
            "streamSettings": [
                "network": "tcp",
                "security": "reality",
                "realitySettings": reality,
            ],
        ]
    }
}
