import Foundation
import HomeKit
import Observation

/// Represents a sensor reading value
struct SensorReading: Hashable {
    enum SensorType: String {
        case temperature = "Temperature"
        case humidity = "Humidity"
        case lightLevel = "Light Level"
        case airQuality = "Air Quality"
        case carbonDioxide = "CO₂"
        case battery = "Battery"
        case contact = "Contact"
        case motion = "Motion"
    }

    let type: SensorType
    let value: Double
    let unit: String

    var displayString: String {
        switch type {
        case .temperature:
            return String(format: "%.1f%@", value, unit)
        case .humidity:
            return String(format: "%.0f%%", value)
        case .lightLevel:
            return String(format: "%.0f lux", value)
        case .airQuality:
            let quality = value <= 1 ? "Good" : value <= 2 ? "Fair" : value <= 3 ? "Poor" : "Bad"
            return quality
        case .carbonDioxide:
            return String(format: "%.0f ppm", value)
        case .battery:
            return String(format: "%.0f%%", value)
        case .contact:
            return value == 0 ? "Closed" : "Open"
        case .motion:
            return value == 1 ? "Detected" : "Clear"
        }
    }

    var icon: String {
        switch type {
        case .temperature: return "thermometer.medium"
        case .humidity: return "humidity.fill"
        case .lightLevel: return "sun.max.fill"
        case .airQuality: return "aqi.medium"
        case .carbonDioxide: return "carbon.dioxide.cloud.fill"
        case .battery: return "battery.100"
        case .contact: return "door.left.hand.closed"
        case .motion: return "figure.walk.motion"
        }
    }
}

/// Represents a HomeKit accessory with its controllable state
struct HomeAccessory: Identifiable, Hashable {
    var id: UUID { uniqueIdentifier }
    let uniqueIdentifier: UUID
    let name: String
    let roomName: String?
    let type: AccessoryType
    var isOn: Bool
    var isReachable: Bool
    var customIcon: String?
    var sensorReadings: [SensorReading] = []
    var isSensor: Bool { !sensorReadings.isEmpty }

    enum AccessoryType: String, CaseIterable {
        case light = "Light"
        case switchOutlet = "Switch"
        case fan = "Fan"
        case thermostat = "Thermostat"
        case door = "Door"
        case window = "Window"
        case lock = "Lock"
        case alarm = "Alarm"
        case motion = "Motion"
        case smoke = "Smoke"
        case heat = "Heat"
        case tamper = "Tamper"
        case sensor = "Sensor"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .light: return "lightbulb.fill"
            case .switchOutlet: return "powerplug.fill"
            case .fan: return "fan.fill"
            case .thermostat: return "thermometer.medium"
            case .door: return "door.left.hand.closed"
            case .window: return "window.vertical.closed"
            case .lock: return "lock.fill"
            case .alarm: return "bell.badge.fill"
            case .motion: return "figure.walk.motion"
            case .smoke: return "smoke.fill"
            case .heat: return "flame.fill"
            case .tamper: return "exclamationmark.shield.fill"
            case .sensor: return "sensor.fill"
            case .unknown: return "questionmark.circle"
            }
        }

        static var availableIcons: [(icon: String, label: String)] {
            [
                ("lightbulb.fill", "Light"),
                ("powerplug.fill", "Switch/Outlet"),
                ("fan.fill", "Fan"),
                ("thermometer.medium", "Thermostat"),
                ("door.left.hand.closed", "Door"),
                ("window.vertical.closed", "Window"),
                ("lock.fill", "Lock"),
                ("bell.badge.fill", "Alarm"),
                ("figure.walk.motion", "Motion"),
                ("smoke.fill", "Smoke"),
                ("flame.fill", "Heat"),
                ("exclamationmark.shield.fill", "Tamper"),
                ("sensor.fill", "Sensor"),
                ("camera.fill", "Camera"),
                ("speaker.wave.2.fill", "Speaker"),
                ("tv.fill", "TV"),
                ("blinds.vertical.closed", "Blinds"),
                ("garage.closed", "Garage"),
                ("spigot.fill", "Sprinkler"),
                ("bolt.fill", "Power"),
            ]
        }
    }

    var effectiveIcon: String {
        customIcon ?? type.icon
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uniqueIdentifier)
    }

    static func == (lhs: HomeAccessory, rhs: HomeAccessory) -> Bool {
        lhs.uniqueIdentifier == rhs.uniqueIdentifier
    }
}

/// Manages HomeKit home and accessories discovery
@Observable
final class HomeKitManager: NSObject {
    private let homeManager = HMHomeManager()
    private var togglingAccessories: Set<UUID> = []

    var accessories: [HomeAccessory] = []
    var isAuthorized = false
    var authorizationStatus: String = "Checking..."
    var homes: [HMHome] = []
    var selectedHomeIndex: Int = 0 {
        didSet {
            if selectedHomeIndex != oldValue {
                refreshAccessories()
            }
        }
    }

    var currentHome: HMHome? {
        guard !homes.isEmpty, selectedHomeIndex < homes.count else { return nil }
        return homes[selectedHomeIndex]
    }

    override init() {
        super.init()
        homeManager.delegate = self
        authorizationStatus = "Connecting to HomeKit..."

        // Retry checking for HomeKit access over several seconds
        // The delegate should fire, but this is a backup
        Task { @MainActor in
            for attempt in 1...10 {
                try? await Task.sleep(for: .seconds(1))

                // If already authorized by delegate, stop checking
                if self.isAuthorized {
                    return
                }

                // Check if we now have access
                let status = self.homeManager.authorizationStatus
                if status.contains(.determined) && !self.homeManager.homes.isEmpty {
                    self.homes = self.homeManager.homes
                    self.isAuthorized = true
                    self.authorizationStatus = "Connected to \(self.homes.first?.name ?? "Home")"
                    self.refreshAccessories()
                    return
                }

                // Update status message
                if status.contains(.restricted) {
                    self.authorizationStatus = "HomeKit access restricted"
                    return
                } else if !status.contains(.determined) {
                    self.authorizationStatus = "Connecting to HomeKit... (\(attempt)/10)"
                } else {
                    self.authorizationStatus = "Waiting for homes... (\(attempt)/10)"
                }
            }

            // After all retries, if still not authorized
            if !self.isAuthorized {
                let status = self.homeManager.authorizationStatus
                if !status.contains(.determined) {
                    self.authorizationStatus = "HomeKit permission not granted"
                } else {
                    self.authorizationStatus = "No HomeKit homes found"
                }
            }
        }
    }

    deinit {
        homeManager.delegate = nil
        clearAccessoryDelegates()
    }

    private func clearAccessoryDelegates() {
        guard let home = currentHome else { return }
        for accessory in home.accessories {
            accessory.delegate = nil
        }
    }

    private func setupAccessoryDelegates() {
        guard let home = currentHome else { return }
        for accessory in home.accessories {
            accessory.delegate = self
        }
    }

    /// Refreshes the list of accessories from HomeKit
    func refreshAccessories() {
        clearAccessoryDelegates()

        guard let home = currentHome else {
            accessories = []
            return
        }

        // First, request fresh reads for all power state characteristics
        for accessory in home.accessories where accessory.isReachable {
            for service in accessory.services {
                for characteristic in service.characteristics {
                    // Read power state and sensor characteristics
                    if characteristic.characteristicType == HMCharacteristicTypePowerState ||
                       characteristic.characteristicType == HMCharacteristicTypeCurrentTemperature ||
                       characteristic.characteristicType == HMCharacteristicTypeCurrentRelativeHumidity ||
                       characteristic.characteristicType == HMCharacteristicTypeMotionDetected ||
                       characteristic.characteristicType == HMCharacteristicTypeContactState {
                        characteristic.readValue { _ in }
                    }
                }
            }
        }

        // Build accessories list (values will update via delegate callbacks)
        var newAccessories: [HomeAccessory] = []

        for accessory in home.accessories {
            guard accessory.isReachable else { continue }

            let type = determineAccessoryType(accessory)
            let isOn = getAccessoryState(accessory)
            let roomName = accessory.room?.name
            let sensorReadings = getSensorReadings(accessory)

            let homeAccessory = HomeAccessory(
                uniqueIdentifier: accessory.uniqueIdentifier,
                name: accessory.name,
                roomName: roomName,
                type: type,
                isOn: isOn,
                isReachable: accessory.isReachable,
                sensorReadings: sensorReadings
            )
            newAccessories.append(homeAccessory)
        }

        accessories = newAccessories.sorted { $0.name < $1.name }
        setupAccessoryDelegates()

        // Schedule a delayed refresh to pick up the read values
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.updateAccessoryStates()
        }
    }

    /// Updates accessory states from current HomeKit values
    private func updateAccessoryStates() {
        guard let home = currentHome else { return }

        var anyChanged = false
        for (index, accessory) in accessories.enumerated() {
            if let hmAccessory = home.accessories.first(where: { $0.uniqueIdentifier == accessory.uniqueIdentifier }) {
                let newIsOn = getAccessoryState(hmAccessory)
                let newSensorReadings = getSensorReadings(hmAccessory)
                if accessories[index].isOn != newIsOn || accessories[index].sensorReadings != newSensorReadings {
                    accessories[index].isOn = newIsOn
                    accessories[index].sensorReadings = newSensorReadings
                    anyChanged = true
                }
            }
        }

        // Notify observers if any state changed
        if anyChanged {
            NotificationCenter.default.post(name: .homeKitAccessoriesDidUpdate, object: nil)
        }
    }

    /// Toggles an accessory on/off
    @MainActor
    func toggleAccessory(_ accessory: HomeAccessory) async {
        // Prevent concurrent toggles on the same accessory
        guard !togglingAccessories.contains(accessory.uniqueIdentifier) else { return }
        togglingAccessories.insert(accessory.uniqueIdentifier)
        defer { togglingAccessories.remove(accessory.uniqueIdentifier) }

        guard let home = currentHome,
              let hmAccessory = home.accessories.first(where: { $0.uniqueIdentifier == accessory.uniqueIdentifier }) else {
            return
        }

        for service in hmAccessory.services {
            for characteristic in service.characteristics where characteristic.characteristicType == HMCharacteristicTypePowerState {
                // Read current value from HomeKit to avoid stale state
                let currentValue = (characteristic.value as? Bool) ?? false
                let newValue = !currentValue

                do {
                    try await characteristic.writeValue(newValue)
                    if let index = accessories.firstIndex(where: { $0.uniqueIdentifier == accessory.uniqueIdentifier }) {
                        accessories[index].isOn = newValue
                    }
                } catch {
                    print("Failed to toggle accessory: \(error)")
                    // On failure, refresh to get the true state
                    refreshAccessories()
                }
                return
            }
        }
    }

    /// Determines the type of accessory based on its services and name
    private func determineAccessoryType(_ accessory: HMAccessory) -> HomeAccessory.AccessoryType {
        // First check HomeKit service types
        for service in accessory.services {
            switch service.serviceType {
            case HMServiceTypeLightbulb:
                return .light
            case HMServiceTypeSwitch, HMServiceTypeOutlet:
                return .switchOutlet
            case HMServiceTypeFan:
                return .fan
            case HMServiceTypeThermostat:
                return .thermostat
            case HMServiceTypeDoor, HMServiceTypeGarageDoorOpener:
                return .door
            case HMServiceTypeWindow, HMServiceTypeWindowCovering:
                return .window
            case HMServiceTypeLockMechanism, HMServiceTypeLockManagement:
                return .lock
            case HMServiceTypeSecuritySystem:
                return .alarm
            case HMServiceTypeMotionSensor, HMServiceTypeOccupancySensor:
                return .motion
            case HMServiceTypeSmokeSensor:
                return .smoke
            case HMServiceTypeContactSensor, HMServiceTypeLeakSensor,
                 HMServiceTypeHumiditySensor, HMServiceTypeLightSensor,
                 HMServiceTypeAirQualitySensor, HMServiceTypeCarbonDioxideSensor,
                 HMServiceTypeCarbonMonoxideSensor:
                return .sensor
            default:
                continue
            }
        }

        // Smart guessing based on name
        let nameLower = accessory.name.lowercased()

        if nameLower.contains("door") || nameLower.contains("garage") {
            return .door
        }
        if nameLower.contains("window") {
            return .window
        }
        if nameLower.contains("lock") {
            return .lock
        }
        if nameLower.contains("alarm") || nameLower.contains("siren") || nameLower.contains("arm") || nameLower.contains("disarm") {
            return .alarm
        }
        if nameLower.contains("motion") || nameLower.contains("occupancy") {
            return .motion
        }
        if nameLower.contains("smoke") {
            return .smoke
        }
        if nameLower.contains("heat") || nameLower.contains("temperature") {
            return .heat
        }
        if nameLower.contains("tamper") {
            return .tamper
        }
        if nameLower.contains("sensor") {
            return .sensor
        }
        if nameLower.contains("light") || nameLower.contains("lamp") || nameLower.contains("bulb") {
            return .light
        }
        if nameLower.contains("fan") {
            return .fan
        }
        // Rooms typically have switches (bedroom, bathroom, kitchen, etc.)
        if nameLower.contains("bedroom") || nameLower.contains("bathroom") ||
           nameLower.contains("kitchen") || nameLower.contains("living") ||
           nameLower.contains("dining") || nameLower.contains("office") {
            return .switchOutlet
        }
        if nameLower.contains("switch") || nameLower.contains("outlet") || nameLower.contains("plug") {
            return .switchOutlet
        }

        return .unknown
    }

    /// Gets the current on/off state of an accessory
    private func getAccessoryState(_ accessory: HMAccessory) -> Bool {
        for service in accessory.services {
            for characteristic in service.characteristics where characteristic.characteristicType == HMCharacteristicTypePowerState {
                return (characteristic.value as? Bool) ?? false
            }
        }
        return false
    }

    /// Gets sensor readings from an accessory
    private func getSensorReadings(_ accessory: HMAccessory) -> [SensorReading] {
        var readings: [SensorReading] = []

        for service in accessory.services {
            for characteristic in service.characteristics {
                switch characteristic.characteristicType {
                case HMCharacteristicTypeCurrentTemperature:
                    if let value = characteristic.value as? Double {
                        // HomeKit uses Celsius, convert based on locale
                        let useFahrenheit = Locale.current.measurementSystem == .us
                        let displayValue = useFahrenheit ? value * 9/5 + 32 : value
                        let unit = useFahrenheit ? "°F" : "°C"
                        readings.append(SensorReading(type: .temperature, value: displayValue, unit: unit))
                    }

                case HMCharacteristicTypeCurrentRelativeHumidity:
                    if let value = characteristic.value as? Double {
                        readings.append(SensorReading(type: .humidity, value: value, unit: "%"))
                    }

                case HMCharacteristicTypeCurrentLightLevel:
                    if let value = characteristic.value as? Double {
                        readings.append(SensorReading(type: .lightLevel, value: value, unit: "lux"))
                    }

                case HMCharacteristicTypeAirQuality:
                    if let value = characteristic.value as? Int {
                        readings.append(SensorReading(type: .airQuality, value: Double(value), unit: ""))
                    }

                case HMCharacteristicTypeCarbonDioxideLevel:
                    if let value = characteristic.value as? Double {
                        readings.append(SensorReading(type: .carbonDioxide, value: value, unit: "ppm"))
                    }

                case HMCharacteristicTypeBatteryLevel:
                    if let value = characteristic.value as? Int {
                        readings.append(SensorReading(type: .battery, value: Double(value), unit: "%"))
                    }

                case HMCharacteristicTypeContactState:
                    if let value = characteristic.value as? Int {
                        readings.append(SensorReading(type: .contact, value: Double(value), unit: ""))
                    }

                case HMCharacteristicTypeMotionDetected:
                    if let value = characteristic.value as? Bool {
                        readings.append(SensorReading(type: .motion, value: value ? 1 : 0, unit: ""))
                    }

                default:
                    continue
                }
            }
        }

        return readings
    }
}

// MARK: - HMHomeManagerDelegate
extension HomeKitManager: HMHomeManagerDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            homes = manager.homes

            // Validate selectedHomeIndex bounds
            if selectedHomeIndex >= homes.count {
                selectedHomeIndex = 0
            }

            let status = manager.authorizationStatus

            if status.contains(.restricted) {
                isAuthorized = false
                authorizationStatus = "HomeKit access restricted"
            } else if !status.contains(.determined) {
                isAuthorized = false
                authorizationStatus = "HomeKit access not authorized"
            } else if manager.homes.isEmpty {
                // HomeKit may return empty initially while syncing - wait and retry
                authorizationStatus = "Connecting to HomeKit..."

                // Retry a few times before giving up
                for attempt in 1...5 {
                    try? await Task.sleep(for: .seconds(1))

                    // Check if homes were populated by another callback
                    if !self.homes.isEmpty {
                        self.isAuthorized = true
                        self.authorizationStatus = "Connected to \(self.homes.first?.name ?? "Home")"
                        self.refreshAccessories()
                        return
                    }

                    // Re-check the manager directly
                    if !manager.homes.isEmpty {
                        self.homes = manager.homes
                        self.isAuthorized = true
                        self.authorizationStatus = "Connected to \(manager.homes.first?.name ?? "Home")"
                        self.refreshAccessories()
                        return
                    }

                    self.authorizationStatus = "Connecting to HomeKit... (\(attempt)/5)"
                }

                // After retries, still no homes
                isAuthorized = false
                authorizationStatus = "No HomeKit homes found. Set up a home in the Home app."
            } else {
                isAuthorized = true
                authorizationStatus = "Connected to \(manager.homes.first?.name ?? "Home")"
                refreshAccessories()
            }
        }
    }

    func homeManagerDidUpdatePrimaryHome(_ manager: HMHomeManager) {
        Task { @MainActor in
            refreshAccessories()
        }
    }
}

// MARK: - HMAccessoryDelegate
extension HomeKitManager: HMAccessoryDelegate {
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        Task { @MainActor in
            guard let index = accessories.firstIndex(where: { $0.uniqueIdentifier == accessory.uniqueIdentifier }) else { return }

            switch characteristic.characteristicType {
            case HMCharacteristicTypePowerState:
                accessories[index].isOn = (characteristic.value as? Bool) ?? false
                NotificationCenter.default.post(name: .homeKitAccessoriesDidUpdate, object: nil)

            case HMCharacteristicTypeCurrentTemperature,
                 HMCharacteristicTypeCurrentRelativeHumidity,
                 HMCharacteristicTypeCurrentLightLevel,
                 HMCharacteristicTypeAirQuality,
                 HMCharacteristicTypeCarbonDioxideLevel,
                 HMCharacteristicTypeBatteryLevel,
                 HMCharacteristicTypeContactState,
                 HMCharacteristicTypeMotionDetected:
                // Update sensor readings
                accessories[index].sensorReadings = getSensorReadings(accessory)
                NotificationCenter.default.post(name: .homeKitAccessoriesDidUpdate, object: nil)

            default:
                break
            }
        }
    }

    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        Task { @MainActor in
            refreshAccessories()
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let homeKitAccessoriesDidUpdate = Notification.Name("homeKitAccessoriesDidUpdate")
}
