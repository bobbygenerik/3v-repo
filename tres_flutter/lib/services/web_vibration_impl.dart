import 'dart:js' as js;

// Web implementation using dart:js
void webVibrate(List<int> pattern) {
  try {
    js.context.callMethod('eval', [
      'if (navigator.vibrate) navigator.vibrate([${pattern.join(",")}])',
    ]);
  } catch (e) {
    // Vibration not supported or blocked
  }
}
