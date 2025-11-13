import 'dart:async';
import 'dart:ui' show Size;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;

/// Background blur service for video calls
/// 
/// Uses ML Kit Selfie Segmentation to detect person and blur background
/// Similar to FaceTime's Portrait Mode
/// 
/// Performance: ~50-100ms per frame (Flutter is slower than native)
class BackgroundBlurService extends ChangeNotifier {
  static const String _tag = 'BackgroundBlur';
  static const double _confidenceThreshold = 0.5;
  static const int _blurRadius = 25;

  SelfieSegmenter? _segmenter;
  bool _isInitialized = false;
  bool _isEnabled = false;
  bool _isProcessing = false;

  bool get isEnabled => _isEnabled;
  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;

  /// Initialize the background blur processor
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize ML Kit Selfie Segmentation
      // STREAM_MODE is optimized for video (faster, less accurate)
      _segmenter = SelfieSegmenter(
        mode: SegmenterMode.stream,
        enableRawSizeMask: true,
      );
      _isInitialized = true;

      debugPrint('$_tag: ✅ Background blur initialized');
    } catch (e) {
      debugPrint('$_tag: ❌ Failed to initialize: $e');
      rethrow;
    }
  }

  /// Enable or disable background blur
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;

    if (enabled && !_isInitialized) {
      await initialize();
    }

    _isEnabled = enabled;
    notifyListeners();
    debugPrint('$_tag: Background blur ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Process a video frame and blur the background
  /// 
  /// @param inputImage Input image as Uint8List (RGBA format)
  /// @param width Image width
  /// @param height Image height
  /// @return Processed image with blurred background, or null on error
  Future<Uint8List?> processFrame(
    Uint8List inputImage,
    int width,
    int height,
  ) async {
    if (!_isEnabled || !_isInitialized || _isProcessing) {
      return null;
    }

    _isProcessing = true;

    try {
      final startTime = DateTime.now();

      // Step 1: Convert to InputImage for ML Kit
      final inputImageForML = InputImage.fromBytes(
        bytes: inputImage,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21, // Android format
          bytesPerRow: width * 4,
        ),
      );

      // Step 2: Get segmentation mask
      final mask = await _segmenter!.processImage(inputImageForML);
      if (mask == null) {
        _isProcessing = false;
        return null;
      }

      // Step 3: Decode input image
      final decodedImage = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: inputImage.buffer,
        numChannels: 4,
      );

      // Step 4: Apply blur to background
      final blurred = _blurImage(decodedImage, _blurRadius);

      // Step 5: Composite foreground over blurred background
      final output = _compositeForegroundAndBackground(
        foreground: decodedImage,
        background: blurred,
        mask: mask,
      );

      // Step 6: Encode back to bytes
      final outputBytes = output.buffer.asUint8List();

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;
      if (processingTime > 100) {
        debugPrint('$_tag: ⚠️ Slow processing: ${processingTime}ms');
      }

      _isProcessing = false;
      return outputBytes;
    } catch (e) {
      debugPrint('$_tag: ❌ Error processing frame: $e');
      _isProcessing = false;
      return null;
    }
  }

  /// Blur an image using Gaussian blur
  img.Image _blurImage(img.Image input, int radius) {
    // Use the image package's built-in Gaussian blur
    // This is slower than RenderScript but works cross-platform
    return img.gaussianBlur(input, radius: radius);
  }

  /// Composite foreground (person) over blurred background using segmentation mask
  img.Image _compositeForegroundAndBackground({
    required img.Image foreground,
    required img.Image background,
    required SegmentationMask mask,
  }) {
    final output = img.Image.from(background);
    final maskData = mask.confidences;
    final maskWidth = mask.width;
    final maskHeight = mask.height;

    // Scale factors if mask resolution differs from image
    final scaleX = foreground.width / maskWidth;
    final scaleY = foreground.height / maskHeight;

    // Apply mask: copy foreground pixels where person is detected
    for (int y = 0; y < maskHeight; y++) {
      for (int x = 0; x < maskWidth; x++) {
        final maskIndex = y * maskWidth + x;
        if (maskIndex < maskData.length) {
          final confidence = maskData[maskIndex];

          // Map mask coordinates to image coordinates
          final imgX = (x * scaleX).toInt();
          final imgY = (y * scaleY).toInt();

          if (imgX < foreground.width && imgY < foreground.height) {
            if (confidence > _confidenceThreshold) {
              // This pixel is part of the person - copy from foreground
              final pixel = foreground.getPixel(imgX, imgY);
              output.setPixel(imgX, imgY, pixel);
            }
          }
        }
      }
    }

    return output;
  }

  /// Clean up resources
  @override
  Future<void> dispose() async {
    try {
      await _segmenter?.close();
      _segmenter = null;
      _isInitialized = false;
      _isEnabled = false;
      debugPrint('$_tag: ✅ Background blur disposed');
    } catch (e) {
      debugPrint('$_tag: ❌ Error disposing: $e');
    }
    super.dispose();
  }
}
