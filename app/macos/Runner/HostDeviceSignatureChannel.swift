import CryptoKit
import FlutterMacOS
import Foundation

final class HostDeviceSignatureChannel {
  private let channel: FlutterMethodChannel
  private let verificationQueue = DispatchQueue(
    label: "io.github.guog962464.aggregate.host-signature-verification",
    qos: .userInitiated
  )

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "aggregate/host_authentication",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard call.method == "verifyDeviceSignature",
            let arguments = call.arguments as? [String: Any],
            let publicKeyBase64 = arguments["publicKeySpki"] as? String,
            let messageBase64 = arguments["message"] as? String,
            let signatureBase64 = arguments["signature"] as? String,
            publicKeyBase64.utf8.count <= 1024,
            messageBase64.utf8.count <= 1_400_000,
            signatureBase64.utf8.count <= 256,
            let publicKeyDER = Data(base64Encoded: publicKeyBase64),
            let message = Data(base64Encoded: messageBase64),
            let signatureDER = Data(base64Encoded: signatureBase64),
            !publicKeyDER.isEmpty,
            !message.isEmpty,
            !signatureDER.isEmpty,
            publicKeyDER.count <= 256,
            message.count <= 1_048_576,
            signatureDER.count <= 80
      else {
        result(false)
        return
      }

      self.verificationQueue.async {
        let isValid = Self.verify(
          publicKeyDER: publicKeyDER,
          message: message,
          signatureDER: signatureDER
        )
        DispatchQueue.main.async { result(isValid) }
      }
    }
  }

  private static func verify(
    publicKeyDER: Data,
    message: Data,
    signatureDER: Data
  ) -> Bool {
    do {
      let publicKey = try P256.Signing.PublicKey(derRepresentation: publicKeyDER)
      let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureDER)
      return publicKey.isValidSignature(signature, for: message)
    } catch {
      return false
    }
  }
}
