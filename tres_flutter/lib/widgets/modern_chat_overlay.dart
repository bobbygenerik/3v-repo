import 'package:flutter/material.dart';
import 'dart:async';
import '../services/chat_service.dart' as chat;
import '../services/vibration_service.dart';

enum ChatOverlayState { hidden, preview, expanded }

class ModernChatOverlay extends StatefulWidget {
  final List<chat.ChatMessage> messages;
  final Function(String) onSendMessage;
  final VoidCallback? onToggleExpanded;
  final bool isVisible;

  const ModernChatOverlay({
    super.key,
    required this.messages,
    required this.onSendMessage,
    this.onToggleExpanded,
    this.isVisible = false,
  });

  @override
  State<ModernChatOverlay> createState() => _ModernChatOverlayState();
}

class _ModernChatOverlayState extends State<ModernChatOverlay>
    with TickerProviderStateMixin {
  ChatOverlayState _state = ChatOverlayState.hidden;
  Timer? _autoHideTimer;
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  Offset? _overlayPosition;

  @override
  void initState() {
    super.initState();
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0), // Start off-screen right
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void didUpdateWidget(ModernChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check for new messages
    if (widget.messages.length > oldWidget.messages.length) {
      final newMessage = widget.messages.last;
      debugPrint('📬 Chat overlay: New message detected from ${newMessage.senderName}');
      
      if (!newMessage.isLocal && _state == ChatOverlayState.hidden) {
        debugPrint('📬 Auto-showing chat preview for new message');
        _showPreviewForNewMessage(newMessage);
      }
    }
    
    // Handle visibility changes from parent
    if (widget.isVisible != oldWidget.isVisible) {
      debugPrint('📬 Chat visibility changed: ${widget.isVisible}');
      if (widget.isVisible && _state != ChatOverlayState.expanded) {
        _showExpanded();
      } else if (!widget.isVisible && _state != ChatOverlayState.hidden) {
        _hide();
      }
    }
  }

  void _showPreviewForNewMessage(chat.ChatMessage message) {
    if (_state == ChatOverlayState.expanded) return; // Already expanded
    
    // Vibrate for new message
    VibrationService.vibrateNewMessage();
    
    setState(() {
      _state = ChatOverlayState.preview;
    });
    
    _slideController.forward();
    _fadeController.forward();
    
    // Auto-hide after 6 seconds
    _startAutoHideTimer();
  }

  void _showExpanded() {
    _cancelAutoHideTimer();
    
    setState(() {
      _state = ChatOverlayState.expanded;
    });
    
    _slideController.forward();
    _fadeController.forward();
  }

  void _hide() {
    _cancelAutoHideTimer();
    
    setState(() {
      _state = ChatOverlayState.hidden;
    });
    
    _slideController.reverse();
    _fadeController.reverse();
  }

  void _startAutoHideTimer() {
    _cancelAutoHideTimer();
    _autoHideTimer = Timer(const Duration(seconds: 6), () {
      if (_state == ChatOverlayState.preview) {
        _hide();
      }
    });
  }

  void _cancelAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  void _toggleExpanded() {
    if (_state == ChatOverlayState.expanded) {
      _hide();
    } else {
      _showExpanded();
    }
    widget.onToggleExpanded?.call();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      widget.onSendMessage(text);
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == ChatOverlayState.hidden) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final panelSize = _state == ChatOverlayState.expanded
        ? const Size(320, 400)
        : const Size(280, 170);
    final defaultLeft = screenSize.width - panelSize.width - 16;
    final defaultTop = (padding.top + 16).clamp(16, screenSize.height - panelSize.height - 16);
    final initialPosition = Offset(defaultLeft, defaultTop.toDouble());
    final position = _overlayPosition == null
        ? _clampPosition(initialPosition, screenSize, panelSize, padding)
        : _clampPosition(_overlayPosition!, screenSize, panelSize, padding);
    _overlayPosition ??= position;

    return Positioned(
      top: position.dy,
      left: position.dx,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: _state == ChatOverlayState.preview
              ? _buildPreviewMode(screenSize, padding, panelSize)
              : _buildExpandedMode(screenSize, padding, panelSize),
        ),
      ),
    );
  }

  Widget _buildPreviewMode(Size screenSize, EdgeInsets padding, Size panelSize) {
    // Get the most recent non-local messages
    final recentMessages = widget.messages
        .where((m) => !m.isLocal)
        .toList()
        .reversed
        .take(2)
        .toList();
    
    return GestureDetector(
      onPanUpdate: (details) {
        _updatePosition(details.delta, screenSize, padding, panelSize);
      },
      onTap: _toggleExpanded,
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E), // Match app's card color
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3A3A3C)), // Match app's border color
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.chat_bubble, color: Color(0xFF6B7FB8), size: 18), // Use app's primary color
                const SizedBox(width: 8),
                const Text(
                  'New message',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500, // Match app's font weight
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.expand_more,
                  color: const Color(0xFF8E8E93), // Use app's secondary text color
                  size: 18,
                ),
              ],
            ),
            
            if (recentMessages.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...recentMessages.map((message) => _buildPreviewMessage(message)),
            ],
            
            // Tap to expand hint
            const SizedBox(height: 8),
            const Text(
              'Tap to open chat',
              style: TextStyle(
                color: Color(0xFF8E8E93), // Use app's secondary text color
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewMessage(chat.ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender avatar
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF6B7FB8), // Use app's primary color
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                message.senderName.isNotEmpty ? message.senderName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Message content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500, // Match app's font weight
                  ),
                ),
                Text(
                  message.message.length > 50 
                      ? '${message.message.substring(0, 50)}...'
                      : message.message,
                  style: const TextStyle(
                    color: Color(0xFF8E8E93), // Use app's secondary text color
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedMode(Size screenSize, EdgeInsets padding, Size panelSize) {
    return Container(
      width: 320,
      height: 400,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E), // Match app's background color
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A3A3C)), // Match app's border color
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2C2C2E), // Match app's card color
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF3A3A3C), // Match app's border color
                  width: 1,
                ),
              ),
            ),
            child: GestureDetector(
              onPanUpdate: (details) {
                _updatePosition(details.delta, screenSize, padding, panelSize);
              },
              child: Row(
                children: [
                  const Icon(Icons.chat_bubble, color: Color(0xFF6B7FB8), size: 20), // Use app's primary color
                  const SizedBox(width: 8),
                  const Text(
                    'Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500, // Match app's font weight
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8E8E93),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF8E8E93), size: 20), // Use app's secondary color
                    onPressed: _hide,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          ),
          
          // Messages
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              reverse: true,
              itemCount: widget.messages.length,
              itemBuilder: (context, index) {
                final reversedIndex = widget.messages.length - 1 - index;
                final message = widget.messages[reversedIndex];
                return _buildExpandedMessage(message);
              },
            ),
          ),
          
          // Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2C2C2E), // Match app's card color
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border(
                top: BorderSide(
                  color: Color(0xFF3A3A3C), // Match app's border color
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocus,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: Color(0xFF8E8E93)), // Use app's secondary text color
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E), // Match app's background color
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), // Match app's border radius
                        borderSide: const BorderSide(color: Color(0xFF3A3A3C)), // Match app's border color
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3A3A3C)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF6B7FB8)), // Use app's primary color
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF6B7FB8), // Use app's primary color
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: _sendMessage,
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedMessage(chat.ChatMessage message) {
    return Align(
      alignment: message.isLocal ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: message.isLocal 
              ? const Color(0xFF6B7FB8) // Use app's primary color for sent messages
              : const Color(0xFF2C2C2E), // Use app's card color for received messages
          borderRadius: BorderRadius.circular(12), // Match app's border radius
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.isLocal) ...[
              Text(
                message.senderName,
                style: const TextStyle(
                  color: Color(0xFF8E8E93), // Use app's secondary text color
                  fontSize: 12,
                  fontWeight: FontWeight.w500, // Match app's font weight
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message.getFormattedTime(),
              style: TextStyle(
                color: message.isLocal 
                    ? Colors.white.withValues(alpha: 0.7)
                    : const Color(0xFF8E8E93), // Use app's secondary text color for received messages
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelAutoHideTimer();
    _slideController.dispose();
    _fadeController.dispose();
    _messageController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  Offset _clampPosition(
    Offset position,
    Size screenSize,
    Size panelSize,
    EdgeInsets padding,
  ) {
    final minX = 16.0;
    final maxX = (screenSize.width - panelSize.width - 16).clamp(minX, screenSize.width);
    final minY = (padding.top + 16).clamp(16, screenSize.height);
    final maxY = (screenSize.height - panelSize.height - padding.bottom - 16)
        .clamp(minY, screenSize.height);
    final dx = position.dx.clamp(minX, maxX).toDouble();
    final dy = position.dy.clamp(minY, maxY).toDouble();
    return Offset(dx, dy);
  }

  void _updatePosition(
    Offset delta,
    Size screenSize,
    EdgeInsets padding,
    Size panelSize,
  ) {
    setState(() {
      final next = (_overlayPosition ?? const Offset(16, 100)) + delta;
      _overlayPosition = _clampPosition(next, screenSize, panelSize, padding);
    });
  }
}
