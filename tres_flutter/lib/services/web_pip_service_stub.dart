/// Stub for non-web platforms
class WebPipService {
  bool get isPipSupported => false;
  bool get isPipActive => false;
  
  void setAutoEnterPip(bool enabled) {}
  void updateStream(dynamic stream) {}
  Future<bool> enterPip() async => false;
  Future<void> exitPip() async {}
  void setupAutoEnterPip() {}
  void dispose() {}
}
