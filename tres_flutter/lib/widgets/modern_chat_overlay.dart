import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/chat_service.dart' as chat;
import '../services/vibration_service.dart';

enum ChatOverlayState { hidden, preview, expanded }

class ModernChatOverlay extends StatefulWidget {
  final List<chat.ChatMessage> messages;
  final ValueChanged<String> onSendMessage;
  final ValueChanged<bool>? onExpandedChanged;
  final bool isExpanded;
  final int unreadCount;
  final bool hasNewMessage;

  const ModernChatOverlay({
    super.key,
    required this.messages,
    required this.onSendMessage,
    this.onExpandedChanged,
    this.isExpanded = false,
    this.unreadCount = 0,
    this.hasNewMessage = false,
  });

  @override
  State<ModernChatOverlay> createState() => _ModernChatOverlayState();
}

class _ModernChatOverlayState extends State<ModernChatOverlay>
    with TickerProviderStateMixin {
  ChatOverlayState _state = ChatOverlayState.hidden;
  Timer? _autoHideTimer;
  late final AnimationController _sheetController;
  late final AnimationController _fadeController;
  late final AnimationController _previewPulseController;
  late final Animation<Offset> _sheetAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _previewPulseAnimation;
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  double _dragDeltaY = 0;

  @override
  void initState() {
    super.initState();

    _sheetController = AnimationController(
      duration: const Duration(milliseconds: 360),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _previewPulseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _sheetAnimation = Tween<Offset>(
      begin: const Offset(0, 1.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _sheetController,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
    _previewPulseAnimation = Tween<double>(
      begin: 0.985,
      end: 1.015,
    ).animate(CurvedAnimation(
      parent: _previewPulseController,
      curve: Curves.easeInOut,
    ));

    if (widget.isExpanded) {
      _state = ChatOverlayState.expanded;
      _sheetController.value = 1;
      _fadeController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant ModernChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.messages.length > oldWidget.messages.length) {
      final latestMessage = widget.messages.last;
      if (!latestMessage.isLocal && _state == ChatOverlayState.hidden) {
        _showPreview();
      }
    }

    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _showExpanded(notifyParent: false);
      } else if (_state == ChatOverlayState.expanded) {
        _hide(notifyParent: false);
      }
    }

    if (widget.hasNewMessage && _state == ChatOverlayState.preview) {
      _previewPulseController
        ..stop()
        ..repeat(reverse: true);
    } else if (!widget.hasNewMessage && !_messageFocus.hasFocus) {
      _previewPulseController
        ..stop()
        ..value = 0;
    }
  }

  void _showPreview() {
    if (_state == ChatOverlayState.expanded) {
      return;
    }

    VibrationService.vibrateNewMessage();
    _cancelAutoHideTimer();

    setState(() {
      _state = ChatOverlayState.preview;
    });

    _sheetController.forward();
    _fadeController.forward();
    _previewPulseController
      ..stop()
      ..repeat(reverse: true);
    _autoHideTimer = Timer(const Duration(seconds: 6), () {
      if (_state == ChatOverlayState.preview) {
        _hide(notifyParent: false);
      }
    });
  }

  void _showExpanded({bool notifyParent = true}) {
    _cancelAutoHideTimer();

    setState(() {
      _state = ChatOverlayState.expanded;
    });

    _previewPulseController
      ..stop()
      ..value = 0;
    _sheetController.forward();
    _fadeController.forward();
    if (notifyParent) {
      widget.onExpandedChanged?.call(true);
    }
    _messageFocus.requestFocus();
  }

  void _hide({bool notifyParent = true}) {
    _cancelAutoHideTimer();

    setState(() {
      _state = ChatOverlayState.hidden;
    });

    _previewPulseController
      ..stop()
      ..value = 0;
    _sheetController.reverse();
    _fadeController.reverse();
    _messageFocus.unfocus();
    if (notifyParent) {
      widget.onExpandedChanged?.call(false);
    }
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
  }

  void _onTrayVerticalDragUpdate(DragUpdateDetails details) {
    _dragDeltaY += details.delta.dy;
  }

  void _onTrayVerticalDragEnd(DragEndDetails details) {
    const expandThreshold = -36.0;
    const collapseThreshold = 44.0;
    final velocity = details.primaryVelocity ?? 0;

    if (_state == ChatOverlayState.preview) {
      if (_dragDeltaY < expandThreshold || velocity < -420) {
        _showExpanded();
      } else if (_dragDeltaY > collapseThreshold || velocity > 520) {
        _hide(notifyParent: false);
      }
    } else if (_state == ChatOverlayState.expanded) {
      if (_dragDeltaY > collapseThreshold || velocity > 420) {
        _hide();
      }
    }

    _dragDeltaY = 0;
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }
    widget.onSendMessage(text);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_state == ChatOverlayState.hidden) {
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final trayHeight = _state == ChatOverlayState.expanded
        ? mediaQuery.size.height * 0.58
        : mediaQuery.size.height * 0.24;

    return Stack(
      children: [
        if (_state == ChatOverlayState.expanded)
          Positioned.fill(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hide,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12 + keyboardInset,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _sheetAnimation,
              child: GestureDetector(
                onVerticalDragUpdate: _onTrayVerticalDragUpdate,
                onVerticalDragEnd: _onTrayVerticalDragEnd,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  height: trayHeight,
                  child: _state == ChatOverlayState.preview
                      ? _buildPreviewMode()
                      : _buildExpandedMode(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewMode() {
    final recentMessages = widget.messages
        .where((message) => !message.isLocal)
        .toList()
        .reversed
        .take(2)
        .toList();

    return GestureDetector(
      onTap: _toggleExpanded,
      child: ScaleTransition(
        scale: _previewPulseAnimation,
        child: _buildTrayShell(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHandle(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF89A8FF).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        color: Color(0xFFB8CBFF),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.unreadCount > 1
                                ? '${widget.unreadCount} new messages'
                                : 'New message',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Tap to open chat and reply',
                            style: TextStyle(
                              color: Color(0xB3E4E9FF),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0x1FFB7185),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x4DFB7185)),
                        ),
                        child: Text(
                          widget.unreadCount > 99
                              ? '99+'
                              : widget.unreadCount.toString(),
                          style: const TextStyle(
                            color: Color(0xFFFFD3DA),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: recentMessages.isEmpty
                      ? const Center(
                          child: Text(
                            'Messages will appear here during the call.',
                            style: TextStyle(
                              color: Color(0xB3E4E9FF),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : Column(
                          children: recentMessages
                              .map(_buildPreviewMessage)
                              .toList(growable: false),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewMessage(chat.ChatMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x16FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7AA2FF), Color(0xFF5DE1C3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                message.senderName.isNotEmpty
                    ? message.senderName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        message.senderName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      message.getFormattedTime(),
                      style: const TextStyle(
                        color: Color(0x80FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.message.length > 88
                      ? '${message.message.substring(0, 88)}...'
                      : message.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xDDEFF2FF),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedMode(BuildContext context) {
    return _buildTrayShell(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            child: Column(
              children: [
                _buildHandle(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFB8CBFF).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        color: Color(0xFFE7EDFF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Call chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.messages.isEmpty
                                ? 'No messages yet'
                                : '${widget.messages.length} messages in this call',
                            style: const TextStyle(
                              color: Color(0xB3E4E9FF),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFFE4E9FF),
                        size: 28,
                      ),
                      onPressed: _hide,
                      tooltip: 'Minimize chat',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Messages sent during the call show up here. Use this for quick notes, links, and coordination without leaving video.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xB3E4E9FF),
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    reverse: true,
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) {
                      final reversedIndex = widget.messages.length - 1 - index;
                      final message = widget.messages[reversedIndex];
                      final nextMessage = reversedIndex < widget.messages.length - 1
                          ? widget.messages[reversedIndex + 1]
                          : null;
                      final showSender = nextMessage == null ||
                          nextMessage.senderId != message.senderId ||
                          nextMessage.isLocal != message.isLocal;
                      return _buildExpandedMessage(context, message, showSender);
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x1EFFFFFF)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocus,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Message everyone in the call',
                        hintStyle: TextStyle(color: Color(0x99FFFFFF)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF7AA2FF), Color(0xFF58D8C0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: _sendMessage,
                        tooltip: 'Send message',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedMessage(
    BuildContext context,
    chat.ChatMessage message,
    bool showSender,
  ) {
    return Align(
      alignment: message.isLocal ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: showSender ? 12 : 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Column(
          crossAxisAlignment:
              message.isLocal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showSender && !message.isLocal)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 6),
                child: Text(
                  message.senderName,
                  style: const TextStyle(
                    color: Color(0xB3E4E9FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: message.isLocal
                    ? const LinearGradient(
                        colors: [Color(0xFF7AA2FF), Color(0xFF58D8C0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: message.isLocal ? null : const Color(0x16FFFFFF),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(message.isLocal ? 20 : 8),
                  bottomRight: Radius.circular(message.isLocal ? 8 : 20),
                ),
                border: message.isLocal
                    ? null
                    : Border.all(color: const Color(0x1EFFFFFF)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.getFormattedTime(),
                      style: TextStyle(
                        color: message.isLocal
                            ? const Color(0xDDF6FFFA)
                            : const Color(0x80FFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0x66FFFFFF),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _buildTrayShell({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xE61B2236), Color(0xE6141826)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: const Color(0x22FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: ColoredBox(
          color: const Color(0x12000000),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelAutoHideTimer();
    _sheetController.dispose();
    _fadeController.dispose();
    _previewPulseController.dispose();
    _messageController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }
}
