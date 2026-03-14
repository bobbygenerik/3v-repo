import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CallControlsBar extends StatelessWidget {
  const CallControlsBar({
    super.key,
    required this.buttonSlideAnimations,
    required this.chatOverlayVisible,
    required this.unreadMessageCount,
    required this.hasNewMessage,
    required this.isMicrophoneEnabled,
    required this.isCameraEnabled,
    required this.onToggleChat,
    required this.onShowMore,
    required this.onToggleMicrophone,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.onEndCall,
  });

  final List<Animation<Offset>> buttonSlideAnimations;
  final bool chatOverlayVisible;
  final int unreadMessageCount;
  final bool hasNewMessage;
  final bool isMicrophoneEnabled;
  final bool isCameraEnabled;

  final VoidCallback onToggleChat;
  final VoidCallback onShowMore;
  final VoidCallback onToggleMicrophone;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEndCall;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonSize = screenWidth < 400 ? 44.0 : 50.0;
    final centerButtonSize = screenWidth < 400 ? 52.0 : 60.0;
    final buttonSpacing = screenWidth < 400 ? 2.0 : 6.0;
    final dividerMargin = screenWidth < 400 ? 8.0 : 14.0;

    final buttons = [
      _AnimatedControlButton(
        animation: buttonSlideAnimations[0],
        icon: chatOverlayVisible ? Icons.forum : Icons.forum_outlined,
        onPressed: onToggleChat,
        onLongPress: onShowMore,
        gradientColors: chatOverlayVisible
            ? const [Color(0xFF7AA2FF), Color(0xFF58D8C0)]
            : hasNewMessage
                ? const [Color(0xFFF9738A), Color(0xFFF43F5E)]
                : const [Color(0xFF6073AE), Color(0xFF47537A)],
        borderColor:
            chatOverlayVisible ? const Color(0x80CDE7FF) : const Color(0x4DFFFFFF),
        badge: unreadMessageCount > 0
            ? (unreadMessageCount > 99 ? '99+' : unreadMessageCount.toString())
            : null,
        size: buttonSize,
        spacing: buttonSpacing,
        tooltip: chatOverlayVisible
            ? 'Hide chat tray (long press: more options)'
            : 'Open chat tray (long press: more options)',
      ),
      _AnimatedControlButton(
        animation: buttonSlideAnimations[1],
        icon: isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
        onPressed: onToggleMicrophone,
        size: buttonSize,
        spacing: buttonSpacing,
        tooltip: isMicrophoneEnabled ? 'Mute microphone' : 'Unmute microphone',
      ),
      _AnimatedControlButton(
        animation: buttonSlideAnimations[2],
        icon: Icons.call_end,
        onPressed: onEndCall,
        backgroundColor: Colors.red.shade600,
        size: centerButtonSize,
        spacing: buttonSpacing,
        tooltip: 'End call',
      ),
      _AnimatedControlButton(
        animation: buttonSlideAnimations[3],
        icon: isCameraEnabled ? Icons.videocam : Icons.videocam_off,
        onPressed: onToggleCamera,
        size: buttonSize,
        spacing: buttonSpacing,
        tooltip: isCameraEnabled ? 'Turn camera off' : 'Turn camera on',
      ),
      _AnimatedControlButton(
        animation: buttonSlideAnimations[4],
        icon: Icons.cameraswitch,
        onPressed: onSwitchCamera,
        size: buttonSize,
        spacing: buttonSpacing,
        tooltip: 'Switch camera',
      ),
      _AnimatedControlButton(
        animation: buttonSlideAnimations[5],
        icon: Icons.more_horiz,
        onPressed: onShowMore,
        size: buttonSize,
        spacing: buttonSpacing,
        tooltip: 'More options',
      ),
    ];

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: SizedBox(
          width: screenWidth * 0.9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          buttons[1],
                          buttons[3],
                          buttons[0],
                          buttons[4],
                          buttons[5],
                        ],
                      ),
                      Container(
                        height: 28,
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.12),
                        margin: EdgeInsets.symmetric(horizontal: dividerMargin),
                      ),
                      buttons[2],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedControlButton extends StatelessWidget {
  const _AnimatedControlButton({
    required this.animation,
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.spacing,
    required this.tooltip,
    this.onLongPress,
    this.backgroundColor = Colors.transparent,
    this.gradientColors,
    this.borderColor,
    this.badge,
  });

  final Animation<Offset> animation;
  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final Color backgroundColor;
  final List<Color>? gradientColors;
  final Color? borderColor;
  final double size;
  final double spacing;
  final String tooltip;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: animation,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: spacing),
        child: Tooltip(
          message: tooltip,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  onLongPress: onLongPress,
                  customBorder: const CircleBorder(),
                  splashColor: Colors.white.withValues(alpha: 0.3),
                  highlightColor: Colors.white.withValues(alpha: 0.1),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: gradientColors == null && backgroundColor == Colors.transparent
                          ? Colors.white.withValues(alpha: 0.08)
                          : null,
                      gradient: gradientColors != null
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: gradientColors!,
                            )
                          : backgroundColor != Colors.transparent
                              ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.red.shade400,
                                    Colors.red.shade700,
                                  ],
                                )
                              : null,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: borderColor ?? Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: size * 0.45,
                    ),
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Center(
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
