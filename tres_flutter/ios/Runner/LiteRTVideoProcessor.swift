import Foundation
import UIKit
import Accelerate
import AVFoundation

#if canImport(TensorFlowLite)
import TensorFlowLite
#endif

/// LiteRT (on-device ML) video frame processor for iOS.
///
/// Mirrors the functionality of LiteRTVideoProcessor.kt on Android.
/// Hooks into the flutter_webrtc / LiveKit capture pipeline via the
/// RTCVideoCapturerDelegate or a custom VideoProcessor protocol.
///
/// Features:
///   - Background blur  (selfie_segmentation.tflite)
///   - Low-light enhancement  (low_light_enhance.tflite)
///   - Sharpening  (vImage convolution kernel — no model needed)
///
/// Models must be placed in the iOS app bundle under Resources/models/.
/// See android/app/src/main/assets/models/README.md for download links;
/// the same .tflite files are cross-platform.
@objc class LiteRTVideoProcessor: NSObject {

    // ── Configuration ─────────────────────────────────────────────────────────
    @objc var backgroundBlurEnabled: Bool = false
    @objc var lowLightEnabled: Bool = false
    @objc var sharpeningEnabled: Bool = false
    @objc var blurRadius: Float = 20.0

    // ── LiteRT interpreters ───────────────────────────────────────────────────
    private var segInterpreter: Any? = nil   // Interpreter (TFLite)
    private var lowLightInterpreter: Any? = nil
    private var gpuAvailable: Bool = false

    // Frame-skip guard
    private var isProcessing: Bool = false
    private let processingLock = NSLock()

    // Model constants
    private let segW = 256
    private let segH = 144
    private let llSize = 400

    // ── Capabilities ─────────────────────────────────────────────────────────
    @objc var hasBackgroundBlur: Bool { segInterpreter != nil }
    @objc var hasLowLight: Bool { lowLightInterpreter != nil }

    // ── Init ──────────────────────────────────────────────────────────────────
    override init() {
        super.init()
        loadModels()
    }

    private func loadModels() {
        #if canImport(TensorFlowLite)
        do {
            var options = Interpreter.Options()
            // Enable Metal GPU delegate on supported devices
            if #available(iOS 12.0, *) {
                let metalDelegate = MetalDelegate()
                options.delegates = [metalDelegate]
                gpuAvailable = true
            }
            options.threadCount = gpuAvailable ? 1 : 2

            if let segPath = Bundle.main.path(forResource: "selfie_segmentation",
                                               ofType: "tflite",
                                               inDirectory: "models") {
                segInterpreter = try Interpreter(modelPath: segPath, options: options)
                (segInterpreter as? Interpreter)?.allocateTensors()
                NSLog("[LiteRTVideoProcessor] Segmentation model loaded")
            } else {
                NSLog("[LiteRTVideoProcessor] selfie_segmentation.tflite not found — background blur disabled")
            }

            if let llPath = Bundle.main.path(forResource: "low_light_enhance",
                                              ofType: "tflite",
                                              inDirectory: "models") {
                lowLightInterpreter = try Interpreter(modelPath: llPath, options: options)
                (lowLightInterpreter as? Interpreter)?.allocateTensors()
                NSLog("[LiteRTVideoProcessor] Low-light model loaded")
            } else {
                NSLog("[LiteRTVideoProcessor] low_light_enhance.tflite not found — low-light disabled")
            }
        } catch {
            NSLog("[LiteRTVideoProcessor] Model load error: \(error)")
        }
        #else
        NSLog("[LiteRTVideoProcessor] TensorFlowLite not linked — all ML features disabled")
        #endif
    }

    // ── Public frame processing ───────────────────────────────────────────────

    /// Process a CVPixelBuffer in-place.  Returns nil to indicate the caller
    /// should use the original buffer unmodified (e.g. during frame skip).
    @objc func processFrame(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let doBlur = backgroundBlurEnabled && hasBackgroundBlur
        let doLL   = lowLightEnabled && hasLowLight
        let doSharp = sharpeningEnabled

        guard doBlur || doLL || doSharp else { return nil }

        // Frame skip: if previous frame is still processing, pass through
        guard processingLock.try() else { return nil }
        defer { processingLock.unlock() }

        guard let uiImage = uiImageFromPixelBuffer(pixelBuffer),
              let cgImage = uiImage.cgImage else { return nil }

        var processed: CGImage = cgImage

        // 1. Low-light
        if doLL, isLowLight(cgImage) {
            processed = runLowLight(processed) ?? processed
        }

        // 2. Background blur
        if doBlur {
            processed = runBackgroundBlur(processed) ?? processed
        }

        // 3. Sharpening
        if doSharp {
            processed = applySharpen(processed) ?? processed
        }

        return pixelBufferFromCGImage(processed, like: pixelBuffer)
    }

    /// Receiver-side processing for remote video.
    /// Applies low-light enhancement and sharpening only.
    @objc func processRemoteFrame(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let doLL = lowLightEnabled && hasLowLight
        let doSharp = sharpeningEnabled

        guard doLL || doSharp else { return nil }

        guard processingLock.try() else { return nil }
        defer { processingLock.unlock() }

        guard let uiImage = uiImageFromPixelBuffer(pixelBuffer),
              let cgImage = uiImage.cgImage else { return nil }

        var processed: CGImage = cgImage

        if doLL, isLowLight(cgImage) {
            processed = runLowLight(processed) ?? processed
        }

        if doSharp {
            processed = applySharpen(processed) ?? processed
        }

        return pixelBufferFromCGImage(processed, like: pixelBuffer)
    }

    // ── Low-light detection ───────────────────────────────────────────────────

    private func isLowLight(_ image: CGImage) -> Bool {
        guard let thumb = scaledCGImage(image, width: 32, height: 32) else { return false }
        let byteCount = 32 * 32 * 4
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: 32, height: 32,
                                   bitsPerComponent: 8, bytesPerRow: 32 * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        var totalLuma: Float = 0
        for i in stride(from: 0, to: byteCount, by: 4) {
            let r = Float(bytes[i])
            let g = Float(bytes[i + 1])
            let b = Float(bytes[i + 2])
            totalLuma += 0.299 * r + 0.587 * g + 0.114 * b
        }
        return (totalLuma / Float(32 * 32)) < 85
    }

    // ── Background blur via segmentation ─────────────────────────────────────

    private func runBackgroundBlur(_ src: CGImage) -> CGImage? {
        #if canImport(TensorFlowLite)
        guard let interp = segInterpreter as? Interpreter,
              let scaled = scaledCGImage(src, width: segW, height: segH),
              let inputData = cgImageToRGBFloat(scaled, width: segW, height: segH) else {
            return nil
        }

        do {
            try interp.copy(inputData, toInputAt: 0)
            try interp.invoke()
            let outputTensor = try interp.output(at: 0)
            let maskData = outputTensor.data

            // Build alpha mask at model resolution
            let maskPixelCount = segW * segH
            var maskBytes = [UInt8](repeating: 0, count: maskPixelCount * 4)
            maskData.withUnsafeBytes { ptr in
                let floats = ptr.bindMemory(to: Float32.self)
                for i in 0 ..< maskPixelCount {
                    let alpha = UInt8(min(max(floats[i], 0), 1) * 255)
                    maskBytes[i * 4 + 0] = 255
                    maskBytes[i * 4 + 1] = 255
                    maskBytes[i * 4 + 2] = 255
                    maskBytes[i * 4 + 3] = alpha
                }
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let maskCtx = CGContext(data: &maskBytes, width: segW, height: segH,
                                           bitsPerComponent: 8, bytesPerRow: segW * 4,
                                           space: colorSpace,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let maskSmall = maskCtx.makeImage(),
                  let mask = scaledCGImage(maskSmall, width: src.width, height: src.height),
                  let blurred = gaussianBlur(src, radius: blurRadius) else {
                return nil
            }

            return compositePersonOverBlur(original: src, blurred: blurred, mask: mask)
        } catch {
            NSLog("[LiteRTVideoProcessor] Segmentation inference error: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    // ── Low-light enhancement ─────────────────────────────────────────────────

    private func runLowLight(_ src: CGImage) -> CGImage? {
        #if canImport(TensorFlowLite)
        guard let interp = lowLightInterpreter as? Interpreter,
              let scaled = scaledCGImage(src, width: llSize, height: llSize),
              let inputData = cgImageToRGBFloat(scaled, width: llSize, height: llSize) else {
            return nil
        }

        do {
            try interp.copy(inputData, toInputAt: 0)
            try interp.invoke()
            let outputTensor = try interp.output(at: 0)
            let outData = outputTensor.data

            var outBytes = [UInt8](repeating: 0, count: llSize * llSize * 4)
            outData.withUnsafeBytes { ptr in
                let floats = ptr.bindMemory(to: Float32.self)
                for i in 0 ..< llSize * llSize {
                    outBytes[i * 4 + 0] = UInt8(min(max(floats[i * 3 + 0], 0), 1) * 255)
                    outBytes[i * 4 + 1] = UInt8(min(max(floats[i * 3 + 1], 0), 1) * 255)
                    outBytes[i * 4 + 2] = UInt8(min(max(floats[i * 3 + 2], 0), 1) * 255)
                    outBytes[i * 4 + 3] = 255
                }
            }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: &outBytes, width: llSize, height: llSize,
                                       bitsPerComponent: 8, bytesPerRow: llSize * 4,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let enhanced = ctx.makeImage() else {
                return nil
            }
            return scaledCGImage(enhanced, width: src.width, height: src.height)
        } catch {
            NSLog("[LiteRTVideoProcessor] Low-light inference error: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    // ── Sharpening via vImage convolution ────────────────────────────────────

    private func applySharpen(_ src: CGImage) -> CGImage? {
        let kernel: [Int16] = [0, -1, 0,
                               -1,  5, -1,
                                0, -1, 0]
        var srcBuffer = vImage_Buffer()
        var dstBuffer = vImage_Buffer()

        guard vImageBuffer_InitWithCGImage(&srcBuffer, nil, nil, src, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        defer { free(srcBuffer.data) }

        guard vImageBuffer_Init(&dstBuffer, srcBuffer.height, srcBuffer.width,
                                32, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        defer { free(dstBuffer.data) }

        let divisor: Int32 = 1
        let error = vImageConvolve_ARGB8888(&srcBuffer, &dstBuffer, nil, 0, 0,
                                             kernel, 3, 3, divisor,
                                             nil, vImage_Flags(kvImageEdgeExtend))
        guard error == kvImageNoError else { return nil }

        var cgFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
            version: 0, decode: nil, renderingIntent: .defaultIntent)
        return vImageCreateCGImageFromBuffer(&dstBuffer, &cgFormat, nil, nil,
                                             vImage_Flags(kvImageNoFlags), nil)?.takeRetainedValue()
    }

    // ── Gaussian blur (vImage) ────────────────────────────────────────────────

    private func gaussianBlur(_ src: CGImage, radius: Float) -> CGImage? {
        var srcBuffer = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&srcBuffer, nil, nil, src, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        defer { free(srcBuffer.data) }

        var dstBuffer = vImage_Buffer()
        guard vImageBuffer_Init(&dstBuffer, srcBuffer.height, srcBuffer.width,
                                32, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
        defer { free(dstBuffer.data) }

        // Kernel size must be odd
        var ks = Int(radius) * 2 + 1
        if ks % 2 == 0 { ks += 1 }
        let error = vImageTentConvolve_ARGB8888(&srcBuffer, &dstBuffer, nil, 0, 0,
                                                 vImagePixelCount(ks), vImagePixelCount(ks),
                                                 nil, vImage_Flags(kvImageEdgeExtend))
        guard error == kvImageNoError else { return nil }

        var cgFormat = vImage_CGImageFormat(
            bitsPerComponent: 8, bitsPerPixel: 32,
            colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
            version: 0, decode: nil, renderingIntent: .defaultIntent)
        return vImageCreateCGImageFromBuffer(&dstBuffer, &cgFormat, nil, nil,
                                             vImage_Flags(kvImageNoFlags), nil)?.takeRetainedValue()
    }

    // ── Compositing ───────────────────────────────────────────────────────────

    private func compositePersonOverBlur(original: CGImage, blurred: CGImage, mask: CGImage) -> CGImage? {
        let w = original.width
        let h = original.height
        UIGraphicsBeginImageContextWithOptions(CGSize(width: w, height: h), false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(blurred, in: rect)
        ctx.clip(to: rect, mask: mask)
        ctx.draw(original, in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }

    // ── Image utilities ───────────────────────────────────────────────────────

    private func scaledCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private func cgImageToRGBFloat(_ image: CGImage, width: Int, height: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var floats = [Float32](repeating: 0, count: width * height * 3)
        for i in 0 ..< width * height {
            floats[i * 3 + 0] = Float32(bytes[i * 4 + 0]) / 255.0
            floats[i * 3 + 1] = Float32(bytes[i * 4 + 1]) / 255.0
            floats[i * 3 + 2] = Float32(bytes[i * 4 + 2]) / 255.0
        }
        return Data(bytes: &floats, count: floats.count * MemoryLayout<Float32>.size)
    }

    private func uiImageFromPixelBuffer(_ buffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func pixelBufferFromCGImage(_ image: CGImage, like original: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(original)
        let h = CVPixelBufferGetHeight(original)
        let pixelFormat = CVPixelBufferGetPixelFormatType(original)

        var newBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, pixelFormat, attrs, &newBuffer) == kCVReturnSuccess,
              let buf = newBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buf, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf),
                            width: w, height: h,
                            bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        CVPixelBufferUnlockBaseAddress(buf, [])
        return buf
    }

    // ── Capabilities ─────────────────────────────────────────────────────────

    @objc func capabilities() -> [String: Bool] {
        return [
            "backgroundBlur": hasBackgroundBlur,
            "lowLight": hasLowLight,
            "sharpening": true,
            "gpuDelegate": gpuAvailable,
        ]
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    @objc func dispose() {
        segInterpreter = nil
        lowLightInterpreter = nil
    }
}

