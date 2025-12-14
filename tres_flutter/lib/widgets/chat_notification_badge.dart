import 'package:flutter/material.dart';

class ChatNotificationBadge extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onTap;
  final bool hasNewMessage;

  const ChatNotificationBadge({
    super.key,
    required this.unreadCount,
    required this.onTap,
    this.hasNewMessage = false,
  });

  @override
  State<ChatNotificationBadge> createState() => _ChatNotificationBadgeState();
}

class _ChatNotificationBadgeState extends State<ChatNotificationBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void didUpdateWidget(ChatNotificationBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Trigger pulse animation on new message
    if (widget.hasNewMessage && !oldWidget.hasNewMessage) {
      _pulseController.forward().then((_) {
        _pulseController.reverse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.hasNewMessage ? _pulseAnimation.value : 1.0,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Chat icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: widget.unreadCount > 0 
                        ? Colors.blue 
                        : Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.chat_bubble,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                
                // Unread count badge
                if (widget.unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      child: Center(
                        child: Text(
                          widget.unreadCount > 99 ? '99+' : widget.unreadCount.toString(),
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
                
                // New message indicator (pulsing dot)
                if (widget.hasNewMessage)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
}