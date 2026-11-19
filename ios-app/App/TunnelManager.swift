import Foundation
import NetworkExtension

/// Owns the app's single VPN configuration and mirrors its state for the UI.
/// The node link is stored in the system VPN configuration itself, where the tunnel extension reads it.
@MainActor
final class TunnelManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var node: VLESSLink?
    @Published private(set) var connectedDate: Date?
    @Published var message: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    /// The tunnel extension's bundle ID: the app's ID plus ".tunnel" (see project.yml).
    private var tunnelBundleID: String {
        (Bundle.main.bundleIdentifier ?? "") + ".tunnel"
    }

    init() {
        Task { await load() }
    }

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let existing = managers.first {
                attach(existing)
            }
        } catch {
            message = "读取 VPN 配置失败：\(error.localizedDescription)"
        }
    }

    /// Checks the link and saves it as the VPN configuration.
    /// The first save makes iOS ask for permission to add a VPN configuration.
    func save(link: String) async throws {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try VLESSLink(link)
        let wasActive = isActive

        let manager = self.manager ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress = parsed.address
        proto.providerConfiguration = [ProviderKeys.link: link]
        manager.protocolConfiguration = proto
        manager.localizedDescription = "ZeyuVPN"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        attach(manager)

        if wasActive {
            manager.connection.stopVPNTunnel()
            message = "节点已更换，请重新连接"
        } else {
            message = nil
        }
    }

    func toggle() {
        if isActive {
            manager?.connection.stopVPNTunnel()
        } else if status == .disconnected || status == .invalid {
            Task { await connect() }
        }
    }

    private var isActive: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    private func connect() async {
        guard let manager else { return }
        do {
            if !manager.isEnabled {
                manager.isEnabled = true
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()
            }
            message = nil
            try manager.connection.startVPNTunnel()
        } catch {
            message = "连接失败：\(error.localizedDescription)"
        }
    }

    private func attach(_ manager: NETunnelProviderManager) {
        self.manager = manager
        let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
        let link = proto?.providerConfiguration?[ProviderKeys.link] as? String
        node = link.flatMap { try? VLESSLink($0) }

        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        refreshStatus()
    }

    private func refreshStatus() {
        guard let connection = manager?.connection else { return }
        let previous = status
        status = connection.status
        connectedDate = connection.connectedDate

        // When a connection drops, show why (for example an error thrown by the tunnel extension).
        if status == .disconnected, previous == .connecting || previous == .connected || previous == .reasserting {
            connection.fetchLastDisconnectError { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.message = error.localizedDescription }
            }
        }
    }
}
