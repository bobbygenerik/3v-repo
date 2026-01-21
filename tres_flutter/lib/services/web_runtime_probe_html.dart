// Web implementation for runtime capability probes.
import 'dart:html' as html;

bool webHasSetParameters() {
  try {
    final rtcsender = (html.window as dynamic).RTCRtpSender;
    if (rtcsender == null) return false;
    final proto = (rtcsender as dynamic).prototype;
    final setParams = proto != null ? (proto as dynamic).setParameters : null;
    return setParams != null;
  } catch (e) {
    return false;
  }
}

bool webHasSimulcast() {
  try {
    final ua = (html.window.navigator.userAgent ?? '').toString().toLowerCase();
    final isSafari = ua.contains('safari') && !ua.contains('chrome') && !ua.contains('crios') && !ua.contains('android');
    return webHasSetParameters() && !isSafari;
  } catch (e) {
    return false;
  }

}
