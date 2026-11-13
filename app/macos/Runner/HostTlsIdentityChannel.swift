import Foundation
import FlutterMacOS
import CryptoKit
import Security

final class HostTlsIdentityChannel {
  private let channel: FlutterMethodChannel
  private let identity = MacHostTlsIdentity()
  private let identityQueue = DispatchQueue(
    label: "io.github.guog962464.aggregate.host-identity",
    qos: .userInitiated
  )

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "aggregate/host_identity",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard call.method == "loadOrCreate" || call.method == "rotate" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.identityQueue.async {
        do {
          let material = try call.method == "rotate"
            ? self.identity.rotate()
            : self.identity.loadOrCreate()
          DispatchQueue.main.async { result(material) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "identity_failure",
              message: "Host identity operation failed",
              details: nil
            ))
          }
        }
      }
    }
  }
}

private final class MacHostTlsIdentity {
  private let service = "io.github.guog962464.aggregate.host.tls.v1"
  private let privateKeyTag = Data("io.github.guog962464.aggregate.host.tls.p256.v1".utf8)

  func loadOrCreate() throws -> [String: String] {
    let privateKey = try loadPrivateKey()
    let hostIdData = try readSecret(account: "host-id")
    let certificateData = try readSecret(account: "certificate-der")
    if privateKey == nil && hostIdData == nil && certificateData == nil {
      return try createIdentity()
    }
    guard let privateKey,
          let hostIdData,
          let certificateData,
          let hostId = String(data: hostIdData, encoding: .utf8),
          hostId.range(of: #"^host-[a-f0-9]{32}$"#, options: .regularExpression) != nil
    else {
      throw HostIdentityFailure.invalidStoredIdentity
    }
    try validateCertificate(certificateData, privateKey: privateKey)
    return try material(hostId: hostId, certificateDER: certificateData, privateKey: privateKey)
  }

  func rotate() throws -> [String: String] {
    try deletePrivateKey()
    try deleteSecret(account: "host-id")
    try deleteSecret(account: "certificate-der")
    return try createIdentity()
  }

  private func createIdentity() throws -> [String: String] {
    let privateKey = try generatePrivateKey()
    var stored = false
    defer {
      if !stored {
        try? deleteSecret(account: "host-id")
        try? deleteSecret(account: "certificate-der")
        try? deletePrivateKey()
      }
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw HostIdentityFailure.keyGenerationFailed
    }
    let privateBytes = try externalRepresentation(of: privateKey)
    let publicBytes = try externalRepresentation(of: publicKey)
    guard privateBytes.count == 97,
          publicBytes.count == 65,
          privateBytes.first == 0x04,
          publicBytes.first == 0x04
    else {
      throw HostIdentityFailure.invalidKeyEncoding
    }

    let hostId = "host-" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    let certificateDER = try selfSignedCertificate(
      privateKey: privateKey,
      publicKeyBytes: Array(publicBytes)
    )
    try writeSecret(account: "host-id", value: Data(hostId.utf8))
    try writeSecret(account: "certificate-der", value: certificateDER)
    let result = try material(hostId: hostId, certificateDER: certificateDER, privateKey: privateKey)
    stored = true
    return result
  }

  private func generatePrivateKey() throws -> SecKey {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: privateKeyTag,
      ],
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw error?.takeRetainedValue() ?? HostIdentityFailure.keyGenerationFailed
    }
    return key
  }

  private func loadPrivateKey() throws -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
      kSecAttrApplicationTag as String: privateKeyTag,
      kSecReturnRef as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let result else {
      throw HostIdentityFailure.keychainFailure
    }
    // The query is restricted to kSecClassKey with kSecReturnRef, so the
    // successful result is guaranteed by Security.framework to be a SecKey.
    let key: SecKey = result as! SecKey
    return Optional.some(key)
  }

  private func deletePrivateKey() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
      kSecAttrApplicationTag as String: privateKeyTag,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw HostIdentityFailure.keychainFailure
    }
  }

  private func validateCertificate(_ certificateDER: Data, privateKey: SecKey) throws {
    guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
          let certificateKey = SecCertificateCopyKey(certificate),
          let publicKey = SecKeyCopyPublicKey(privateKey),
          try externalRepresentation(of: certificateKey) == externalRepresentation(of: publicKey)
    else {
      throw HostIdentityFailure.invalidStoredIdentity
    }
  }

  private func externalRepresentation(of key: SecKey) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
      throw error?.takeRetainedValue() ?? HostIdentityFailure.keychainFailure
    }
    return data
  }

  private func material(hostId: String, certificateDER: Data, privateKey: SecKey) throws -> [String: String] {
    let privateBytes = try externalRepresentation(of: privateKey)
    let publicKey = SecKeyCopyPublicKey(privateKey)
    guard privateBytes.count == 97,
          privateBytes.first == 0x04,
          let publicKey,
          try externalRepresentation(of: publicKey).count == 65
    else {
      throw HostIdentityFailure.invalidKeyEncoding
    }
    let publicBytes = try externalRepresentation(of: publicKey)
    let scalar = Array(privateBytes.suffix(32))
    let ecPrivateKey = derSequence([
      derInteger([1]),
      derOctetString(scalar),
      der(0xA0, derObjectIdentifier("1.2.840.10045.3.1.7")),
      der(0xA1, derBitString(Array(publicBytes))),
    ])
    return [
      "hostId": hostId,
      "certificatePem": pem(label: "CERTIFICATE", der: Array(certificateDER)),
      "privateKeyPem": pem(label: "EC PRIVATE KEY", der: ecPrivateKey),
    ]
  }

  private func selfSignedCertificate(privateKey: SecKey, publicKeyBytes: [UInt8]) throws -> Data {
    let signatureAlgorithm = derSequence([derObjectIdentifier("1.2.840.10045.4.3.2")])
    let name = derSequence([
      der(0x31, derSequence([derObjectIdentifier("2.5.4.3"), derUtf8("Aggregate Host")])),
      der(0x31, derSequence([derObjectIdentifier("2.5.4.10"), derUtf8("Aggregate")])),
    ])
    var serial = [UInt8](repeating: 0, count: 16)
    guard SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial) == errSecSuccess else {
      throw HostIdentityFailure.keyGenerationFailed
    }
    serial[serial.count - 1] |= 1
    let now = Date()
    let validity = derSequence([
      derUtcTime(now.addingTimeInterval(-300)),
      derUtcTime(now.addingTimeInterval(3650 * 24 * 60 * 60)),
    ])
    let subjectPublicKeyInfo = derSequence([
      derSequence([
        derObjectIdentifier("1.2.840.10045.2.1"),
        derObjectIdentifier("1.2.840.10045.3.1.7"),
      ]),
      derBitString(publicKeyBytes),
    ])
    let keyUsage = derSequence([
      derObjectIdentifier("2.5.29.15"),
      der(0x01, [0xFF]),
      derOctetString(der(0x03, [0x07, 0x80])),
    ])
    let extendedKeyUsage = derSequence([
      derObjectIdentifier("2.5.29.37"),
      derOctetString(derSequence([derObjectIdentifier("1.3.6.1.5.5.7.3.1")])),
    ])
    let basicConstraints = derSequence([
      derObjectIdentifier("2.5.29.19"),
      der(0x01, [0xFF]),
      derOctetString(derSequence([])),
    ])
    let subjectAltName = derSequence([
      derObjectIdentifier("2.5.29.17"),
      derOctetString(derSequence([der(0x82, Array("aggregate-host.local".utf8))])),
    ])
    let extensions = der(0xA3, derSequence([keyUsage, extendedKeyUsage, basicConstraints, subjectAltName]))
    let tbsCertificate = derSequence([
      der(0xA0, derInteger([2])),
      derInteger(serial),
      signatureAlgorithm,
      name,
      validity,
      name,
      subjectPublicKeyInfo,
      extensions,
    ])
    var signingError: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(
      privateKey,
      .ecdsaSignatureMessageX962SHA256,
      Data(tbsCertificate) as CFData,
      &signingError
    ) as Data? else {
      throw signingError?.takeRetainedValue() ?? HostIdentityFailure.keyGenerationFailed
    }
    return Data(derSequence([
      tbsCertificate,
      signatureAlgorithm,
      derBitString(Array(signature)),
    ]))
  }

  private func pem(label: String, der bytes: [UInt8]) -> String {
    let encoded = Data(bytes).base64EncodedString()
    let lines = stride(from: 0, to: encoded.count, by: 64).map { start -> String in
      let lower = encoded.index(encoded.startIndex, offsetBy: start)
      let upper = encoded.index(lower, offsetBy: min(64, encoded.distance(from: lower, to: encoded.endIndex)))
      return String(encoded[lower..<upper])
    }
    return "-----BEGIN \(label)-----\n\(lines.joined(separator: "\n"))\n-----END \(label)-----\n"
  }

  private func derSequence(_ contents: [[UInt8]]) -> [UInt8] { der(0x30, contents.flatMap { $0 }) }
  private func derInteger(_ input: [UInt8]) -> [UInt8] {
    var bytes = Array(input.drop(while: { $0 == 0 }))
    if bytes.isEmpty { bytes = [0] }
    if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
    return der(0x02, bytes)
  }
  private func derOctetString(_ bytes: [UInt8]) -> [UInt8] { der(0x04, bytes) }
  private func derUtf8(_ value: String) -> [UInt8] { der(0x0C, Array(value.utf8)) }
  private func derBitString(_ bytes: [UInt8]) -> [UInt8] { der(0x03, [0] + bytes) }
  private func derUtcTime(_ date: Date) -> [UInt8] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyMMddHHmmss'Z'"
    return der(0x17, Array(formatter.string(from: date).utf8))
  }
  private func derObjectIdentifier(_ dotted: String) -> [UInt8] {
    let arcs = dotted.split(separator: ".").compactMap { UInt64($0) }
    guard arcs.count >= 2 else { return der(0x06, []) }
    var encoded = [UInt8]()
    let all = [arcs[0] * 40 + arcs[1]] + arcs.dropFirst(2)
    for arc in all {
      var groups = [UInt8(arc & 0x7F)]
      var value = arc >> 7
      while value > 0 {
        groups.insert(UInt8(value & 0x7F), at: 0)
        value >>= 7
      }
      for index in groups.indices where index < groups.count - 1 {
        groups[index] |= 0x80
      }
      encoded.append(contentsOf: groups)
    }
    return der(0x06, encoded)
  }
  private func der(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
    var length = [UInt8]()
    if content.count < 128 {
      length = [UInt8(content.count)]
    } else {
      var value = content.count
      var bytes = [UInt8]()
      while value > 0 {
        bytes.insert(UInt8(value & 0xFF), at: 0)
        value >>= 8
      }
      length = [0x80 | UInt8(bytes.count)] + bytes
    }
    return [tag] + length + content
  }

  private func queryKeychain(_ query: [String: Any]) throws -> (OSStatus, CFTypeRef?) {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    return (status, result)
  }

  private func secretQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func readSecret(account: String) throws -> Data? {
    var query = secretQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, value) = try queryKeychain(query)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = value as? Data else {
      throw HostIdentityFailure.keychainFailure
    }
    return data
  }

  private func writeSecret(account: String, value: Data) throws {
    let query = secretQuery(account: account)
    let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = value
      guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
        throw HostIdentityFailure.keychainFailure
      }
    } else if updateStatus != errSecSuccess {
      throw HostIdentityFailure.keychainFailure
    }
  }

  private func deleteSecret(account: String) throws {
    let status = SecItemDelete(secretQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw HostIdentityFailure.keychainFailure
    }
  }
}

private enum HostIdentityFailure: Error {
  case keyGenerationFailed
  case invalidKeyEncoding
  case invalidStoredIdentity
  case keychainFailure
}
