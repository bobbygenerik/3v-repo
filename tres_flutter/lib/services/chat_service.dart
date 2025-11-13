import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:intl/intl.dart';

/// Chat message data class
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;
  final bool isLocal;

  ChatMessage({
    String? id,
    required this.senderId,
    required this.senderName,
    required this.message,
    DateTime? timestamp,
    this.isLocal = false,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now();

  String getFormattedTime() {
    return DateFormat('HH:mm').format(timestamp);
  }

  Map<String, dynamic> toJson() => {
        'type': 'chat',
        'id': id,
        'message': message,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json, Participant? participant) {
    return ChatMessage(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: participant?.sid ?? 'unknown',
      senderName: participant?.name ?? 'Unknown',
      message: json['message'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isLocal: false,
    );
  }
}

/// Typing indicator data class
class TypingIndicator {
  final String userId;
  final String userName;
  final DateTime timestamp;

  TypingIndicator({
    required this.userId,
    required this.userName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// In-call chat manager for real-time text messaging
/// Mirrors functionality from Android InCallChatManager.kt
class ChatService extends ChangeNotifier {
  static const String _messageTypeChat = 'chat';
  static const String _messageTypeTyping = 'typing';
  static const String _messageTypeTypingStop = 'typing_stop';
  static const int _typingTimeoutMs = 3000;
  static const int _maxHistorySize = 100;

  Room? _room;
  final List<ChatMessage> _messageHistory = [];
  final Map<String, TypingIndicator> _typingUsers = {};
  final Map<String, Timer> _typingTimeoutTimers = {};

  DateTime _lastReadTimestamp = DateTime.now();
  EventsListener<RoomEvent>? _roomListener;

  List<ChatMessage> get messageHistory => List.unmodifiable(_messageHistory);
  List<TypingIndicator> get typingUsers => _typingUsers.values.toList();
  int get messageCount => _messageHistory.length;

  /// Initialize chat service with LiveKit room
  void initialize(Room room) {
    _room = room;
    _setupDataChannelListener();
    debugPrint('ChatService initialized for room: ${room.name}');
  }

  /// Setup LiveKit DataChannel listener for incoming messages
  void _setupDataChannelListener() {
    if (_room == null) return;

    try {
      _roomListener = _room!.createListener();
      _roomListener!.on<DataReceivedEvent>((event) {
        final data = event.data is Uint8List 
            ? event.data as Uint8List 
            : Uint8List.fromList(event.data);
        _handleIncomingData(data, event.participant);
      });
      debugPrint('DataChannel listener setup complete');
    } catch (e) {
      debugPrint('❌ Failed to setup DataChannel listener: $e');
    }
  }

  /// Handle incoming data from DataChannel
  void _handleIncomingData(Uint8List data, Participant? participant) {
    try {
      final jsonString = utf8.decode(data);
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final messageType = json['type'] ?? '';

      switch (messageType) {
        case _messageTypeChat:
          final message = ChatMessage.fromJson(json, participant);
          _handleReceivedMessage(message);
          break;

        case _messageTypeTyping:
          if (participant != null) {
            final indicator = TypingIndicator(
              userId: participant.sid,
              userName: participant.name ?? 'Unknown',
            );
            _handleTypingIndicator(indicator);
          }
          break;

        case _messageTypeTypingStop:
          if (participant != null) {
            _removeTypingIndicator(participant.sid);
          }
          break;

        default:
          debugPrint('⚠️ Unknown message type: $messageType');
      }
    } catch (e) {
      debugPrint('❌ Failed to parse incoming data: $e');
    }
  }

  /// Send a chat message to all participants
  Future<bool> sendMessage(String text) async {
    if (text.trim().isEmpty) {
      debugPrint('⚠️ Attempted to send blank message');
      return false;
    }

    if (_room == null || _room!.localParticipant == null) {
      debugPrint('❌ Cannot send message: room or localParticipant is null');
      return false;
    }

    try {
      final message = ChatMessage(
        senderId: _room!.localParticipant!.sid ?? 'local',
        senderName: _room!.localParticipant!.name ?? 'You',
        message: text.trim(),
        isLocal: true,
      );

      // Create JSON payload
      final data = utf8.encode(jsonEncode(message.toJson()));

      // Send via DataChannel to all participants
      await _room!.localParticipant!.publishData(data);

      // Add to local history
      _addMessageToHistory(message);
      notifyListeners();

      // Stop typing indicator for local user
      await sendTypingStop();

      debugPrint('✅ Sent message: ${message.message}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to send message: $e');
      return false;
    }
  }

  /// Send typing indicator to other participants
  Future<void> sendTypingIndicator() async {
    if (_room == null || _room!.localParticipant == null) return;

    try {
      final json = {
        'type': _messageTypeTyping,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final data = utf8.encode(jsonEncode(json));
      await _room!.localParticipant!.publishData(data);

      debugPrint('Sent typing indicator');
    } catch (e) {
      debugPrint('❌ Failed to send typing indicator: $e');
    }
  }

  /// Send typing stop indicator
  Future<void> sendTypingStop() async {
    if (_room == null || _room!.localParticipant == null) return;

    try {
      final json = {
        'type': _messageTypeTypingStop,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final data = utf8.encode(jsonEncode(json));
      await _room!.localParticipant!.publishData(data);

      debugPrint('Sent typing stop indicator');
    } catch (e) {
      debugPrint('❌ Failed to send typing stop indicator: $e');
    }
  }

  /// Handle received message
  void _handleReceivedMessage(ChatMessage message) {
    _addMessageToHistory(message);
    notifyListeners();
    debugPrint('📬 Received message from ${message.senderName}: ${message.message}');
  }

  /// Handle typing indicator
  void _handleTypingIndicator(TypingIndicator indicator) {
    _typingUsers[indicator.userId] = indicator;
    notifyListeners();

    // Cancel existing timeout timer for this user
    _typingTimeoutTimers[indicator.userId]?.cancel();

    // Schedule automatic removal after timeout
    _typingTimeoutTimers[indicator.userId] = Timer(
      const Duration(milliseconds: _typingTimeoutMs),
      () => _removeTypingIndicator(indicator.userId),
    );

    debugPrint('⌨️ ${indicator.userName} is typing');
  }

  /// Remove typing indicator for a user
  void _removeTypingIndicator(String userId) {
    if (_typingUsers.remove(userId) != null) {
      _typingTimeoutTimers[userId]?.cancel();
      _typingTimeoutTimers.remove(userId);
      notifyListeners();
      debugPrint('🛑 Removed typing indicator for user: $userId');
    }
  }

  /// Add message to history with size limit
  void _addMessageToHistory(ChatMessage message) {
    _messageHistory.add(message);

    // Trim history if too large
    if (_messageHistory.length > _maxHistorySize) {
      final removeCount = _messageHistory.length - _maxHistorySize;
      _messageHistory.removeRange(0, removeCount);
      debugPrint('🧹 Trimmed message history, removed $removeCount old messages');
    }
  }

  /// Clear all messages
  void clearHistory() {
    _messageHistory.clear();
    notifyListeners();
    debugPrint('🗑️ Cleared message history');
  }

  /// Get unread message count
  int getUnreadCount() {
    return _messageHistory
        .where((msg) =>
            msg.timestamp.isAfter(_lastReadTimestamp) && !msg.isLocal)
        .length;
  }

  /// Mark all messages as read
  void markAllAsRead() {
    _lastReadTimestamp = DateTime.now();
    notifyListeners();
    debugPrint('✅ Marked all messages as read');
  }

  /// Clean up resources
  void cleanup() {
    _roomListener?.dispose();
    _roomListener = null;

    for (var timer in _typingTimeoutTimers.values) {
      timer.cancel();
    }
    _typingTimeoutTimers.clear();
    _typingUsers.clear();

    _room = null;
    debugPrint('🧹 ChatService cleaned up');
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
