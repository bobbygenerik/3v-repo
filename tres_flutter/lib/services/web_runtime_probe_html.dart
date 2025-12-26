// Web implementation for runtime capability probes.
import 'dart:html' as html;
import 'dart:js_util' as js_util;

bool webHasSetParameters() {
  try {
    final rtcsender = js_util.getProperty(html.window, 'RTCRtpSender');
    if (rtcsender == null) return false;
    final proto = js_util.getProperty(rtcsender, 'prototype');
    final setParams = proto != null ? js_util.getProperty(proto, 'setParameters') : null;
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
