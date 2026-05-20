import Foundation
import NetworkExtension

@objcMembers
class ZeroTierBridge: NSObject {

    var connected: Bool = false
    var currentNetworkId: String?
    var onStatusChange: ((Bool) -> Void)?
    var onOnlineStatusChange: ((Bool) -> Void)?
    var onLogUpdate: (() -> Void)?

    private var vpnManager: NETunnelProviderManager?
    private let appGroupIdentifier = "group.com.zerotier.ZeroTierOne"
    private let tunnelBundleIdentifier = "com.zerotier.ZeroTierOne.Tunnel"
    private var statusTimer: Timer?
    private var logTimer: Timer?
    private var cachedLogEntries: [String] = []
    private var cachedNodeId: String = "--------"

    override init() {
        super.init()
        loadVPNManager()
        observeVPNStatus()
    }

    private func loadVPNManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                NSLog("[ZT-App] loadVPNManager error: %@", error.localizedDescription)
            }
            if let manager = managers?.first {
                self?.vpnManager = manager
                NSLog("[ZT-App] Loaded existing VPN manager")
            } else {
                let manager = NETunnelProviderManager()
                self?.vpnManager = manager
                NSLog("[ZT-App] Created new VPN manager")
            }
            self?.updateStatusFromVPN()
        }
    }

    private func observeVPNStatus() {
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusFromVPN()
        }
    }

    private func updateStatusFromVPN() {
        guard let session = vpnManager?.connection as? NETunnelProviderSession else {
            return
        }
        let status = session.status
        NSLog("[ZT-App] VPN status changed: %d", status.rawValue)

        switch status {
        case .connected:
            connected = true
            onStatusChange?(true)
            startStatusPolling()
        case .disconnected:
            connected = false
            currentNetworkId = nil
            onStatusChange?(false)
            onOnlineStatusChange?(false)
            stopStatusPolling()
        case .connecting, .reasserting:
            break
        case .invalid:
            connected = false
            onStatusChange?(false)
            onOnlineStatusChange?(false)
            stopStatusPolling()
        default:
            break
        }
    }

    private func startStatusPolling() {
        stopStatusPolling()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollExtensionStatus()
        }
        logTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollExtensionLogs()
        }
        pollExtensionStatus()
        pollExtensionLogs()
    }

    private func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
        logTimer?.invalidate()
        logTimer = nil
    }

    private func pollExtensionStatus() {
        sendIPCMessage(Data([0x02])) { [weak self] data in
            guard let data = data,
                  let statusStr = String(data: data, encoding: .utf8) else { return }
            let parts = statusStr.split(separator: ":")
            if parts.count >= 2 {
                let online = parts[0] == "1"
                let connected = parts[1] == "1"
                DispatchQueue.main.async {
                    self?.onOnlineStatusChange?(online)
                    self?.connected = connected
                    if connected {
                        self?.onStatusChange?(true)
                    }
                }
            }
        }

        sendIPCMessage(Data([0x01])) { [weak self] data in
            guard let data = data,
                  let nodeId = String(data: data, encoding: .utf8),
                  !nodeId.isEmpty, nodeId != "--------" else { return }
            DispatchQueue.main.async {
                self?.cachedNodeId = nodeId
                let defaults = UserDefaults(suiteName: self?.appGroupIdentifier ?? "")
                defaults?.set(nodeId, forKey: "nodeId")
                defaults?.synchronize()
            }
        }
    }

    private func pollExtensionLogs() {
        sendIPCMessage(Data([0x03])) { [weak self] data in
            guard let data = data,
                  let logsStr = String(data: data, encoding: .utf8) else { return }
            let entries = logsStr.components(separatedBy: "\n").filter { !$0.isEmpty }
            DispatchQueue.main.async {
                self?.cachedLogEntries = entries
                self?.onLogUpdate?()
            }
        }
    }

    private func sendIPCMessage(_ message: Data, completionHandler: ((Data?) -> Void)? = nil) {
        guard let session = vpnManager?.connection as? NETunnelProviderSession else {
            completionHandler?(nil)
            return
        }
        do {
            try session.sendProviderMessage(message) { responseData in
                completionHandler?(responseData)
            }
        } catch {
            NSLog("[ZT-App] sendProviderMessage error: %@", error.localizedDescription)
            completionHandler?(nil)
        }
    }

    func nodeId() -> String {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        if let nodeId = defaults?.string(forKey: "nodeId"), nodeId != "--------", !nodeId.isEmpty {
            cachedNodeId = nodeId
            return nodeId
        }
        if cachedNodeId != "--------" {
            return cachedNodeId
        }
        return "--------"
    }

    func isNodeOnline() -> Bool {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        return defaults?.bool(forKey: "isOnline") ?? false
    }

    func isNodeRunning() -> Bool {
        guard let session = vpnManager?.connection as? NETunnelProviderSession else { return false }
        return session.status == .connected || session.status == .connecting || session.status == .reasserting
    }

    func startNode() -> Bool {
        guard let session = vpnManager?.connection as? NETunnelProviderSession else { return false }
        if session.status == .connected || session.status == .connecting {
            return true
        }
        do {
            try session.startVPNTunnel()
            return true
        } catch {
            NSLog("[ZT-App] startVPNTunnel error: %@", error.localizedDescription)
            return false
        }
    }

    func stopNode() {
        vpnManager?.connection.stopVPNTunnel()
    }

    func joinNetwork(_ networkId: String, completion: @escaping (Bool) -> Void) {
        guard let manager = vpnManager else {
            completion(false)
            return
        }

        let providerConfig: [String: Any] = [
            "networkId": networkId
        ]

        let proto = NETunnelProviderProtocol()
        proto.providerConfiguration = providerConfig
        proto.providerBundleIdentifier = tunnelBundleIdentifier
        proto.serverAddress = "ZeroTier"

        manager.protocolConfiguration = proto
        manager.localizedDescription = "ZeroTier One"
        manager.isEnabled = true

        manager.saveToPreferences { [weak self] error in
            if let error = error {
                NSLog("[ZT-App] saveToPreferences error: %@", error.localizedDescription)
                completion(false)
                return
            }

            manager.loadFromPreferences { error in
                if let error = error {
                    NSLog("[ZT-App] loadFromPreferences error: %@", error.localizedDescription)
                    completion(false)
                    return
                }

                guard let session = manager.connection as? NETunnelProviderSession else {
                    completion(false)
                    return
                }

                do {
                    try session.startVPNTunnel()
                    self?.currentNetworkId = networkId
                    self?.saveNetwork(networkId)
                    completion(true)
                } catch {
                    NSLog("[ZT-App] startVPNTunnel error: %@", error.localizedDescription)
                    completion(false)
                }
            }
        }
    }

    func leaveNetwork() {
        sendIPCMessage(Data([0x07]))
        vpnManager?.connection.stopVPNTunnel()
        connected = false
        if let nwid = currentNetworkId {
            removeNetwork(nwid)
        }
        currentNetworkId = nil
        onStatusChange?(false)
        onOnlineStatusChange?(false)
    }

    func logEntries() -> [String] {
        return cachedLogEntries
    }

    func peerInfo() -> String {
        var result = ""
        let semaphore = DispatchSemaphore(value: 0)
        sendIPCMessage(Data([0x04])) { data in
            if let data = data, let str = String(data: data, encoding: .utf8) {
                result = str
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return result
    }

    func nodeStatusInfo() -> String {
        var result = ""
        let semaphore = DispatchSemaphore(value: 0)
        sendIPCMessage(Data([0x05])) { data in
            if let data = data, let str = String(data: data, encoding: .utf8) {
                result = str
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
        return result
    }

    func savedNetworks() -> [String] {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        return defaults?.stringArray(forKey: "savedNetworks") ?? []
    }

    func fullIdentityString() -> String? {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        let identityPath = containerURL?.appendingPathComponent("zerotier/identity.secret").path
        if let path = identityPath {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        return nil
    }

    func publicIdentityString() -> String? {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        let identityPath = containerURL?.appendingPathComponent("zerotier/identity.public").path
        if let path = identityPath {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        return nil
    }

    private func saveNetwork(_ networkId: String) {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        var networks = defaults?.stringArray(forKey: "savedNetworks") ?? []
        if !networks.contains(networkId) {
            networks.append(networkId)
            defaults?.set(networks, forKey: "savedNetworks")
            defaults?.synchronize()
        }
    }

    private func removeNetwork(_ networkId: String) {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        var networks = defaults?.stringArray(forKey: "savedNetworks") ?? []
        networks.removeAll { $0 == networkId }
        defaults?.set(networks, forKey: "savedNetworks")
        defaults?.synchronize()
    }

    static func sharedInstance() -> ZeroTierBridge {
        struct Singleton {
            static let instance = ZeroTierBridge()
        }
        return Singleton.instance
    }
}
