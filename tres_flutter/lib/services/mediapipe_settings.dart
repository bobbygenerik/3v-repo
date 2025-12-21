import 'package:flutter/foundation.dart';

class MediaPipeSettings extends ChangeNotifier {
  bool backgroundBlurEnabled = false;
  bool beautyEnabled = false;
  bool faceMeshEnabled = false;
  bool faceDetectionEnabled = false;
  double blurIntensity = 70.0;

  bool get shouldProcess =>
      backgroundBlurEnabled || beautyEnabled || faceMeshEnabled || faceDetectionEnabled;

  void update({
    bool? backgroundBlur,
    bool? beauty,
    bool? faceMesh,
    bool? faceDetection,
    double? blurIntensity,
  }) {
    var changed = false;

    if (backgroundBlur != null && backgroundBlur != backgroundBlurEnabled) {
      backgroundBlurEnabled = backgroundBlur;
      changed = true;
    }
    if (beauty != null && beauty != beautyEnabled) {
      beautyEnabled = beauty;
      changed = true;
    }
    if (faceMesh != null && faceMesh != faceMeshEnabled) {
      faceMeshEnabled = faceMesh;
      changed = true;
    }
    if (faceDetection != null && faceDetection != faceDetectionEnabled) {
      faceDetectionEnabled = faceDetection;
      changed = true;
    }
    if (blurIntensity != null && blurIntensity != this.blurIntensity) {
      this.blurIntensity = blurIntensity;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }
}
