import FlutterMacOS
import Foundation
import Security

final class HostPairingStoreChannel {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(
    label: "io.github.guog962464.aggregate.host-pairing-store",
    qos: .userInitiated
  )
  private let service = "io.github.guog962464.aggregate.host.pairings.v1"
  private let account = "paired-devices"

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "aggregate/host_pairing",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      self.queue.async {
        do {
          switch call.method {
          case "loadAll":
            let registry = try self.loadAll()
            DispatchQueue.main.async { result(registry) }
          case "save":
            guard let arguments = call.arguments as? [String: Any],
                  let deviceId = arguments["deviceId"] as? String,
                  let record = arguments["record"] as? String
            else {
              DispatchQueue.main.async {
                result(FlutterError(code: "invalid_args", message: "Pairing record is invalid", details: nil))
              }
              return
            }
            try self.save(deviceId: deviceId, record: record)
            DispatchQueue.main.async { result(nil) }
          case "remove":
            guard let arguments = call.arguments as? [String: Any],
                  let deviceId = arguments["deviceId"] as? String
            else {
              DispatchQueue.main.async {
                result(FlutterError(code: "invalid_args", message: "Pairing device is invalid", details: nil))
              }
              return
            }
            try self.remove(deviceId: deviceId)
            DispatchQueue.main.async { result(nil) }
          default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "pairing_store_failure", message: "Pairing store operation failed", details: nil))
          }
        }
      }
    }
  }

  private func loadAll() throws -> String? {
    guard let data = try readRegistryData() else { return nil }
    guard data.count <= Self.maxRegistryBytes,
          let encoded = String(data: data, encoding: .utf8),
          try Self.isValidRegistry(encoded)
    else {
      throw HostPairingStoreFailure.corruptRegistry
    }
    return encoded
  }

  private func save(deviceId: String, record: String) throws {
    guard Self.isDeviceId(deviceId),
          record.utf8.count <= Self.maxRecordBytes,
          try Self.recordMatchesDevice(record, deviceId: deviceId)
    else {
      throw HostPairingStoreFailure.corruptRegistry
    }
    var registry = try readRegistry()
    registry[deviceId] = record
    try writeRegistry(registry)
  }

  private func remove(deviceId: String) throws {
    guard Self.isDeviceId(deviceId) else { throw HostPairingStoreFailure.corruptRegistry }
    var registry = try readRegistry()
    registry.removeValue(forKey: deviceId)
    try writeRegistry(registry)
  }

  private func readRegistry() throws -> [String: String] {
    guard let data = try readRegistryData() else { return [:] }
    guard data.count <= Self.maxRegistryBytes,
          let encoded = String(data: data, encoding: .utf8),
          try Self.isValidRegistry(encoded),
          let value = try JSONSerialization.jsonObject(with: data) as? [String: String]
    else {
      throw HostPairingStoreFailure.corruptRegistry
    }
    return value
  }

  private func readRegistryData() throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw HostPairingStoreFailure.keychain
    }
    return data
  }

  private func writeRegistry(_ registry: [String: String]) throws {
    guard registry.count <= Self.maxPairedDevices else {
      throw HostPairingStoreFailure.resourceLimit
    }
    if registry.isEmpty {
      let status = SecItemDelete(secretQuery() as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw HostPairingStoreFailure.keychain
      }
      return
    }
    for (deviceId, record) in registry {
      guard Self.isDeviceId(deviceId),
            record.utf8.count <= Self.maxRecordBytes,
            try Self.recordMatchesDevice(record, deviceId: deviceId)
      else {
        throw HostPairingStoreFailure.corruptRegistry
      }
    }
    let data = try JSONSerialization.data(withJSONObject: registry, options: [.sortedKeys])
    guard data.count <= Self.maxRegistryBytes else {
      throw HostPairingStoreFailure.resourceLimit
    }
    let updateStatus = SecItemUpdate(
      secretQuery() as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecItemNotFound {
      var add = secretQuery()
      add[kSecValueData as String] = data
      guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
        throw HostPairingStoreFailure.keychain
      }
    } else if updateStatus != errSecSuccess {
      throw HostPairingStoreFailure.keychain
    }
  }

  private func secretQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private static func isValidRegistry(_ json: String) throws -> Bool {
    guard let data = json.data(using: .utf8),
          let registry = try JSONSerialization.jsonObject(with: data) as? [String: String],
          registry.count <= maxPairedDevices
    else {
      return false
    }
    for (deviceId, record) in registry {
      guard isDeviceId(deviceId),
            record.utf8.count <= maxRecordBytes,
            try recordMatchesDevice(record, deviceId: deviceId)
      else {
        return false
      }
    }
    return true
  }

  private static func recordMatchesDevice(_ json: String, deviceId: String) throws -> Bool {
    guard let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw HostPairingStoreFailure.corruptRegistry
    }
    return object["deviceId"] as? String == deviceId
  }

  private static func isDeviceId(_ value: String) -> Bool {
    value.range(of: #"^device-[a-f0-9]{32}$"#, options: .regularExpression) != nil
  }

  private static let maxPairedDevices = 128
  private static let maxRegistryBytes = 1024 * 1024
  private static let maxRecordBytes = 16 * 1024
}

private enum HostPairingStoreFailure: Error {
  case keychain
  case corruptRegistry
  case resourceLimit
}
