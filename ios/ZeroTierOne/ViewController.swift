import UIKit

class ViewController: UIViewController {

    private var statusLabel: UILabel!
    private var nodeIdLabel: UILabel!
    private var networkIdTextField: UITextField!
    private var joinButton: UIButton!
    private var leaveButton: UIButton!
    private var statusImageView: UIImageView!

    private let ztBridge = ZeroTierBridge()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateStatus()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = NSLocalizedString("APP_TITLE", value: "ZeroTier One", comment: "App title")

        statusImageView = UIImageView()
        statusImageView.contentMode = .scaleAspectFit
        statusImageView.translatesAutoresizingMaskIntoConstraints = false
        statusImageView.tintColor = .systemGray
        let config = UIImage.SymbolConfiguration(pointSize: 60, weight: .regular)
        statusImageView.image = UIImage(systemName: "network", withConfiguration: config)
        view.addSubview(statusImageView)

        statusLabel = UILabel()
        statusLabel.font = .preferredFont(forTextStyle: .title2)
        statusLabel.textAlignment = .center
        statusLabel.text = NSLocalizedString("STATUS_OFFLINE", value: "Offline", comment: "Offline status")
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        nodeIdLabel = UILabel()
        nodeIdLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        nodeIdLabel.textAlignment = .center
        nodeIdLabel.text = String(format: NSLocalizedString("NODE_ID_FORMAT", value: "Node: %@", comment: "Node ID format"), ztBridge.nodeId)
        nodeIdLabel.textColor = .secondaryLabel
        nodeIdLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nodeIdLabel)

        networkIdTextField = UITextField()
        networkIdTextField.placeholder = NSLocalizedString("NETWORK_ID_PLACEHOLDER", value: "Enter Network ID", comment: "Network ID placeholder")
        networkIdTextField.borderStyle = .roundedRect
        networkIdTextField.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        networkIdTextField.keyboardType = .numberPad
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

        NSLayoutConstraint.activate([
            statusImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            statusImageView.widthAnchor.constraint(equalToConstant: 80),
            statusImageView.heightAnchor.constraint(equalToConstant: 80),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: statusImageView.bottomAnchor, constant: 16),

            nodeIdLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nodeIdLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),

            networkIdTextField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            networkIdTextField.topAnchor.constraint(equalTo: nodeIdLabel.bottomAnchor, constant: 40),
            networkIdTextField.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            networkIdTextField.heightAnchor.constraint(equalToConstant: 44),

            joinButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            joinButton.topAnchor.constraint(equalTo: networkIdTextField.bottomAnchor, constant: 20),
            joinButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            joinButton.heightAnchor.constraint(equalToConstant: 44),

            leaveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            leaveButton.topAnchor.constraint(equalTo: joinButton.bottomAnchor, constant: 12),
            leaveButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            leaveButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func joinNetwork() {
        guard let networkId = networkIdTextField.text, !networkId.isEmpty else {
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
                } else {
                    self?.statusLabel.text = NSLocalizedString("STATUS_FAILED", value: "Connection Failed", comment: "Failed status")
                    self?.statusLabel.textColor = .systemRed
                    self?.statusImageView.tintColor = .systemRed
                }
            }
        }
    }

    @objc private func leaveNetwork() {
        ztBridge.leaveNetwork()
        leaveButton.isEnabled = false
        updateStatus()
    }

    private func updateStatus() {
        if ztBridge.connected {
            statusLabel.text = NSLocalizedString("STATUS_CONNECTED", value: "Connected", comment: "Connected status")
            statusLabel.textColor = .systemGreen
            statusImageView.tintColor = .systemGreen
            leaveButton.isEnabled = true
        } else {
            statusLabel.text = NSLocalizedString("STATUS_OFFLINE", value: "Offline", comment: "Offline status")
            statusLabel.textColor = .secondaryLabel
            statusImageView.tintColor = .systemGray
            leaveButton.isEnabled = false
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", value: "OK", comment: "OK button"), style: .default))
        present(alert, animated: true)
    }
}
