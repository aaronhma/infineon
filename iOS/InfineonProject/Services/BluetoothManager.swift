//
//  BluetoothManager.swift
//  InfineonProject
//
//  Created by Aaron Ma on 3/4/26.
//

import CoreBluetooth
import Foundation

// MARK: - UUIDs (must match RPi bluetooth.py)

private let serviceUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-1234567890AB")
private let realtimeCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-123456780001")
private let settingsCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-123456780002")
private let buzzerCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-123456780003")
private let tripCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-123456780004")

// MARK: - Compact BLE payload models

struct BLERealtimeData: Codable {
  let spd: Int
  let hdg: Int
  let lat: Double
  let lng: Double
  let dir: String
  let ds: String
  let ph: Bool
  let dr: Bool
  let ix: Int
  let sp: Bool
  let sat: Int

  /// Convert compact BLE JSON to the app's existing VehicleRealtime model.
  func toVehicleRealtime(vehicleId: String) -> VehicleRealtime {
    VehicleRealtime(
      vehicleId: vehicleId,
      updatedAt: .now,
      latitude: lat,
      longitude: lng,
      speedMph: spd,
      speedLimitMph: 0,
      headingDegrees: hdg,
      compassDirection: dir,
      isSpeeding: sp,
      isMoving: spd > 0,
      driverStatus: ds,
      intoxicationScore: ix,
      satellites: sat,
      isPhoneDetected: ph,
      isDrinkingDetected: dr
    )
  }
}

struct BLESettingsData: Codable {
  var yolo: Bool
  var stream: Bool
  var shazam: Bool
  var mic: Bool
  var cam: Bool
  var dash: Bool

  /// Build from existing Vehicle toggle values.
  init(from vehicle: Vehicle) {
    yolo = vehicle.enableYolo
    stream = vehicle.enableStream
    shazam = vehicle.enableShazam
    mic = vehicle.enableMicrophone
    cam = vehicle.enableCamera
    dash = vehicle.enableDashcam
  }
}

struct BLETripData: Codable {
  let tid: String
  let dur: Int
  let mx_spd: Int
  let avg_spd: Double
  let spd_ev: Int
  let drw_ev: Int
  let ph_ev: Int
  let ix_max: Int
}

// MARK: - BluetoothManager

@Observable
final class BluetoothManager: NSObject {
  // Public state
  var bleEnabled = false {
    didSet {
      if bleEnabled {
        startScanning()
      } else {
        disconnect()
      }
    }
  }

  private(set) var isConnected = false
  private(set) var statusMessage = "Off"
  private(set) var latestRealtime: BLERealtimeData?
  private(set) var latestTrip: BLETripData?

  // CoreBluetooth
  private var centralManager: CBCentralManager?
  private var connectedPeripheral: CBPeripheral?
  private var settingsCharacteristic: CBCharacteristic?
  private var buzzerCharacteristic: CBCharacteristic?

  // Reconnect / timeout
  private var scanTimer: Timer?
  private var reconnectWorkItem: DispatchWorkItem?

  private static let scanTimeout: TimeInterval = 15
  private static let reconnectDelay: TimeInterval = 2

  override init() {
    super.init()
  }

  // MARK: - Public Write Methods

  func writeSettings(_ settings: BLESettingsData) {
    guard let char = settingsCharacteristic, let peripheral = connectedPeripheral else { return }
    guard let data = try? JSONEncoder().encode(settings) else { return }
    peripheral.writeValue(data, for: char, type: .withResponse)
  }

  func writeBuzzerCommand(active: Bool, type: String = "alert") {
    guard let char = buzzerCharacteristic, let peripheral = connectedPeripheral else { return }
    let payload: [String: Any] = ["active": active, "type": type]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
    peripheral.writeValue(data, for: char, type: .withResponse)
  }

  // MARK: - Scanning

  private func startScanning() {
    if centralManager == nil {
      centralManager = CBCentralManager(delegate: self, queue: .main)
      // Scanning starts in centralManagerDidUpdateState once powered on
    } else if centralManager?.state == .poweredOn {
      beginScan()
    }
  }

  private func beginScan() {
    guard let cm = centralManager, cm.state == .poweredOn else { return }
    statusMessage = "Scanning..."
    cm.scanForPeripherals(withServices: [serviceUUID], options: nil)

    // Scan timeout
    scanTimer?.invalidate()
    scanTimer = Timer.scheduledTimer(withTimeInterval: Self.scanTimeout, repeats: false) {
      [weak self] _ in
      guard let self, !self.isConnected else { return }
      self.centralManager?.stopScan()
      self.statusMessage = "Device not found"
    }
  }

  private func disconnect() {
    scanTimer?.invalidate()
    reconnectWorkItem?.cancel()
    if let peripheral = connectedPeripheral {
      centralManager?.cancelPeripheralConnection(peripheral)
    }
    centralManager?.stopScan()
    cleanup()
    statusMessage = "Off"
  }

  private func cleanup() {
    isConnected = false
    connectedPeripheral = nil
    settingsCharacteristic = nil
    buzzerCharacteristic = nil
    latestRealtime = nil
    latestTrip = nil
  }

  private func scheduleReconnect() {
    guard bleEnabled else { return }
    statusMessage = "Reconnecting..."
    reconnectWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.beginScan()
    }
    reconnectWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectDelay, execute: work)
  }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      if bleEnabled { beginScan() }
    case .poweredOff:
      statusMessage = "Bluetooth is off"
      cleanup()
    case .unauthorized:
      statusMessage = "Bluetooth not authorized"
    case .unsupported:
      statusMessage = "BLE not supported"
    default:
      break
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    central.stopScan()
    scanTimer?.invalidate()
    statusMessage = "Connecting..."
    connectedPeripheral = peripheral
    peripheral.delegate = self
    central.connect(peripheral, options: nil)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    isConnected = true
    statusMessage = "Connected"
    peripheral.discoverServices([serviceUUID])
  }

  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    cleanup()
    scheduleReconnect()
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    cleanup()
    scheduleReconnect()
  }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
      return
    }
    peripheral.discoverCharacteristics(
      [realtimeCharUUID, settingsCharUUID, buzzerCharUUID, tripCharUUID],
      for: service
    )
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard let chars = service.characteristics else { return }
    for char in chars {
      switch char.uuid {
      case realtimeCharUUID:
        peripheral.setNotifyValue(true, for: char)
        peripheral.readValue(for: char)
      case settingsCharUUID:
        settingsCharacteristic = char
      case buzzerCharUUID:
        buzzerCharacteristic = char
      case tripCharUUID:
        peripheral.setNotifyValue(true, for: char)
        peripheral.readValue(for: char)
      default:
        break
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard let data = characteristic.value else { return }
    let decoder = JSONDecoder()

    switch characteristic.uuid {
    case realtimeCharUUID:
      if let parsed = try? decoder.decode(BLERealtimeData.self, from: data) {
        latestRealtime = parsed
      }
    case tripCharUUID:
      if let parsed = try? decoder.decode(BLETripData.self, from: data) {
        latestTrip = parsed
      }
    default:
      break
    }
  }
}

// MARK: - Global singleton

let bluetooth = BluetoothManager()
