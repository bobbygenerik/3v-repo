import Flutter
import UIKit
import WebRTC
import flutter_webrtc

final class LiteRTRemoteVideoRenderer: NSObject, FlutterTexture, RTCVideoRenderer {
  private let registry: FlutterTextureRegistry
  private let processor: LiteRTVideoProcessor
  private let lock = NSLock()

  private(set) var textureId: Int64 = -1
  private var latestBuffer: CVPixelBuffer?
  private var frameAvailable = false
  private weak var videoTrack: RTCVideoTrack?

  init(registry: FlutterTextureRegistry, processor: LiteRTVideoProcessor) {
    self.registry = registry
    self.processor = processor
    super.init()
    textureId = registry.register(self)
  }

  func setVideoTrack(_ track: RTCVideoTrack?) {
    if videoTrack === track {
      return
    }
    videoTrack?.remove(self)
    videoTrack = track
    track?.add(self)
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }

    guard let buffer = latestBuffer, frameAvailable else {
      return nil
    }

    frameAvailable = false
    return Unmanaged.passRetained(buffer)
  }

  func setSize(_ size: CGSize) {}

  func renderFrame(_ frame: RTCVideoFrame?) {
    guard let frame else { return }

    let sourceBuffer: CVPixelBuffer?
    if let cvBuffer = frame.buffer as? RTCCVPixelBuffer {
      sourceBuffer = cvBuffer.pixelBuffer
    } else {
      sourceBuffer = nil
    }

    guard let pixelBuffer = sourceBuffer else {
      return
    }

    let processedBuffer = processor.processRemoteFrame(pixelBuffer) ?? pixelBuffer

    lock.lock()
    latestBuffer = processedBuffer
    frameAvailable = true
    lock.unlock()

    registry.textureFrameAvailable(textureId)
  }

  func dispose() {
    videoTrack?.remove(self)
    videoTrack = nil
    lock.lock()
    latestBuffer = nil
    frameAvailable = false
    lock.unlock()
    if textureId != -1 {
      registry.unregisterTexture(textureId)
      textureId = -1
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {

  // LiteRT on-device ML processor (shared instance, lives for app lifetime)
  private let liteRTProcessor = LiteRTVideoProcessor()
  private var remoteRenderers: [String: LiteRTRemoteVideoRenderer] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController

    // ── LiteRT ML channel ────────────────────────────────────────────────────
    let liteRTChannel = FlutterMethodChannel(name: "tres3/liteRT",
                                               binaryMessenger: controller.binaryMessenger)
    liteRTChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {

      case "setBackgroundBlur":
        let args = call.arguments as? [String: Any]
        self.liteRTProcessor.backgroundBlurEnabled = args?["enabled"] as? Bool ?? false
        if let r = args?["blurRadius"] as? Double {
          self.liteRTProcessor.blurRadius = Float(r)
        }
        result(nil)

      case "setLowLightEnhancement":
        let args = call.arguments as? [String: Any]
        self.liteRTProcessor.lowLightEnabled = args?["enabled"] as? Bool ?? false
        result(nil)

      case "setSharpening":
        let args = call.arguments as? [String: Any]
        self.liteRTProcessor.sharpeningEnabled = args?["enabled"] as? Bool ?? false
        result(nil)

      case "attachRemoteProcessing":
        guard let args = call.arguments as? [String: Any],
              let trackId = args["trackId"] as? String,
              !trackId.isEmpty else {
          result(FlutterError(code: "INVALID_ARG", message: "trackId is required", details: nil))
          return
        }

        self.attachRemoteProcessing(trackId: trackId, controller: controller, result: result)

      case "detachRemoteProcessing":
        let args = call.arguments as? [String: Any]
        let trackId = args?["trackId"] as? String ?? ""
        self.detachRemoteProcessing(trackId: trackId)
        result(nil)

      case "getCapabilities":
        result(self.liteRTProcessor.capabilities())

      // Audio effects not separately available on iOS (WebRTC handles NS/EC).
      case "setNoiseSuppression", "setLoudnessGain", "setVadEnabled",
           "attachAudio", "detachAudio":
        result(nil)

      case "getAudioStats":
        result([:] as [String: Any])

      case "dispose":
        self.remoteRenderers.keys.forEach { self.detachRemoteProcessing(trackId: $0) }
        self.liteRTProcessor.dispose()
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // ── Spatial audio channel ────────────────────────────────────────────────
    let audioChannel = FlutterMethodChannel(name: "tres3/audio",
                                              binaryMessenger: controller.binaryMessenger)

    audioChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if ("setSpatialAudioEnabled" == call.method) {
        // Acknowledge spatial audio request
        // Actual spatial audio rendering is handled by the OS and WebRTC based on channel count
        // and user's device settings (e.g. AirPods Pro).
        // This channel acknowledges the user's intent to enable/disable feature specific logic if added.
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func attachRemoteProcessing(
    trackId: String,
    controller: FlutterViewController,
    result: FlutterResult
  ) {
    detachRemoteProcessing(trackId: trackId)

    guard let plugin = FlutterWebRTCPlugin.sharedSingleton() else {
      result(FlutterError(code: "PLUGIN_UNAVAILABLE", message: "FlutterWebRTCPlugin not initialized", details: nil))
      return
    }

    guard let track = plugin.track(forId: trackId, peerConnectionId: nil) as? RTCVideoTrack else {
      result(FlutterError(code: "TRACK_NOT_FOUND", message: "Track '\(trackId)' not found", details: nil))
      return
    }

    let renderer = LiteRTRemoteVideoRenderer(
      registry: controller as FlutterTextureRegistry,
      processor: liteRTProcessor
    )
    renderer.setVideoTrack(track)
    remoteRenderers[trackId] = renderer
    result(renderer.textureId)
  }

  private func detachRemoteProcessing(trackId: String) {
    guard let renderer = remoteRenderers.removeValue(forKey: trackId) else {
      return
    }
    renderer.dispose()
  }
}
