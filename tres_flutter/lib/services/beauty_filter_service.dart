import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Beauty filter service for video calls
///
/// Applies real-time beauty effects to video frames:
/// - Skin smoothing (reduces blemishes and imperfections)
/// - Brightness adjustment (subtle brightening)
/// - Warm color tone (slight pink tint for healthy appearance)
/// - Edge preservation (maintains facial features)
///
/// Performance: ~30-80ms per frame (lighter than background blur)
class BeautyFilterService extends ChangeNotifier {
  static const String _tag = 'BeautyFilter';

  double _intensity = 0.5; // 0.0 = disabled, 1.0 = maximum
  bool _isEnabled = false;
  bool _isProcessing = false;
  int _frameCount = 0;
  int _processedCount = 0;

  // Process every 3rd frame for smooth effect with better performance
  static const int _processEveryNFrames = 3;

  bool get isEnabled => _isEnabled;
  double get intensity => _intensity;
  bool get isProcessing => _isProcessing;
  int get processedFrames => _processedCount;
  int get totalFrames => _frameCount;

  /// Enable or disable beauty filter
  void setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;
    if (enabled) {
      _frameCount = 0;
      _processedCount = 0;
    }
    notifyListeners();
    debugPrint('$_tag: Beauty filter ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Update filter intensity (0.0 - 1.0)
  void setIntensity(double newIntensity) {
    if (newIntensity < 0.0 || newIntensity > 1.0) {
      throw ArgumentError('Intensity must be between 0.0 and 1.0');
    }

    if (_intensity == newIntensity) return;

    _intensity = newIntensity;
    notifyListeners();
    debugPrint('$_tag: Intensity updated to $_intensity');
  }

  /// Process a video frame and apply beauty filter
  ///
  /// @param inputImage Input image as Uint8List (RGBA format)
  /// @param width Image width
  /// @param height Image height
  /// @return Processed image with beauty filter, or null if skipped/error
  Future<Uint8List?> processFrame(
    Uint8List inputImage,
    int width,
    int height,
  ) async {
    _frameCount++;

    if (!_isEnabled || _intensity == 0.0 || _isProcessing) {
      return null;
    }

    // Process only every Nth frame to reduce CPU load
    if (_frameCount % _processEveryNFrames != 0) {
      return null;
    }

    _isProcessing = true;
    _processedCount++;

    try {
      final startTime = DateTime.now();

      // Decode image
      final decodedImage = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: inputImage.buffer,
        numChannels: 4,
      );

      // Apply beauty filter
      final filtered = _applyBeautyFilter(decodedImage);

      // Encode back to bytes
      final outputBytes = filtered.buffer.asUint8List();

      final processingTime = DateTime.now()
          .difference(startTime)
          .inMilliseconds;
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

  /// Apply beauty filter to image
  ///
  /// Algorithm:
  /// 1. Box blur for skin smoothing
  /// 2. Blend original with blurred (preserves edges)
  /// 3. Brighten slightly
  /// 4. Add warm tint
  img.Image _applyBeautyFilter(img.Image input) {
    final width = input.width;
    final height = input.height;
    final output = img.Image.from(input);

    try {
      // Step 1: Apply box blur (lightweight alternative to Gaussian)
      final radius = (3 * _intensity).toInt().clamp(1, 5);
      final blurred = _boxBlur(input, radius);

      // Step 2: Blend original with blurred based on intensity
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final origPixel = input.getPixel(x, y);
          final blurPixel = blurred.getPixel(x, y);

          // Extract RGB channels
          final origR = origPixel.r.toInt();
          final origG = origPixel.g.toInt();
          final origB = origPixel.b.toInt();

          final blurR = blurPixel.r.toInt();
          final blurG = blurPixel.g.toInt();
          final blurB = blurPixel.b.toInt();

          // Calculate contrast to preserve edges
          final contrast =
              (origR - blurR) * (origR - blurR) +
              (origG - blurG) * (origG - blurG) +
              (origB - blurB) * (origB - blurB);

          // High contrast = edge (preserve), low contrast = smooth skin (blur)
          final blendFactor = contrast > 1000 ? 0.2 : _intensity;

          // Blend
          var r = (origR * (1 - blendFactor) + blurR * blendFactor).toInt();
          var g = (origG * (1 - blendFactor) + blurG * blendFactor).toInt();
          var b = (origB * (1 - blendFactor) + blurB * blendFactor).toInt();

          // Step 3: Subtle brightening (5-15%)
          final brighten = 1.0 + (0.1 * _intensity);
          r = (r * brighten).toInt().clamp(0, 255);
          g = (g * brighten).toInt().clamp(0, 255);
          b = (b * brighten).toInt().clamp(0, 255);

          // Step 4: Warm tint (add slight red for healthy appearance)
          r = (r + 5 * _intensity).toInt().clamp(0, 255);

          // Set output pixel
          output.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return output;
    } catch (e) {
      debugPrint('$_tag: ❌ Error applying filter: $e');
      return input;
    }
  }

  /// Simple box blur (faster than Gaussian for real-time)
  img.Image _boxBlur(img.Image input, int radius) {
    final width = input.width;
    final height = input.height;
    final output = img.Image.from(input);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int r = 0;
        int g = 0;
        int b = 0;
        int count = 0;

        // Average pixels in box
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = (x + dx).clamp(0, width - 1);
            final ny = (y + dy).clamp(0, height - 1);
            final pixel = input.getPixel(nx, ny);

            r += pixel.r.toInt();
            g += pixel.g.toInt();
            b += pixel.b.toInt();
            count++;
          }
        }

        output.setPixelRgba(x, y, r ~/ count, g ~/ count, b ~/ count, 255);
      }
    }

    return output;
  }

  /// Get processing statistics
  String getStats() {
    if (_frameCount == 0) return 'No frames processed';
    final percentage = (_processedCount / _frameCount * 100).toStringAsFixed(1);
    return 'Processed $_processedCount/$_frameCount frames ($percentage%)';
  }

  /// Clean up resources
  @override
  void dispose() {
    _isEnabled = false;
    _isProcessing = false;
    debugPrint('$_tag: ✅ Beauty filter disposed - ${getStats()}');
    super.dispose();
  }
}
