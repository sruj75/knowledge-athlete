@preconcurrency import AVFoundation
import Combine
import CoreImage
import Foundation
import ImageIO

struct SupervisorCameraDevice: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let builtIn: Bool
}

struct SupervisorCameraSample: Sendable {
  let jpegData: Data
  let capturedAt: Date
  let capturedUptime: TimeInterval
  let visualHash: UInt64
}

enum SupervisorCameraPermission: Sendable { case authorized, notDetermined, denied }

/// The hardware boundary. It never records audio, creates files, or owns account state.
@MainActor
protocol SupervisorCameraHardware: AnyObject {
  var permission: SupervisorCameraPermission { get }
  var devicesChanged: (@MainActor () -> Void)? { get set }
  func devices() async -> [SupervisorCameraDevice]
  func requestPermission() async -> Bool
  func start(
    deviceID: String, sample: @escaping @Sendable (SupervisorCameraSample) -> Void,
    unavailable: @escaping @Sendable () -> Void)
  func stop()
}

@MainActor
final class SupervisorWebcamService: ObservableObject {
  static let enabledDefaultsKey = "supervisorWebcamEnabled"
  static let deviceDefaultsKey = "supervisorWebcamDeviceID"
  static let shared = SupervisorWebcamService(hardware: AVFoundationSupervisorCamera())

  @Published var enabled: Bool {
    didSet {
      guard enabled != oldValue else { return }
      defaults.set(enabled, forKey: Self.enabledDefaultsKey)
      reconcile()
    }
  }
  @Published var selectedDeviceID: String? {
    didSet {
      guard selectedDeviceID != oldValue else { return }
      defaults.set(selectedDeviceID, forKey: Self.deviceDefaultsKey)
      reconcile()
    }
  }
  @Published private(set) var devices: [SupervisorCameraDevice] = []
  @Published private(set) var availability: SupervisorInputAvailability = .disabled

  private let hardware: any SupervisorCameraHardware
  private let defaults: UserDefaults
  private let currentOwner: @MainActor () -> RuntimeOwnerAuthorizationSnapshot?
  private let ownerIsCurrent: @MainActor (RuntimeOwnerAuthorizationSnapshot) -> Bool
  private let monitoringSession: @MainActor () -> String
  private let deliver: @MainActor (SupervisorCameraSample, String, RuntimeOwnerAuthorizationSnapshot) -> Void
  private let statusChanged: @MainActor (SupervisorInputAvailability) -> Void
  private var allowed = false
  private var generation: UInt64 = 0
  private var configuration: Task<Void, Never>?

  init(
    hardware: any SupervisorCameraHardware,
    defaults: UserDefaults = .standard,
    currentOwner: @escaping @MainActor () -> RuntimeOwnerAuthorizationSnapshot? = {
      RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    },
    ownerIsCurrent: @escaping @MainActor (RuntimeOwnerAuthorizationSnapshot) -> Bool = {
      RuntimeOwnerIdentity.isAuthorizationCurrent($0)
    },
    monitoringSession: @escaping @MainActor () -> String = { SupervisorService.shared.sessionID },
    deliver: @escaping @MainActor (SupervisorCameraSample, String, RuntimeOwnerAuthorizationSnapshot) -> Void = {
      sample, session, owner in
      SupervisorService.shared.observeWebcam(
        jpegData: sample.jpegData, capturedAt: sample.capturedAt, capturedUptime: sample.capturedUptime,
        visualHash: sample.visualHash, observationSessionID: session, authorizationSnapshot: owner)
    },
    statusChanged: @escaping @MainActor (SupervisorInputAvailability) -> Void = {
      SupervisorService.shared.webcamUnavailable($0)
    }
  ) {
    self.hardware = hardware
    self.defaults = defaults
    self.currentOwner = currentOwner
    self.ownerIsCurrent = ownerIsCurrent
    self.monitoringSession = monitoringSession
    self.deliver = deliver
    self.statusChanged = statusChanged
    enabled = defaults.bool(forKey: Self.enabledDefaultsKey)
    selectedDeviceID = defaults.string(forKey: Self.deviceDefaultsKey)
    hardware.devicesChanged = { [weak self] in self?.reconcile() }
  }

  func setMonitoringAllowed(_ value: Bool) {
    guard value != allowed else { return }
    allowed = value
    reconcile()
  }

  func refreshDevices() async {
    devices = await hardware.devices()
  }

  private func setAvailability(_ value: SupervisorInputAvailability) {
    availability = value
    if value != .available { statusChanged(value) }
  }

  private func reconcile() {
    generation &+= 1
    let token = generation
    configuration?.cancel()
    configuration = nil
    hardware.stop()
    setAvailability(!enabled ? .disabled : (!allowed ? .suspended : .unavailable))
    guard enabled, allowed, let owner = currentOwner(), ownerIsCurrent(owner) else { return }
    let session = monitoringSession()
    configuration = Task { [weak self] in
      guard let self else { return }
      let devices = await hardware.devices()
      guard accepts(token, owner: owner), !Task.isCancelled else { return }
      self.devices = devices
      let permitted: Bool
      switch hardware.permission {
      case .authorized: permitted = true
      case .denied: permitted = false
      case .notDetermined: permitted = await hardware.requestPermission()
      }
      guard accepts(token, owner: owner), !Task.isCancelled else { return }
      guard permitted else {
        setAvailability(.denied)
        return
      }
      let device =
        selectedDeviceID.flatMap { id in devices.first { $0.id == id } }
        ?? (selectedDeviceID == nil ? devices.first { $0.builtIn } : nil)
      guard let device else {
        setAvailability(.unavailable)
        return
      }
      hardware.start(
        deviceID: device.id,
        sample: { [weak self] sample in
          Task { @MainActor in
            guard let self, self.accepts(token, owner: owner), self.monitoringSession() == session else { return }
            self.setAvailability(.available)
            self.deliver(sample, session, owner)
          }
        },
        unavailable: { [weak self] in
          Task { @MainActor in
            guard let self, self.accepts(token, owner: owner) else { return }
            self.generation &+= 1
            self.hardware.stop()
            self.setAvailability(.unavailable)
          }
        })
    }
  }

  private func accepts(_ token: UInt64, owner: RuntimeOwnerAuthorizationSnapshot) -> Bool {
    enabled && allowed && token == generation && ownerIsCurrent(owner)
  }
}

@MainActor
private final class AVFoundationSupervisorCamera: SupervisorCameraHardware {
  var devicesChanged: (@MainActor () -> Void)?
  private let worker = SupervisorCameraWorker()
  private var observers: [NSObjectProtocol] = []

  init() {
    for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.devicesChanged?() }
        })
    }
  }

  var permission: SupervisorCameraPermission {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return .authorized
    case .notDetermined: return .notDetermined
    default: return .denied
    }
  }

  func requestPermission() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

  func devices() async -> [SupervisorCameraDevice] {
    await Task.detached {
      AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
        mediaType: .video, position: .unspecified
      ).devices.map {
        SupervisorCameraDevice(
          id: $0.uniqueID, name: $0.localizedName, builtIn: $0.deviceType == .builtInWideAngleCamera)
      }
    }.value
  }

  func start(
    deviceID: String, sample: @escaping @Sendable (SupervisorCameraSample) -> Void,
    unavailable: @escaping @Sendable () -> Void
  ) {
    worker.start(deviceID: deviceID, sample: sample, unavailable: unavailable)
  }

  func stop() { worker.stop() }
}

/// All mutable capture/encoding state stays on this serial worker. Only bounded,
/// immutable JPEG samples cross to MainActor; AVFoundation drops queued video.
private final class SupervisorCameraWorker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable
{
  private let queue = DispatchQueue(label: "com.heyintentive.supervisor.webcam", qos: .utility)
  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private var session: AVCaptureSession?
  private var output: AVCaptureVideoDataOutput?
  private var receiver: (@Sendable (SupervisorCameraSample) -> Void)?
  private var failureObserver: NSObjectProtocol?
  private var lastSample: TimeInterval = -.infinity
  private let delivery = SupervisorCameraSampleDelivery()

  func start(
    deviceID: String, sample: @escaping @Sendable (SupervisorCameraSample) -> Void,
    unavailable: @escaping @Sendable () -> Void
  ) {
    queue.async { [self] in
      stopOnQueue()
      guard let device = AVCaptureDevice(uniqueID: deviceID) else {
        unavailable()
        return
      }
      do {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
          session.commitConfiguration()
          unavailable()
          return
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        guard session.canAddOutput(output) else {
          session.commitConfiguration()
          unavailable()
          return
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
          $0.minFrameRate <= 1 && $0.maxFrameRate >= 1
        }) {
          try device.lockForConfiguration()
          device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 1)
          device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 1)
          device.unlockForConfiguration()
        }
        self.session = session
        self.output = output
        receiver = sample
        failureObserver = NotificationCenter.default.addObserver(
          forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { _ in unavailable() }
        session.startRunning()
      } catch {
        stopOnQueue()
        unavailable()
      }
    }
  }

  func stop() { queue.async { [self] in stopOnQueue() } }

  private func stopOnQueue() {
    receiver = nil
    delivery.clear()
    if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    failureObserver = nil
    output?.setSampleBufferDelegate(nil, queue: nil)
    session?.stopRunning()
    output = nil
    session = nil
    lastSample = -.infinity
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
  ) {
    let uptime = ProcessInfo.processInfo.systemUptime
    guard uptime - lastSample >= 1, let receiver, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    lastSample = uptime
    let capturedAt = Date()
    autoreleasepool {
      let source = CIImage(cvPixelBuffer: pixelBuffer)
      let scale = min(1, 640 / max(source.extent.width, source.extent.height))
      let resized = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      guard let image = imageContext.createCGImage(resized, from: resized.extent) else { return }
      for quality in [0.7, 0.5, 0.3] {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil) else {
          return
        }
        CGImageDestinationAddImage(
          destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        guard bytes.length <= 256_000 else { continue }
        delivery.offer(
          .init(
            jpegData: bytes as Data, capturedAt: capturedAt, capturedUptime: uptime,
            visualHash: RewindOCRService.dHash(of: image)), receiver: receiver)
        return
      }
    }
  }
}

private final class SupervisorCameraSampleDelivery: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: (SupervisorCameraSample, @Sendable (SupervisorCameraSample) -> Void)?
  private var scheduled = false

  func clear() { lock.withLock { pending = nil } }

  func offer(_ sample: SupervisorCameraSample, receiver: @escaping @Sendable (SupervisorCameraSample) -> Void) {
    let schedule = lock.withLock {
      pending = (sample, receiver)
      guard !scheduled else { return false }
      scheduled = true
      return true
    }
    guard schedule else { return }
    Task { @MainActor [self] in
      let value = lock.withLock {
        let value = pending
        pending = nil
        scheduled = false
        return value
      }
      if let (sample, receiver) = value { receiver(sample) }
    }
  }
}
