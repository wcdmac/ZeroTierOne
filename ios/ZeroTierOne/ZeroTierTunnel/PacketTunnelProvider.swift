import NetworkExtension
import Foundation

enum TunnelError: Error {
    case badConfiguration
    case timeout
}

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var nodeBridge: ZTNodeBridge!
    private var tunnelReady = false
    private var startCompleter: ((Error?) -> Void)?
    private var readPacketsActive = false
    private let appGroupIdentifier = "group.com.zerotier.ZeroTierOne"

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("[ZT-Tunnel] startTunnel called")

        let providerConfig = protocolConfiguration.providerConfiguration
        let networkId = (providerConfig?["networkId"] as? String) ?? ""

        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        let dataPath = (containerURL?.path ?? NSTemporaryDirectory()) + "/zerotier"

        NSLog("[ZT-Tunnel] Data path: %@", dataPath)
        NSLog("[ZT-Tunnel] Network ID: %@", networkId)

        nodeBridge = ZTNodeBridge(dataPath: dataPath)

        nodeBridge.onStatusChanged = { [weak self] online in
            NSLog("[ZT-Tunnel] Status changed: online=%@", online ? "YES" : "NO")
            self?.updateSharedStatus()
        }

        nodeBridge.onNetworkConfigChanged = { [weak self] config in
            NSLog("[ZT-Tunnel] Network config changed: %@", config)
            self?.handleNetworkConfig(config)
        }

        nodeBridge.onFrameReceived = { [weak self] frameData, etherType in
            self?.handleFrameReceived(frameData: frameData, etherType: etherType)
        }

        nodeBridge.onLogMessage = { message in
            NSLog("[ZT-Tunnel] %@", message)
        }

        if !nodeBridge.startNode() {
            NSLog("[ZT-Tunnel] Failed to start node")
            completionHandler(TunnelError.badConfiguration)
            return
        }

        if !networkId.isEmpty {
            nodeBridge.joinNetwork(networkId)
        }

        startCompleter = completionHandler

        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            if !self.tunnelReady {
                NSLog("[ZT-Tunnel] Timeout waiting for network config, completing with basic settings")
                self.applyBasicNetworkSettings(completionHandler: completionHandler)
            }
        }
    }

    private func handleNetworkConfig(_ config: [AnyHashable: Any]) {
        guard !tunnelReady else {
            NSLog("[ZT-Tunnel] Tunnel already ready, updating settings")
            applyNetworkSettings(config)
            return
        }

        applyNetworkSettings(config) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                NSLog("[ZT-Tunnel] Failed to apply network settings: %@", error.localizedDescription)
                self.startCompleter?(error)
                self.startCompleter = nil
            } else {
                NSLog("[ZT-Tunnel] Network settings applied successfully")
                self.tunnelReady = true
                self.startCompleter?(nil)
                self.startCompleter = nil
                self.startReadingPackets()
            }
        }
    }

    private func applyBasicNetworkSettings(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "0.0.0.0")

        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4Settings

        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        settings.dnsSettings = dnsSettings
        settings.mtu = 2800

        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                completionHandler(error)
            } else {
                self.tunnelReady = true
                completionHandler(nil)
                self.startReadingPackets()
            }
        }
    }

    private func applyNetworkSettings(_ config: [AnyHashable: Any], completion: ((Error?) -> Void)? = nil) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "0.0.0.0")

        let ipv4Addresses = config["ipv4Addresses"] as? [String] ?? []
        let ipv6Addresses = config["ipv6Addresses"] as? [String] ?? []
        let routes = config["routes"] as? [[AnyHashable: Any]] ?? []

        if !ipv4Addresses.isEmpty {
            let ipv4Settings = NEIPv4Settings(
                addresses: ipv4Addresses,
                subnetMasks: Array(repeating: "255.255.255.0", count: ipv4Addresses.count)
            )

            var includedRoutes: [NEIPv4Route] = []
            for addr in ipv4Addresses {
                if let route = try? NEIPv4Route(destinationAddress: addr, subnetMask: "255.255.255.0") {
                    includedRoutes.append(route)
                }
            }

            for routeDict in routes {
                if let target = routeDict["target"] as? String {
                    if let route = try? NEIPv4Route(destinationAddress: target, subnetMask: "255.255.255.0") {
                        if let via = routeDict["via"] as? String {
                            route.gatewayAddress = via
                        }
                        includedRoutes.append(route)
                    }
                }
            }

            if includedRoutes.isEmpty {
                includedRoutes.append(NEIPv4Route.default())
            }

            ipv4Settings.includedRoutes = includedRoutes
            settings.ipv4Settings = ipv4Settings
        } else {
            let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.1"], subnetMasks: ["255.255.255.0"])
            ipv4Settings.includedRoutes = [NEIPv4Route.default()]
            settings.ipv4Settings = ipv4Settings
        }

        if !ipv6Addresses.isEmpty {
            let ipv6Settings = NEIPv6Settings(
                addresses: ipv6Addresses,
                networkPrefixLengths: Array(repeating: 64, count: ipv6Addresses.count)
            )
            settings.ipv6Settings = ipv6Settings
        }

        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        settings.dnsSettings = dnsSettings

        if let mtu = config["mtu"] as? Int, mtu > 0 {
            settings.mtu = NSNumber(value: mtu)
        } else {
            settings.mtu = 2800
        }

        setTunnelNetworkSettings(settings) { error in
            completion?(error)
        }
    }

    private func startReadingPackets() {
        guard !readPacketsActive else { return }
        readPacketsActive = true
        readPacketsLoop()
    }

    private func readPacketsLoop() {
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self, self.readPacketsActive else { return }
            self.handlePackets(packets: packets, protocols: protocols)
            self.readPacketsLoop()
        }
    }

    private func handlePackets(packets: [Data], protocols: [NSNumber]) {
        for (packet, proto) in zip(packets, protocols) {
            let etherType: UInt32
            if proto.int32Value == AF_INET {
                etherType = 0x0800
            } else if proto.int32Value == AF_INET6 {
                etherType = 0x86DD
            } else {
                continue
            }
            nodeBridge.sendFrame(packet, etherType: etherType)
        }
    }

    private func handleFrameReceived(frameData: Data, etherType: UInt32) {
        let proto: NSNumber
        if etherType == 0x0800 {
            proto = NSNumber(value: AF_INET)
        } else if etherType == 0x86DD {
            proto = NSNumber(value: AF_INET6)
        } else {
            return
        }
        packetFlow.writePackets([frameData], withProtocols: [proto])
    }

    private func updateSharedStatus() {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(nodeBridge.isNodeOnline(), forKey: "isOnline")
        defaults?.set(nodeBridge.isConnected(), forKey: "isConnected")
        defaults?.set(nodeBridge.currentNetworkId(), forKey: "currentNetworkId")
        defaults?.set(nodeBridge.nodeId(), forKey: "nodeId")
        defaults?.synchronize()
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("[ZT-Tunnel] stopTunnel called, reason: %d", reason.rawValue)
        readPacketsActive = false
        nodeBridge?.stopNode()
        tunnelReady = false
        startCompleter = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard messageData.count > 0 else {
            completionHandler?(nil)
            return
        }

        let command = messageData[0]
        switch command {
        case 0x01:
            let nodeId = nodeBridge?.nodeId() ?? ""
            completionHandler?(nodeId.data(using: .utf8))

        case 0x02:
            let online = nodeBridge?.isNodeOnline() ?? false
            let connected = nodeBridge?.isConnected() ?? false
            let status = "\(online ? 1 : 0):\(connected ? 1 : 0)"
            completionHandler?(status.data(using: .utf8))

        case 0x03:
            let logs = nodeBridge?.logEntries().joined(separator: "\n") ?? ""
            completionHandler?(logs.data(using: .utf8))

        case 0x04:
            let info = nodeBridge?.peerInfo() ?? ""
            completionHandler?(info.data(using: .utf8))

        case 0x05:
            let statusInfo = nodeBridge?.nodeStatusInfo() ?? ""
            completionHandler?(statusInfo.data(using: .utf8))

        case 0x06:
            if messageData.count > 1,
               let networkId = String(data: messageData.subdata(in: 1..<messageData.count), encoding: .utf8) {
                nodeBridge?.joinNetwork(networkId)
            }
            completionHandler?("ok".data(using: .utf8))

        case 0x07:
            nodeBridge?.leaveNetwork()
            completionHandler?("ok".data(using: .utf8))

        default:
            completionHandler?(nil)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        NSLog("[ZT-Tunnel] sleep called")
        completionHandler()
    }

    override func wake() {
        NSLog("[ZT-Tunnel] wake called")
    }
}
