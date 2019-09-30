//
//  HomeTableViewController.swift
//  BasicExample
//
//  Created by Paul Calnan on 11/26/18.
//  Copyright © 2018 Bose Corporation. All rights reserved.
//

import UIKit
import BoseWearable
import BLECore
import AVFoundation

class HomeViewController: UITableViewController {

    private var activityIndicator: ActivityIndicator?

    @IBOutlet var connectToLast: UISwitch!

    @IBOutlet var versionLabel: UILabel!

    private var reconnectTask: ConnectionTask<ReconnectUI>?

    private static let sensorSamplePeriod = SamplePeriod._20ms
    
    fileprivate static var sensorIntent = SensorIntent(sensors: [.rotation], samplePeriods: [HomeViewController.sensorSamplePeriod])
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAudioSessionRouteChange(_:)),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: AVAudioSession.sharedInstance())
        
        versionLabel.text = "BoseWearable \(BoseWearable.formattedVersion)"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        reconnect()
    }
    
    private func reconnect() {
        guard let device = MostRecentlyConnectedDevice.get() else {
            print("[Bose] No recent connected device")
            return
        }
        
        if let reconnectTask = reconnectTask {
            reconnectTask.cancel()
        }
        
        print("[Bose] Sending reconnection request...")
        
        reconnectTask = ReconnectUI.connectionTask(device: device) { result in
            switch result {
            case .success(let session):
                print("[Bose] Reconnection success")
                self.showDeviceInfo(for: session)
            case .failure(let error):
                print("[Bose] Reconnection failed with error: \(error.localizedDescription)")
                self.show(error)
            case .cancelled:
                print("[Bose] Reconnection cancelled")
            }
            
            self.reconnectTask = nil
        }
        
        reconnectTask?.start()
        
        versionLabel.text = "Reconnection request sent..."
        versionLabel.textColor = UIColor.orange
    }
    
    @IBAction func connectTapped(_ sender: Any) {
        // Perform the device search and connect to the selected device. This
        // may present a view controller on a new UIWindow.
        BoseWearable.shared.startConnection(mode: .alwaysShow, sensorIntent: HomeViewController.sensorIntent) { result in
            switch result {
            case .success(let session):
                // A device was selected, a session was created and opened. Show
                // a view controller that will become the session delegate.
                self.showDeviceInfo(for: session)

            case .failure(let error):
                // An error occurred when searching for or connecting to a
                // device. Present an alert showing the error.
                self.show(error)

            case .cancelled:
                // The user cancelled the search operation.
                break
            }

            // An error occurred when performing the search or creating the
            // session. Present an alert showing the error.
            self.activityIndicator?.removeFromSuperview()
        }
    }

    @IBAction func useSimulatedDeviceTapped(_ sender: Any) {
        // Instead of using a session for a remote device, create a session for a
        // simulated device.
        showDeviceInfo(for: BoseWearable.shared.createSimulatedWearableDeviceSession())
    }

    private func showDeviceInfo(for session: WearableDeviceSession) {
        guard let vc = storyboard?.instantiateViewController(withIdentifier: "HeadingTableViewController") as? HeadingTableViewController else {
            fatalError("Cannot instantiate view controller")
        }

        vc.session = session
        self.navigationController?.pushViewController(vc, animated: true)
    }
}

extension HomeViewController {
    @objc func handleAudioSessionRouteChange(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
        }
        
        print("[AVAudioSession] Route change occurred with reason: \(reason)")
        
        if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
            let previousOutput = previousRoute.outputs.first {
            print("[AVAudioSession] Audio session previous route output: \(previousOutput.portName) (\(previousOutput.portType.rawValue))")
        }
        
        if let currentOutput = AVAudioSession.sharedInstance().currentRoute.outputs.first {
            print("[AVAudioSession] Audio session current route output: \(currentOutput.portName) (\(currentOutput.portType.rawValue))")
        }
    }
}

// MARK: - Bose Reconnection UI

private class ReconnectUI {
    static func connectionTask(device: MostRecentlyConnectedDevice, completion: @escaping (CancellableResult<WearableDeviceSession>) -> Void) -> ConnectionTask<ReconnectUI> {
        return ConnectionTask(
            mode: .reconnect(device: device),
            bluetoothManager: BoseWearable.shared.bluetoothManager,
            removeTimeout: 15,
            sensorIntent: HomeViewController.sensorIntent,
            gestureIntent: GestureIntent(gestures: []),
            userInterface: ReconnectUI(),
            completionHandler: completion
        )
    }
}

extension ReconnectUI: ConnectUI {
    typealias SearchUIImpl = AppSearchUI
    typealias AlertUIImpl = AppAlertUI
    typealias InfoUIImpl = AppInfoUI
    
    func start() {
    }
    
    func push(_ element: ConnectUIElement) {
    }
    
    func pop() {
    }
    
    func restart() {
    }
    
    func open(url: URL) {
    }
    
    func finish() {
    }
}

private final class AppSearchUI: SearchUI {
    weak var searchDelegate: SearchUIDelegate?
    private(set) var selectedDevice: DiscoveredDevice?
    
    private func addOrUpdate(device: DiscoveredDevice, state: DeviceState) {
        guard selectedDevice == nil else { return }
        switch state {
        case .found(let strength):
            switch strength {
            case .full, .strong:
                print("[Bose] Selecting device \(device.name ?? "unknown") with signal strength \(strength)")
                selectedDevice = device
                
            case .moderate, .weak:
                print("[Bose] Ignoring device \(device.name ?? "unknown") with signal strength \(strength)")
            }
        default:
            print("[Bose] Ignoring device \(device.name ?? "unknown") with state \(state)")
        }
    }
    
    static func create() -> AppSearchUI {
        return AppSearchUI()
    }
    
    func add(device: DiscoveredDevice, state: DeviceState) {
        addOrUpdate(device: device, state: state)
    }
    
    func update(device: DiscoveredDevice, state: DeviceState) {
        addOrUpdate(device: device, state: state)
    }
    
    func remove(device: DiscoveredDevice) {
    }
    
    func removeAllDevices() {
    }
}

private final class AppAlertUI: AlertUI {
    static func create(icon: AlertIcon, title: String?, message: String?, actions: [AlertAction]) -> AppAlertUI {
        return AppAlertUI()
    }
}

private final class AppInfoUI: InfoUI {
    weak var infoDelegate: InfoUIDelegate?
    
    static func create(title: String, message: String?, type: InfoType, cancellable: Bool) -> AppInfoUI {
        return AppInfoUI()
    }
}

extension AVAudioSession.RouteChangeReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "new device available"
        case .oldDeviceUnavailable: return "old device unavailable"
        case .categoryChange: return "category Change"
        case .override: return "override"
        case .wakeFromSleep: return "wake from sleep"
        case .noSuitableRouteForCategory: return "no suitable route for category"
        case .routeConfigurationChange: return "route configuration change"
        @unknown default: return "unknown - (WARNING) new enum value added"
        }
    }
}
