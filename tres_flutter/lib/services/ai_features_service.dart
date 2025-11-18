import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';

/// AI Features service for video calls
/// Combines multiple AI capabilities for enhanced video experience
class AIFeaturesService extends ChangeNotifier {
  FaceDetector? _faceDetector;
  bool _isInitialized = false;
  bool _autoFramingEnabled = false;
  bool _eyeContactCorrectionEnabled = false;
  
  // Face tracking state
  List<Face> _detectedFaces = [];
  Rect? _optimalFraming;
  
  bool get isInitialized => _isInitialized;
  bool get autoFramingEnabled => _autoFramingEnabled;
  bool get eyeContactEnabled => _eyeContactCorrectionEnabled;
  List<Face> get detectedFaces => _detectedFaces;
  Rect? get optimalFraming => _optimalFraming;
  
  /// Initialize AI features
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
          enableClassification: true,
          enableTracking: true,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
      _isInitialized = true;
      debugPrint('🤖 AI Features initialized');
    } catch (e) {
      debugPrint('❌ AI Features init failed: $e');
    }
  }
  
  /// Enable/disable auto-framing (keeps face centered)
  void setAutoFraming(bool enabled) {
    _autoFramingEnabled = enabled;
    notifyListeners();
    debugPrint('🎯 Auto-framing: ${enabled ? 'ON' : 'OFF'}');
  }
  
  /// Enable/disable eye contact correction
  void setEyeContactCorrection(bool enabled) {
    _eyeContactCorrectionEnabled = enabled;
    notifyListeners();
    debugPrint('👁️ Eye contact correction: ${enabled ? 'ON' : 'OFF'}');
  }
  
  /// Process camera image for AI features
  Future<void> processImage(CameraImage image) async {
    if (!_isInitialized || _faceDetector == null) return;
    
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;
      
      _detectedFaces = await _faceDetector!.processImage(inputImage);
      
      if (_autoFramingEnabled && _detectedFaces.isNotEmpty) {
        _calculateOptimalFraming();
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ AI processing error: $e');
    }
  }
  
  /// Calculate optimal camera framing based on detected faces
  void _calculateOptimalFraming() {
    if (_detectedFaces.isEmpty) return;
    
    // Find bounding box that includes all faces
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = 0;
    double maxY = 0;
    
    for (final face in _detectedFaces) {
      final bounds = face.boundingBox;
      minX = minX < bounds.left ? minX : bounds.left;
      minY = minY < bounds.top ? minY : bounds.top;
      maxX = maxX > bounds.right ? maxX : bounds.right;
      maxY = maxY > bounds.bottom ? maxY : bounds.bottom;
    }
    
    // Add padding around faces
    const padding = 50.0;
    _optimalFraming = Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }
  
  /// Convert CameraImage to InputImage for ML Kit
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('❌ Camera image conversion failed: $e');
      return null;
    }
  }
  
  /// Get AI insights for current frame
  Map<String, dynamic> getAIInsights() {
    return {
      'facesDetected': _detectedFaces.length,
      'autoFramingActive': _autoFramingEnabled && _optimalFraming != null,
      'eyeContactActive': _eyeContactCorrectionEnabled,
      'recommendations': _getRecommendations(),
    };
  }
  
  /// Get AI-powered recommendations for better video quality
  List<String> _getRecommendations() {
    final recommendations = <String>[];
    
    if (_detectedFaces.isEmpty) {
      recommendations.add('Move closer to camera for better face detection');
    } else if (_detectedFaces.length > 1) {
      recommendations.add('Multiple faces detected - consider individual calls');
    }
    
    // Check face positioning
    for (final face in _detectedFaces) {
      if (face.headEulerAngleY != null && face.headEulerAngleY!.abs() > 30) {
        recommendations.add('Face camera directly for better eye contact');
      }
      
      if (face.leftEyeOpenProbability != null && 
          face.rightEyeOpenProbability != null) {
        final avgEyeOpen = (face.leftEyeOpenProbability! + face.rightEyeOpenProbability!) / 2;
        if (avgEyeOpen < 0.5) {
          recommendations.add('Keep eyes open and look at camera');
        }
      }
    }
    
    return recommendations;
  }
  
  @override
  Future<void> dispose() async {
    await _faceDetector?.close();
    _isInitialized = false;
    super.dispose();
  }
}