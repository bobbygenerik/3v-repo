// Web implementation for small utility functions
import 'dart:html' as html;

String webUserAgent() => html.window.navigator.userAgent;

bool webMatchMediaStandalone() {
  try {
    final mm = html.window.matchMedia('(display-mode: standalone)');
    return mm.matches;
  } catch (_) {
    return false;
  }
}

bool webNavigatorStandalone() {
  try {
    final nav = html.window.navigator;
    final asDynamic = nav as dynamic;
    return (asDynamic.standalone == true);
  } catch (_) {
    return false;
  }
}
