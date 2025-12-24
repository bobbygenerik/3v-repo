// MediaPipe settings removed. Keep empty stub to avoid breaking references.
class MediaPipeSettings {
  // No-op: MediaPipe has been removed for Safari PWA stability.
  bool get shouldProcess => false;
  void addListener(Function() _) {}
  void removeListener(Function() _) {}
  void update({
    bool? backgroundBlur,
    bool? beauty,
    bool? faceMesh,
    bool? faceDetection,
    double? blurIntensity,
  }) {}
}
