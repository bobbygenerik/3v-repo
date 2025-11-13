import 'dart:ui' show Size, Offset;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// AR filter types matching Android implementation
enum ARFilterType {
  none,
  glasses,      // Sunglasses 🕶️
  hat,          // Top hat 🎩
  mask,         // Face mask 😷
  bunnyEars,    // Bunny ears 🐰
  catEars,      // Cat ears 🐱
  crown,        // Crown 👑
  monocle,      // Monocle 🧐
  piratePatch,  // Pirate eye patch 🏴‍☠️
  santaHat,     // Santa hat 🎅
  sparkles,     // Sparkles overlay ✨
}

/// AR Filters service for video calls
/// 
/// Features:
/// - Face detection and landmark tracking with ML Kit
/// - 11 AR filters (glasses, hats, masks, accessories)
/// - Real-time effect application
/// - Performance optimization
/// 
/// Note: This is a simplified Flutter implementation.
/// For production, consider using ARKit (iOS) or ARCore (Android).
class ARFiltersService extends ChangeNotifier {
  static const String _tag = 'ARFilters';

  FaceDetector? _faceDetector;
  bool _isInitialized = false;
  ARFilterType _currentFilter = ARFilterType.none;
  double _intensity = 1.0;
  bool _isProcessing = false;
  
  List<Face> _detectedFaces = [];
  int _framesProcessed = 0;

  bool get isInitialized => _isInitialized;
  ARFilterType get currentFilter => _currentFilter;
  double get intensity => _intensity;
  bool get isProcessing => _isProcessing;
  List<Face> get detectedFaces => List.unmodifiable(_detectedFaces);
  int get framesProcessed => _framesProcessed;

  /// Initialize AR face detection
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize ML Kit Face Detector
      // ACCURATE mode for better landmark detection
      final options = FaceDetectorOptions(
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.15,
        performanceMode: FaceDetectorMode.accurate,
      );

      _faceDetector = FaceDetector(options: options);
      _isInitialized = true;

      debugPrint('$_tag: ✅ AR filters initialized');
    } catch (e) {
      debugPrint('$_tag: ❌ Failed to initialize: $e');
      rethrow;
    }
  }

  /// Apply AR filter
  void applyFilter(ARFilterType filter, {double? intensity}) {
    _currentFilter = filter;
    if (intensity != null) {
      _intensity = intensity.clamp(0.0, 1.0);
    }
    notifyListeners();
    debugPrint('$_tag: Applied filter: $filter (intensity: $_intensity)');
  }

  /// Set filter intensity
  void setIntensity(double newIntensity) {
    _intensity = newIntensity.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Process a video frame and apply AR filter
  /// 
  /// @param inputImage Input image as Uint8List (RGBA format)
  /// @param width Image width
  /// @param height Image height
  /// @return Processed image with AR filter, or null if filter is disabled
  Future<Uint8List?> processFrame(
    Uint8List inputImage,
    int width,
    int height,
  ) async {
    if (!_isInitialized || _currentFilter == ARFilterType.none || _isProcessing) {
      return null;
    }

    _isProcessing = true;

    try {
      final startTime = DateTime.now();

      // Step 1: Detect faces with ML Kit
      final inputImageForML = InputImage.fromBytes(
        bytes: inputImage,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: width * 4,
        ),
      );

      final faces = await _faceDetector!.processImage(inputImageForML);
      _detectedFaces = faces;
      _framesProcessed++;

      if (faces.isEmpty) {
        _isProcessing = false;
        return null; // No face detected, no filter to apply
      }

      // Step 2: Decode image
      final decodedImage = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: inputImage.buffer,
        numChannels: 4,
      );

      // Step 3: Draw AR filter overlays
      final filtered = _drawFilterOnImage(decodedImage, faces);

      // Step 4: Encode back to bytes
      final outputBytes = filtered.buffer.asUint8List();

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

  /// Draw AR filter overlays on image based on detected faces
  img.Image _drawFilterOnImage(img.Image image, List<Face> faces) {
    final output = img.Image.from(image);

    for (final face in faces) {
      switch (_currentFilter) {
        case ARFilterType.glasses:
          _drawGlasses(output, face);
          break;
        case ARFilterType.hat:
          _drawHat(output, face);
          break;
        case ARFilterType.mask:
          _drawMask(output, face);
          break;
        case ARFilterType.bunnyEars:
          _drawBunnyEars(output, face);
          break;
        case ARFilterType.catEars:
          _drawCatEars(output, face);
          break;
        case ARFilterType.crown:
          _drawCrown(output, face);
          break;
        case ARFilterType.monocle:
          _drawMonocle(output, face);
          break;
        case ARFilterType.piratePatch:
          _drawPiratePatch(output, face);
          break;
        case ARFilterType.santaHat:
          _drawSantaHat(output, face);
          break;
        case ARFilterType.sparkles:
          _drawSparkles(output, face);
          break;
        case ARFilterType.none:
          break;
      }
    }

    return output;
  }

  /// Draw sunglasses filter
  void _drawGlasses(img.Image image, Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    
    if (leftEye == null || rightEye == null) return;

    final eyeDistance = (rightEye.position.x - leftEye.position.x).abs().toDouble();
    final glassesWidth = (eyeDistance * 0.6).toInt();

    // Draw left lens
    img.fillCircle(
      image,
      x: leftEye.position.x,
      y: leftEye.position.y,
      radius: glassesWidth ~/ 2,
      color: img.ColorRgba8(0, 0, 0, (200 * _intensity).toInt()),
    );

    // Draw right lens
    img.fillCircle(
      image,
      x: rightEye.position.x,
      y: rightEye.position.y,
      radius: glassesWidth ~/ 2,
      color: img.ColorRgba8(0, 0, 0, (200 * _intensity).toInt()),
    );

    // Draw bridge
    img.drawLine(
      image,
      x1: leftEye.position.x + glassesWidth ~/ 2,
      y1: leftEye.position.y,
      x2: rightEye.position.x - glassesWidth ~/ 2,
      y2: rightEye.position.y,
      color: img.ColorRgb8(0, 0, 0),
      thickness: 3,
    );
  }

  /// Draw top hat filter
  void _drawHat(img.Image image, Face face) {
    final bbox = face.boundingBox;
    final hatWidth = (bbox.width * 0.8).toInt();
    final hatHeight = (bbox.height * 0.4).toInt();
    final hatX = (bbox.center.dx - hatWidth / 2).toInt();
    final hatY = (bbox.top - hatHeight).toInt();

    // Draw hat brim
    img.fillRect(
      image,
      x1: hatX - 20,
      y1: hatY + hatHeight - 10,
      x2: hatX + hatWidth + 20,
      y2: hatY + hatHeight + 5,
      color: img.ColorRgba8(50, 50, 50, (255 * _intensity).toInt()),
    );

    // Draw hat crown
    img.fillRect(
      image,
      x1: hatX,
      y1: hatY,
      x2: hatX + hatWidth,
      y2: hatY + hatHeight,
      color: img.ColorRgba8(30, 30, 30, (255 * _intensity).toInt()),
    );
  }

  /// Draw face mask filter
  void _drawMask(img.Image image, Face face) {
    final nose = face.landmarks[FaceLandmarkType.noseBase];
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth];
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth];

    if (nose == null || leftMouth == null || rightMouth == null) return;

    final maskWidth = ((rightMouth.position.x - leftMouth.position.x).toDouble() * 1.5).toInt();
    final maskHeight = (maskWidth * 0.6).toInt();
    final maskX = (nose.position.x - maskWidth / 2).toInt();
    final maskY = nose.position.y;

    // Draw light blue surgical mask
    img.fillRect(
      image,
      x1: maskX,
      y1: maskY,
      x2: maskX + maskWidth,
      y2: maskY + maskHeight,
      color: img.ColorRgba8(173, 216, 230, (220 * _intensity).toInt()),
    );

    // Draw mask pleats (lines)
    for (int i = 1; i <= 3; i++) {
      final lineY = maskY + (maskHeight * i / 4).toInt();
      img.drawLine(
        image,
        x1: maskX,
        y1: lineY,
        x2: maskX + maskWidth,
        y2: lineY,
        color: img.ColorRgba8(150, 180, 200, (150 * _intensity).toInt()),
      );
    }
  }

  /// Draw bunny ears filter
  void _drawBunnyEars(img.Image image, Face face) {
    final bbox = face.boundingBox;
    final earHeight = (bbox.height * 0.5).toInt();
    final earWidth = (bbox.width * 0.15).toInt();

    // Left ear
    img.fillRect(
      image,
      x1: (bbox.left + bbox.width * 0.2).toInt(),
      y1: (bbox.top - earHeight).toInt(),
      x2: (bbox.left + bbox.width * 0.2 + earWidth).toInt(),
      y2: bbox.top.toInt(),
      color: img.ColorRgba8(255, 192, 203, (230 * _intensity).toInt()),
    );

    // Right ear
    img.fillRect(
      image,
      x1: (bbox.right - bbox.width * 0.2 - earWidth).toInt(),
      y1: (bbox.top - earHeight).toInt(),
      x2: (bbox.right - bbox.width * 0.2).toInt(),
      y2: bbox.top.toInt(),
      color: img.ColorRgba8(255, 192, 203, (230 * _intensity).toInt()),
    );
  }

  /// Draw cat ears filter
  void _drawCatEars(img.Image image, Face face) {
    final bbox = face.boundingBox;
    final earSize = (bbox.width * 0.15).toInt();

    // Left ear (triangle)
    for (int y = 0; y < earSize; y++) {
      final lineWidth = (y * 0.8).toInt();
      img.drawLine(
        image,
        x1: (bbox.left + bbox.width * 0.25 - lineWidth / 2).toInt(),
        y1: (bbox.top - earSize + y).toInt(),
        x2: (bbox.left + bbox.width * 0.25 + lineWidth / 2).toInt(),
        y2: (bbox.top - earSize + y).toInt(),
        color: img.ColorRgba8(255, 140, 0, (230 * _intensity).toInt()),
        thickness: 2,
      );
    }

    // Right ear (triangle)
    for (int y = 0; y < earSize; y++) {
      final lineWidth = (y * 0.8).toInt();
      img.drawLine(
        image,
        x1: (bbox.right - bbox.width * 0.25 - lineWidth / 2).toInt(),
        y1: (bbox.top - earSize + y).toInt(),
        x2: (bbox.right - bbox.width * 0.25 + lineWidth / 2).toInt(),
        y2: (bbox.top - earSize + y).toInt(),
        color: img.ColorRgba8(255, 140, 0, (230 * _intensity).toInt()),
        thickness: 2,
      );
    }
  }

  /// Draw crown filter
  void _drawCrown(img.Image image, Face face) {
    final bbox = face.boundingBox;
    final crownWidth = (bbox.width * 0.7).toInt();
    final crownHeight = (bbox.height * 0.25).toInt();
    final crownX = (bbox.center.dx - crownWidth / 2).toInt();
    final crownY = (bbox.top - crownHeight).toInt();

    // Draw gold crown base
    img.fillRect(
      image,
      x1: crownX,
      y1: crownY + crownHeight - 15,
      x2: crownX + crownWidth,
      y2: crownY + crownHeight,
      color: img.ColorRgba8(255, 215, 0, (240 * _intensity).toInt()),
    );

    // Draw crown points
    for (int i = 0; i < 5; i++) {
      final pointX = crownX + (crownWidth * i / 4).toInt();
      final pointHeight = i % 2 == 0 ? 20 : 10;
      img.fillRect(
        image,
        x1: pointX - 10,
        y1: crownY + crownHeight - 15 - pointHeight,
        x2: pointX + 10,
        y2: crownY + crownHeight - 15,
        color: img.ColorRgba8(255, 215, 0, (240 * _intensity).toInt()),
      );
    }
  }

  /// Draw monocle filter
  void _drawMonocle(img.Image image, Face face) {
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    if (rightEye == null) return;

    final monocleRadius = 30;

    // Draw outer circle (gold frame)
    img.drawCircle(
      image,
      x: rightEye.position.x,
      y: rightEye.position.y,
      radius: monocleRadius,
      color: img.ColorRgba8(255, 215, 0, (255 * _intensity).toInt()),
    );

    // Draw inner circle (glass)
    img.drawCircle(
      image,
      x: rightEye.position.x,
      y: rightEye.position.y,
      radius: monocleRadius - 3,
      color: img.ColorRgba8(200, 200, 255, (100 * _intensity).toInt()),
    );
  }

  /// Draw pirate eye patch filter
  void _drawPiratePatch(img.Image image, Face face) {
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    if (rightEye == null) return;

    final patchRadius = 35;

    // Draw black eye patch
    img.fillCircle(
      image,
      x: rightEye.position.x,
      y: rightEye.position.y,
      radius: patchRadius,
      color: img.ColorRgba8(20, 20, 20, (240 * _intensity).toInt()),
    );
  }

  /// Draw Santa hat filter
  void _drawSantaHat(img.Image image, Face face) {
    final bbox = face.boundingBox;
    final hatWidth = (bbox.width * 0.8).toInt();
    final hatHeight = (bbox.height * 0.5).toInt();
    final hatX = (bbox.left + bbox.width / 2 - hatWidth / 2).toInt();
    final hatY = (bbox.top - hatHeight).toInt();

    // Draw red hat
    for (int y = 0; y < hatHeight - 15; y++) {
      final lineWidth = (hatWidth * (1 - y / hatHeight)).toInt();
      img.drawLine(
        image,
        x1: (bbox.left + bbox.width / 2 - lineWidth / 2).toInt(),
        y1: hatY + y,
        x2: (bbox.left + bbox.width / 2 + lineWidth / 2).toInt(),
        y2: hatY + y,
        color: img.ColorRgba8(220, 20, 60, (240 * _intensity).toInt()),
        thickness: 2,
      );
    }

    // Draw white trim
    img.fillRect(
      image,
      x1: hatX - 10,
      y1: bbox.top.toInt() - 20,
      x2: hatX + hatWidth + 10,
      y2: bbox.top.toInt() - 10,
      color: img.ColorRgba8(255, 255, 255, (255 * _intensity).toInt()),
    );

    // Draw white pom-pom
    img.fillCircle(
      image,
      x: (bbox.left + bbox.width / 2).toInt(),
      y: hatY,
      radius: 15,
      color: img.ColorRgba8(255, 255, 255, (255 * _intensity).toInt()),
    );
  }

  /// Draw sparkles overlay filter
  void _drawSparkles(img.Image image, Face face) {
    final bbox = face.boundingBox;
    
    // Draw multiple sparkles around the face
    final sparkles = [
      Offset(bbox.left.toDouble() - 20, bbox.top.toDouble()),
      Offset(bbox.right.toDouble() + 20, bbox.top.toDouble()),
      Offset((bbox.left + bbox.width / 2).toDouble(), bbox.top.toDouble() - 30),
      Offset(bbox.left.toDouble(), (bbox.top + bbox.height / 2).toDouble()),
      Offset(bbox.right.toDouble(), (bbox.top + bbox.height / 2).toDouble()),
    ];

    for (final pos in sparkles) {
      // Draw star shape (simplified as cross)
      img.drawLine(
        image,
        x1: pos.dx.toInt() - 15,
        y1: pos.dy.toInt(),
        x2: pos.dx.toInt() + 15,
        y2: pos.dy.toInt(),
        color: img.ColorRgba8(255, 255, 0, (220 * _intensity).toInt()),
        thickness: 3,
      );
      img.drawLine(
        image,
        x1: pos.dx.toInt(),
        y1: pos.dy.toInt() - 15,
        x2: pos.dx.toInt(),
        y2: pos.dy.toInt() + 15,
        color: img.ColorRgba8(255, 255, 0, (220 * _intensity).toInt()),
        thickness: 3,
      );
    }
  }

  /// Get filter display name
  static String getFilterName(ARFilterType filter) {
    switch (filter) {
      case ARFilterType.none:
        return 'None';
      case ARFilterType.glasses:
        return 'Glasses 🕶️';
      case ARFilterType.hat:
        return 'Hat 🎩';
      case ARFilterType.mask:
        return 'Mask 😷';
      case ARFilterType.bunnyEars:
        return 'Bunny Ears 🐰';
      case ARFilterType.catEars:
        return 'Cat Ears 🐱';
      case ARFilterType.crown:
        return 'Crown 👑';
      case ARFilterType.monocle:
        return 'Monocle 🧐';
      case ARFilterType.piratePatch:
        return 'Pirate Patch 🏴‍☠️';
      case ARFilterType.santaHat:
        return 'Santa Hat 🎅';
      case ARFilterType.sparkles:
        return 'Sparkles ✨';
    }
  }

  /// Clean up resources
  @override
  Future<void> dispose() async {
    try {
      await _faceDetector?.close();
      _faceDetector = null;
      _isInitialized = false;
      debugPrint('$_tag: ✅ AR filters disposed (processed $_framesProcessed frames)');
    } catch (e) {
      debugPrint('$_tag: ❌ Error disposing: $e');
    }
    super.dispose();
  }
}
