import Foundation

/// Keys of `NETunnelProviderProtocol.providerConfiguration`, shared by the app and the tunnel.
enum ProviderKeys {
    static let link = "link"
}

/// A VLESS + REALITY node parsed from a `vless://` share link,
/// the format printed by install.sh in this repository.
struct VLESSLink: Equatable {
    var uuid: String
    var host: String
    var port: Int
    var flow: String
    var serverName: String
    var fingerprint: String
    var publicKey: String
    var shortId: String
    var spiderX: String
    var name: String

    enum ParseError: LocalizedError {
        case notVLESS
        case missing(String)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notVLESS: return "这不是 vless:// 链接"
            case .missing(let field): return "链接里缺少 \(field)"
            case .unsupported(let what): return "暂不支持：\(what)"
            }
        }
    }

    init(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("vless://"),
              let components = URLComponents(string: trimmed)
        else { throw ParseError.notVLESS }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }

        guard let uuid = components.user, !uuid.isEmpty else { throw ParseError.missing("UUID") }
        guard var host = components.host, !host.isEmpty else { throw ParseError.missing("服务器地址") }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        guard let port = components.port, (1...65535).contains(port) else { throw ParseError.missing("端口") }

        let security = query["security"] ?? ""
        guard security == "reality" else {
            throw ParseError.unsupported("security=\(security.isEmpty ? "无" : security)，只支持 reality")
        }
        let network = query["type"] ?? "tcp"
        guard network == "tcp" || network == "raw" else {
            throw ParseError.unsupported("type=\(network)，只支持 tcp")
        }
        let encryption = query["encryption"] ?? "none"
        guard encryption == "none" else { throw ParseError.unsupported("encryption=\(encryption)") }
        guard let publicKey = query["pbk"], !publicKey.isEmpty else { throw ParseError.missing("pbk（公钥）") }
        guard let serverName = query["sni"], !serverName.isEmpty else { throw ParseError.missing("sni（伪装网站）") }

        self.uuid = uuid
        self.host = host
        self.port = port
        self.flow = query["flow"] ?? ""
        self.serverName = serverName
        self.fingerprint = query["fp"].flatMap { $0.isEmpty ? nil : $0 } ?? "chrome"
        self.publicKey = publicKey
        self.shortId = query["sid"] ?? ""
        self.spiderX = query["spx"] ?? ""
        self.name = components.fragment ?? ""
    }

    /// `host:port`, with IPv6 hosts in brackets.
    var address: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}
