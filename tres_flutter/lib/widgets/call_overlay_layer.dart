import 'package:flutter/material.dart';
import 'call_status_overlays.dart';

class CallOverlayLayer extends StatelessWidget {
  final bool isReconnecting;
  final bool hasIncomingCall;
  final Widget? callWaitingBanner;
  final bool qualityDashboardVisible;
  final Widget? qualityDashboard;
  final bool translationVisible;
  final double translationBottom;
  final String translatedText;
  final VoidCallback onCloseTranslation;

  const CallOverlayLayer({
    super.key,
    required this.isReconnecting,
    required this.hasIncomingCall,
    this.callWaitingBanner,
    required this.qualityDashboardVisible,
    this.qualityDashboard,
    required this.translationVisible,
    required this.translationBottom,
    required this.translatedText,
    required this.onCloseTranslation,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (isReconnecting)
          const Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: ReconnectingBadge(),
          ),

        if (hasIncomingCall && callWaitingBanner != null)
          Positioned(
            top: 80,
            left: 16,
            right: 16,
            child: callWaitingBanner!,
          ),

        if (qualityDashboardVisible && qualityDashboard != null)
          Positioned(
            top: 100,
            right: 16,
            child: qualityDashboard!,
          ),

        if (translationVisible)
          Positioned(
            bottom: translationBottom,
            left: 16,
            right: 16,
            child: TranslationOverlay(
              text: translatedText,
              onClose: onCloseTranslation,
            ),
          ),
      ],
    );
  }
}
