import 'package:flutter/foundation.dart';

class CallUiStateController extends ChangeNotifier {
  bool controlsVisible = true;
  bool reactionsVisible = false;
  bool chatOverlayVisible = false;
  int unreadMessageCount = 0;
  bool hasNewMessage = false;

  void setControlsVisible(bool visible) {
    if (controlsVisible == visible) return;
    controlsVisible = visible;
    notifyListeners();
  }

  void toggleControlsVisible() {
    controlsVisible = !controlsVisible;
    notifyListeners();
  }

  void setReactionsVisible(bool visible) {
    if (reactionsVisible == visible) return;
    reactionsVisible = visible;
    notifyListeners();
  }

  void toggleReactionsVisible() {
    reactionsVisible = !reactionsVisible;
    notifyListeners();
  }

  void setChatOverlayExpanded(bool expanded) {
    chatOverlayVisible = expanded;
    controlsVisible = !expanded;
    if (expanded) {
      unreadMessageCount = 0;
      hasNewMessage = false;
    }
    notifyListeners();
  }

  void markSentMessage() {
    if (!hasNewMessage) return;
    hasNewMessage = false;
    notifyListeners();
  }

  void registerRemoteMessage({required bool chatOpen}) {
    hasNewMessage = true;
    if (!chatOpen) {
      unreadMessageCount += 1;
    }
    notifyListeners();
  }

  void clearUnread() {
    final changed = unreadMessageCount != 0 || hasNewMessage;
    unreadMessageCount = 0;
    hasNewMessage = false;
    if (changed) {
      notifyListeners();
    }
  }
}
