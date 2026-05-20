import UIKit

class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let networkVC = NetworkViewController()
        networkVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("TAB_NETWORK", value: "Network", comment: "Network tab"),
            image: UIImage(systemName: "network"),
            selectedImage: UIImage(systemName: "network.fill")
        )

        let identityVC = IdentityViewController()
        identityVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("TAB_IDENTITY", value: "Identity", comment: "Identity tab"),
            image: UIImage(systemName: "key"),
            selectedImage: UIImage(systemName: "key.fill")
        )

        let logVC = LogViewController()
        logVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("TAB_LOG", value: "Log", comment: "Log tab"),
            image: UIImage(systemName: "list.bullet.rectangle"),
            selectedImage: UIImage(systemName: "list.bullet.rectangle.fill")
        )

        let settingsVC = SettingsViewController()
        settingsVC.tabBarItem = UITabBarItem(
            title: NSLocalizedString("TAB_SETTINGS", value: "Settings", comment: "Settings tab"),
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        viewControllers = [
            UINavigationController(rootViewController: networkVC),
            UINavigationController(rootViewController: identityVC),
            UINavigationController(rootViewController: logVC),
            UINavigationController(rootViewController: settingsVC)
        ]
    }
}

class NetworkViewController: UIViewController {

    private var statusLabel: UILabel!
    private var nodeIdLabel: UILabel!
    private var networkIdTextField: UITextField!
    private var joinButton: UIButton!
    private var leaveButton: UIButton!
    private var networkListView: UITableView!
    private var statusImageView: UIImageView!
    private var statsLabel: UILabel!

    private let ztBridge = ZeroTierBridge.sharedInstance()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("NETWORK_TITLE", value: "ZeroTier One", comment: "Network page title")
        setupUI()

        ztBridge.onOnlineStatusChange = { [weak self] online in
            self?.updateStatus()
        }
        ztBridge.onStatusChange = { [weak self] connected in
            self?.updateStatus()
            self?.networkListView.reloadData()
        }

        ztBridge.startNode()
        updateStatus()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        statusImageView = UIImageView()
        statusImageView.contentMode = .scaleAspectFit
        statusImageView.translatesAutoresizingMaskIntoConstraints = false
        statusImageView.tintColor = .systemGray
        let config = UIImage.SymbolConfiguration(pointSize: 50, weight: .regular)
        statusImageView.image = UIImage(systemName: "network", withConfiguration: config)
        view.addSubview(statusImageView)

        statusLabel = UILabel()
        statusLabel.font = .preferredFont(forTextStyle: .title3)
        statusLabel.textAlignment = .center
        statusLabel.text = NSLocalizedString("STATUS_OFFLINE", value: "Offline", comment: "Offline status")
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        nodeIdLabel = UILabel()
        nodeIdLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        nodeIdLabel.textAlignment = .center
        nodeIdLabel.text = String(format: NSLocalizedString("NODE_ID_FORMAT", value: "Node: %@", comment: "Node ID format"), ztBridge.nodeId())
        nodeIdLabel.textColor = .systemBlue
        nodeIdLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nodeIdLabel)

        statsLabel = UILabel()
        statsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textAlignment = .center
        statsLabel.textColor = .tertiaryLabel
        statsLabel.numberOfLines = 0
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsLabel)

        networkIdTextField = UITextField()
        networkIdTextField.placeholder = NSLocalizedString("NETWORK_ID_PLACEHOLDER", value: "Enter Network ID (16 hex digits)", comment: "Network ID placeholder")
        networkIdTextField.borderStyle = .roundedRect
        networkIdTextField.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        networkIdTextField.keyboardType = .numbersAndPunctuation
        networkIdTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(networkIdTextField)

        joinButton = UIButton(type: .system)
        joinButton.setTitle(NSLocalizedString("JOIN_NETWORK", value: "Join Network", comment: "Join network button"), for: .normal)
        joinButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        joinButton.backgroundColor = .systemBlue
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.layer.cornerRadius = 8
        joinButton.translatesAutoresizingMaskIntoConstraints = false
        joinButton.addTarget(self, action: #selector(joinNetwork), for: .touchUpInside)
        view.addSubview(joinButton)

        leaveButton = UIButton(type: .system)
        leaveButton.setTitle(NSLocalizedString("LEAVE_NETWORK", value: "Leave Network", comment: "Leave network button"), for: .normal)
        leaveButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        leaveButton.backgroundColor = .systemRed
        leaveButton.setTitleColor(.white, for: .normal)
        leaveButton.layer.cornerRadius = 8
        leaveButton.translatesAutoresizingMaskIntoConstraints = false
        leaveButton.addTarget(self, action: #selector(leaveNetwork), for: .touchUpInside)
        leaveButton.isEnabled = false
        view.addSubview(leaveButton)

        let savedLabel = UILabel()
        savedLabel.text = NSLocalizedString("SAVED_NETWORKS", value: "Saved Networks", comment: "Saved networks label")
        savedLabel.font = .preferredFont(forTextStyle: .headline)
        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(savedLabel)

        networkListView = UITableView(frame: .zero, style: .plain)
        networkListView.translatesAutoresizingMaskIntoConstraints = false
        networkListView.dataSource = self
        networkListView.delegate = self
        networkListView.register(UITableViewCell.self, forCellReuseIdentifier: "NetworkCell")
        networkListView.isScrollEnabled = true
        view.addSubview(networkListView)

        NSLayoutConstraint.activate([
            statusImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            statusImageView.widthAnchor.constraint(equalToConstant: 50),
            statusImageView.heightAnchor.constraint(equalToConstant: 50),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: statusImageView.bottomAnchor, constant: 8),

            nodeIdLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nodeIdLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),

            statsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statsLabel.topAnchor.constraint(equalTo: nodeIdLabel.bottomAnchor, constant: 2),
            statsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),

            networkIdTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            networkIdTextField.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 12),
            networkIdTextField.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9),
            networkIdTextField.heightAnchor.constraint(equalToConstant: 40),

            joinButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            joinButton.topAnchor.constraint(equalTo: networkIdTextField.bottomAnchor, constant: 12),
            joinButton.heightAnchor.constraint(equalToConstant: 40),

            leaveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            leaveButton.topAnchor.constraint(equalTo: networkIdTextField.bottomAnchor, constant: 12),
            leaveButton.heightAnchor.constraint(equalToConstant: 40),

            joinButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -4),
            leaveButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 4),

            savedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            savedLabel.topAnchor.constraint(equalTo: joinButton.bottomAnchor, constant: 20),

            networkListView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            networkListView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            networkListView.topAnchor.constraint(equalTo: savedLabel.bottomAnchor, constant: 8),
            networkListView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func joinNetwork() {
        guard let networkId = networkIdTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !networkId.isEmpty else {
            showAlert(title: NSLocalizedString("ERROR", value: "Error", comment: "Error title"),
                      message: NSLocalizedString("ENTER_NETWORK_ID", value: "Please enter a Network ID", comment: "Enter network ID message"))
            return
        }
        joinButton.isEnabled = false
        statusLabel.text = NSLocalizedString("STATUS_CONNECTING", value: "Connecting...", comment: "Connecting status")
        statusLabel.textColor = .systemOrange

        ztBridge.joinNetwork(networkId) { [weak self] success in
            DispatchQueue.main.async {
                self?.joinButton.isEnabled = true
                if success {
                    self?.updateStatus()
                    self?.networkListView.reloadData()
                    self?.networkIdTextField.text = ""
                } else {
                    self?.statusLabel.text = NSLocalizedString("STATUS_FAILED", value: "Connection Failed", comment: "Failed status")
                    self?.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    @objc private func leaveNetwork() {
        ztBridge.leaveNetwork()
        leaveButton.isEnabled = false
        updateStatus()
        networkListView.reloadData()
    }

    private func updateStatus() {
        let online = ztBridge.isNodeOnline()
        if ztBridge.connected {
            statusLabel.text = NSLocalizedString("STATUS_CONNECTED", value: "Connected", comment: "Connected status")
            statusLabel.textColor = .systemGreen
            statusImageView.tintColor = .systemGreen
            leaveButton.isEnabled = true
        } else if online {
            statusLabel.text = NSLocalizedString("STATUS_ONLINE", value: "Online (Not Connected)", comment: "Online but not connected")
            statusLabel.textColor = .systemOrange
            statusImageView.tintColor = .systemOrange
            leaveButton.isEnabled = false
        } else {
            statusLabel.text = NSLocalizedString("STATUS_OFFLINE", value: "Offline", comment: "Offline status")
            statusLabel.textColor = .secondaryLabel
            statusImageView.tintColor = .systemGray
            leaveButton.isEnabled = false
        }
        nodeIdLabel.text = String(format: NSLocalizedString("NODE_ID_FORMAT", value: "Node: %@", comment: "Node ID format"), ztBridge.nodeId())
        statsLabel.text = ztBridge.nodeStatusInfo()
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", value: "OK", comment: "OK button"), style: .default))
        present(alert, animated: true)
    }
}

extension NetworkViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ztBridge.savedNetworks().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NetworkCell", for: indexPath)
        let networks = ztBridge.savedNetworks()
        if indexPath.row < networks.count {
            let nwid = networks[indexPath.row]
            cell.textLabel?.text = nwid
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            if nwid == ztBridge.currentNetworkId && ztBridge.connected {
                cell.accessoryType = .checkmark
                cell.detailTextLabel?.text = NSLocalizedString("STATUS_CONNECTED", value: "Connected", comment: "Connected status")
            } else {
                cell.accessoryType = .none
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let networks = ztBridge.savedNetworks()
        if indexPath.row < networks.count {
            networkIdTextField.text = networks[indexPath.row]
        }
    }
}

class IdentityViewController: UIViewController {

    private let ztBridge = ZeroTierBridge.sharedInstance()
    private var textView: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("IDENTITY_TITLE", value: "Identity", comment: "Identity page title")
        view.backgroundColor = .systemBackground

        let nodeId = ztBridge.nodeId()

        let headerLabel = UILabel()
        headerLabel.text = String(format: NSLocalizedString("YOUR_NODE_ID", value: "Your Node ID: %@", comment: "Node ID header"), nodeId)
        headerLabel.font = .preferredFont(forTextStyle: .title3)
        headerLabel.textAlignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        let copyIdButton = UIButton(type: .system)
        copyIdButton.setTitle(NSLocalizedString("COPY_NODE_ID", value: "Copy Node ID", comment: "Copy node ID button"), for: .normal)
        copyIdButton.translatesAutoresizingMaskIntoConstraints = false
        copyIdButton.addTarget(self, action: #selector(copyNodeId), for: .touchUpInside)
        view.addSubview(copyIdButton)

        let publicLabel = UILabel()
        publicLabel.text = NSLocalizedString("PUBLIC_IDENTITY", value: "Public Identity:", comment: "Public identity label")
        publicLabel.font = .preferredFont(forTextStyle: .headline)
        publicLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(publicLabel)

        textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.text = ztBridge.publicIdentityString()
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        let copyPubButton = UIButton(type: .system)
        copyPubButton.setTitle(NSLocalizedString("COPY_PUBLIC_ID", value: "Copy Public Identity", comment: "Copy public identity button"), for: .normal)
        copyPubButton.translatesAutoresizingMaskIntoConstraints = false
        copyPubButton.addTarget(self, action: #selector(copyPublicIdentity), for: .touchUpInside)
        view.addSubview(copyPubButton)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            copyIdButton.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            copyIdButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            publicLabel.topAnchor.constraint(equalTo: copyIdButton.bottomAnchor, constant: 20),
            publicLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            textView.topAnchor.constraint(equalTo: publicLabel.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(equalToConstant: 200),

            copyPubButton.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            copyPubButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func copyNodeId() {
        UIPasteboard.general.string = ztBridge.nodeId()
        showToast(NSLocalizedString("COPIED", value: "Copied!", comment: "Copied toast"))
    }

    @objc private func copyPublicIdentity() {
        UIPasteboard.general.string = ztBridge.publicIdentityString()
        showToast(NSLocalizedString("COPIED", value: "Copied!", comment: "Copied toast"))
    }

    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { alert.dismiss(animated: true) }
    }
}

class LogViewController: UIViewController {

    private let ztBridge = ZeroTierBridge.sharedInstance()
    private var tableView: UITableView!
    private var logEntries: [String] = []
    private var refreshTimer: Timer?
    private var autoScroll = true
    private var autoScrollButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("LOG_TITLE", value: "Log", comment: "Log page title")
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: NSLocalizedString("LOG_COPY", value: "Copy", comment: "Copy log"), style: .plain, target: self, action: #selector(copyLog)),
            UIBarButtonItem(title: NSLocalizedString("LOG_CLEAR", value: "Clear", comment: "Clear log"), style: .plain, target: self, action: #selector(clearLog))
        ]

        autoScrollButton = UIBarButtonItem(
            title: NSLocalizedString("LOG_AUTOSCROLL", value: "Auto", comment: "Auto scroll"),
            style: .plain,
            target: self,
            action: #selector(toggleAutoScroll)
        )
        autoScrollButton.tintColor = .systemBlue
        navigationItem.leftBarButtonItem = autoScrollButton

        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LogCell")
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        refreshLog()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshLog()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func refreshLog() {
        let newEntries = ztBridge.logEntries()
        if newEntries.count != logEntries.count {
            let oldCount = logEntries.count
            logEntries = newEntries
            tableView.reloadData()
            if autoScroll && logEntries.count > oldCount {
                let lastRow = logEntries.count - 1
                if lastRow >= 0 {
                    tableView.scrollToRow(at: IndexPath(row: lastRow, section: 0), at: .bottom, animated: false)
                }
            }
        }
    }

    @objc private func copyLog() {
        UIPasteboard.general.string = logEntries.joined(separator: "\n")
        let alert = UIAlertController(title: nil, message: NSLocalizedString("LOG_COPIED", value: "Log copied to clipboard", comment: "Log copied"), preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { alert.dismiss(animated: true) }
    }

    @objc private func clearLog() {
        logEntries = []
        tableView.reloadData()
    }

    @objc private func toggleAutoScroll() {
        autoScroll = !autoScroll
        autoScrollButton.tintColor = autoScroll ? .systemBlue : .systemGray
    }
}

extension LogViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return logEntries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LogCell", for: indexPath)
        let entry = logEntries[indexPath.row]

        cell.textLabel?.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.text = entry
        cell.selectionStyle = .none

        if entry.contains("FAIL") || entry.contains("FATAL") || entry.contains("ERROR") {
            cell.textLabel?.textColor = .systemRed
        } else if entry.contains("TX ") || entry.contains("EVENT: ONLINE") {
            cell.textLabel?.textColor = .systemGreen
        } else if entry.contains("RX") {
            cell.textLabel?.textColor = .systemBlue
        } else if entry.contains("EVENT: OFFLINE") {
            cell.textLabel?.textColor = .systemOrange
        } else {
            cell.textLabel?.textColor = .secondaryLabel
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

class SettingsViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("SETTINGS_TITLE", value: "Settings", comment: "Settings page title")
        view.backgroundColor = .systemBackground

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        let items: [(String, String)] = [
            (NSLocalizedString("SETTINGS_VERSION", value: "Version", comment: "Version label"), "1.16.1"),
            (NSLocalizedString("SETTINGS_CORE", value: "Core Engine", comment: "Core engine label"), "ZeroTier One"),
            (NSLocalizedString("SETTINGS_PLATFORM", value: "Platform", comment: "Platform label"), "iOS arm64"),
            (NSLocalizedString("SETTINGS_MIN_IOS", value: "Minimum iOS", comment: "Min iOS label"), "15.0"),
            (NSLocalizedString("SETTINGS_BUILD", value: "Build Type", comment: "Build type label"), NSLocalizedString("SETTINGS_UNSIGNED", value: "Unsigned", comment: "Unsigned build")),
            (NSLocalizedString("SETTINGS_LANG", value: "Language Support", comment: "Language label"), "English / \u{7b80}\u{4f53}\u{4e2d}\u{6587}")
        ]

        for (label, value) in items {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fill

            let lbl = UILabel()
            lbl.text = label
            lbl.font = .preferredFont(forTextStyle: .body)
            lbl.textColor = .secondaryLabel

            let val = UILabel()
            val.text = value
            val.font = .preferredFont(forTextStyle: .body)
            val.textAlignment = .right

            row.addArrangedSubview(lbl)
            row.addArrangedSubview(val)
            stackView.addArrangedSubview(row)
        }

        let disclaimer = UILabel()
        disclaimer.text = NSLocalizedString("SETTINGS_DISCLAIMER", value: "This is an unsigned build. Network connectivity requires proper signing with NetworkExtension entitlements. Node identity is generated locally using ZeroTier core cryptographic functions.", comment: "Disclaimer")
        disclaimer.font = .preferredFont(forTextStyle: .caption1)
        disclaimer.textColor = .tertiaryLabel
        disclaimer.numberOfLines = 0
        stackView.addArrangedSubview(disclaimer)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }
}
