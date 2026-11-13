import dnssd
import FlutterMacOS
import Foundation

final class HostBonjourChannel {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(
    label: "io.github.guog962464.aggregate.host-bonjour",
    qos: .userInitiated
  )
  private var registrations: [(reference: OpaquePointer, source: DispatchSourceRead)] = []
  private var pendingRegistrations = 0
  private var publishCompletion: ((Bool) -> Void)?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "aggregate/host_bonjour",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "publish":
        guard let arguments = call.arguments as? [String: Any],
              let hostId = arguments["hostId"] as? String,
              hostId.range(of: #"^host-[a-f0-9]{32}$"#, options: .regularExpression) != nil,
              let port = arguments["port"] as? Int,
              (1...65535).contains(port),
              let interfaceIndices = arguments["interfaceIndices"] as? [Int],
              !interfaceIndices.isEmpty,
              interfaceIndices.count <= 8,
              Set(interfaceIndices).count == interfaceIndices.count,
              interfaceIndices.allSatisfy({ $0 > 0 && $0 <= Int(UInt32.max) })
        else {
          result(FlutterError(code: "invalid_args", message: "Host service is invalid", details: nil))
          return
        }
        self.publish(hostId: hostId, port: port, interfaceIndices: interfaceIndices) { success in
          DispatchQueue.main.async {
            if success {
              result(nil)
            } else {
              result(FlutterError(code: "bonjour_failure", message: "Host discovery could not start", details: nil))
            }
          }
        }
      case "stop":
        self.stop {
          DispatchQueue.main.async { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func publish(
    hostId: String,
    port: Int,
    interfaceIndices: [Int],
    completion: @escaping (Bool) -> Void
  ) {
    queue.async { [weak self] in
      guard let self else { return }
      self.stopRegistrations()
      self.publishCompletion = completion
      self.pendingRegistrations = interfaceIndices.count
      let name = "Aggregate-" + String(hostId.suffix(8))

      for interfaceIndex in interfaceIndices {
        var reference: DNSServiceRef?
        let status = name.withCString { namePointer in
          "_aggregate-host._tcp.".withCString { typePointer in
            DNSServiceRegister(
              &reference,
              0,
              UInt32(interfaceIndex),
              namePointer,
              typePointer,
              "local.",
              nil,
              UInt16(port).bigEndian,
              0,
              nil,
              Self.registrationReply,
              Unmanaged.passUnretained(self).toOpaque()
            )
          }
        }
        guard status == kDNSServiceErr_NoError, let reference else {
          self.finishPublish(success: false)
          return
        }
        let descriptor = DNSServiceRefSockFD(reference)
        guard descriptor >= 0 else {
          DNSServiceRefDeallocate(reference)
          self.finishPublish(success: false)
          return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: self.queue)
        source.setEventHandler { [weak self] in
          guard let self else { return }
          if DNSServiceProcessResult(reference) != kDNSServiceErr_NoError {
            self.finishPublish(success: false)
          }
        }
        source.setCancelHandler {
          DNSServiceRefDeallocate(reference)
        }
        self.registrations.append((reference, source))
        source.resume()
      }

      self.queue.asyncAfter(deadline: .now() + 10) { [weak self] in
        guard let self, self.publishCompletion != nil else { return }
        self.finishPublish(success: false)
      }
    }
  }

  private func stop(completion: @escaping () -> Void) {
    queue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async { completion() }
        return
      }
      self.publishCompletion = nil
      self.pendingRegistrations = 0
      self.stopRegistrations()
      DispatchQueue.main.async { completion() }
    }
  }

  private func stopRegistrations() {
    registrations.forEach { $0.source.cancel() }
    registrations.removeAll()
  }

  private func registrationDidComplete(_ error: DNSServiceErrorType) {
    guard publishCompletion != nil else { return }
    guard error == kDNSServiceErr_NoError else {
      finishPublish(success: false)
      return
    }
    pendingRegistrations -= 1
    if pendingRegistrations == 0 {
      finishPublish(success: true)
    }
  }

  private func finishPublish(success: Bool) {
    guard let completion = publishCompletion else { return }
    publishCompletion = nil
    pendingRegistrations = 0
    if !success { stopRegistrations() }
    completion(success)
  }

  private static let registrationReply: DNSServiceRegisterReply = {
    _, _, error, _, _, _, context in
    guard let context else { return }
    let instance = Unmanaged<HostBonjourChannel>.fromOpaque(context).takeUnretainedValue()
    instance.registrationDidComplete(error)
  }
}
