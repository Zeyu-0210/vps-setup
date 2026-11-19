import NetworkExtension
import SwiftUI
import UIKit

enum Theme {
    /// Light blue, the same as the GitHub profile: #2F80C9 in light mode, #6CB8F5 in dark mode.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.72, blue: 0.96, alpha: 1)
            : UIColor(red: 0.18, green: 0.50, blue: 0.79, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct ContentView: View {
    @StateObject private var tunnel = TunnelManager()
    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    PowerButton(status: tunnel.status, enabled: tunnel.node != nil) {
                        tunnel.toggle()
                    }
                    .padding(.top, 28)

                    StatusText(status: tunnel.status, hasNode: tunnel.node != nil, connectedDate: tunnel.connectedDate)

                    NodeCard(node: tunnel.node) { showingImport = true }

                    if tunnel.status == .connected {
                        LatencyCard()
                    }

                    if let message = tunnel.message {
                        MessageBanner(message: message)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("ZeyuVPN")
            .sheet(isPresented: $showingImport) {
                ImportView { link in
                    try await tunnel.save(link: link)
                }
            }
        }
        .tint(Theme.accent)
    }
}

private struct PowerButton: View {
    let status: NEVPNStatus
    let enabled: Bool
    let action: () -> Void

    private var isOn: Bool { status == .connected }
    private var isBusy: Bool {
        status == .connecting || status == .disconnecting || status == .reasserting
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isOn ? Theme.accent : Theme.card)
                    .shadow(color: Theme.accent.opacity(isOn ? 0.45 : 0.15), radius: isOn ? 26 : 12)
                Circle()
                    .strokeBorder(Theme.accent.opacity(isOn ? 0 : 0.35), lineWidth: 2)
                if isBusy {
                    ProgressView()
                        .controlSize(.large)
                        .tint(isOn ? .white : Theme.accent)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(isOn ? Color.white : Theme.accent)
                }
            }
            .frame(width: 168, height: 168)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || status == .disconnecting)
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.25), value: status)
        .accessibilityLabel(isOn ? "断开 VPN" : "连接 VPN")
    }
}

private struct StatusText: View {
    let status: NEVPNStatus
    let hasNode: Bool
    let connectedDate: Date?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
            if status == .connected, let connectedDate {
                Text(connectedDate, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        guard hasNode else { return "先导入一个节点" }
        switch status {
        case .connected: return "已连接"
        case .connecting: return "正在连接…"
        case .disconnecting: return "正在断开…"
        case .reasserting: return "正在重新连接…"
        case .disconnected, .invalid: return "未连接"
        @unknown default: return "未知状态"
        }
    }
}

private struct NodeCard: View {
    let node: VLESSLink?
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("节点", systemImage: "server.rack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(node == nil ? "导入" : "更换", action: onImport)
                    .font(.subheadline.weight(.semibold))
            }
            if let node {
                Text(node.name.isEmpty ? "未命名节点" : node.name)
                    .font(.headline)
                InfoRow(label: "地址", value: node.address)
                InfoRow(label: "协议", value: "VLESS · REALITY")
                InfoRow(label: "伪装", value: node.serverName)
            } else {
                Text("复制服务器部署脚本打印的 vless:// 链接，再点「导入」。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
    }
}

/// Times an HTTPS request to Google through the tunnel, as a quick "does it work" check.
private struct LatencyCard: View {
    @State private var result = "—"
    @State private var testing = false

    var body: some View {
        HStack {
            Label("Google 连通测试", systemImage: "speedometer")
                .foregroundStyle(.secondary)
            Spacer()
            Text(result)
                .monospacedDigit()
            Button {
                Task { await test() }
            } label: {
                if testing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(testing)
        }
        .font(.subheadline)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task { await test() }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        var request = URLRequest(url: URL(string: "https://www.gstatic.com/generate_204")!, timeoutInterval: 8)
        request.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            result = (response as? HTTPURLResponse)?.statusCode == 204 ? "\(milliseconds) ms" : "异常"
        } catch {
            result = "不通"
        }
    }
}

private struct MessageBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
