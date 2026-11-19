import Darwin
import NetworkExtension

/// The VPN itself: iOS starts this extension when you tap connect.
/// It sets up the utun interface, then hands its file descriptor to Xray.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    enum TunnelError: LocalizedError {
        case noNode
        case tunNotFound

        var errorDescription: String? {
            switch self {
            case .noNode: return "还没有导入节点"
            case .tunNotFound: return "找不到系统 VPN 接口（utun）"
            }
        }
    }

    override func startTunnel(options: [String: NSObject]?) async throws {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let link = proto.providerConfiguration?[ProviderKeys.link] as? String
        else { throw TunnelError.noNode }
        let node = try VLESSLink(link)

        try await setTunnelNetworkSettings(Self.networkSettings(remoteAddress: node.host))

        guard let fd = Self.tunnelFileDescriptor() else { throw TunnelError.tunNotFound }
        let config = try XrayConfig.make(
            node: node,
            tunFileDescriptor: fd,
            assetDirectory: Bundle.main.resourcePath ?? ""
        )
        try XrayCore.run(configJSON: config)
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        XrayCore.stop()
    }

    /// Sends all IPv4 and IPv6 traffic and all DNS lookups into the tunnel.
    /// The extension's own connections (Xray to the server) bypass it automatically.
    private static func networkSettings(remoteAddress: String) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteAddress)
        settings.mtu = 1500

        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let ipv6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: [XrayConfig.tunnelDNSServer])
        dns.matchDomains = [""] // use it for every domain
        settings.dnsSettings = dns
        return settings
    }

    /// Finds the utun file descriptor NetworkExtension opened for this tunnel,
    /// the way Xray-core's proxy/tun README describes.
    private static func tunnelFileDescriptor() -> Int32? {
        var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        let utunPrefix = Array("utun".utf8CString.dropLast())
        for fd: Int32 in 0...1024 {
            var length = socklen_t(name.count)
            // level SYSPROTO_CONTROL (2), option UTUN_OPT_IFNAME (2)
            if getsockopt(fd, 2, 2, &name, &length) == 0, name.starts(with: utunPrefix) {
                return fd
            }
        }
        return nil
    }
}
