import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// Reaction types enum
enum ReactionType {
  heart('❤️'),
  laugh('😂'),
  clap('👏'),
  party('🎉'),
  surprised('😮'),
  thumbsUp('👍');

  final String emoji;
  const ReactionType(this.emoji);

  static ReactionType? fromString(String name) {
    return ReactionType.values.where((type) => type.name == name).firstOrNull;
  }
}

/// Reaction data class
class Reaction {
  final String id;
  final ReactionType type;
  final String senderId;
  final String senderName;
  final DateTime timestamp;

  Reaction({
    String? id,
    required this.type,
    required this.senderId,
    required this.senderName,
    DateTime? timestamp,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
       timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'type': 'reaction',
    'id': id,
    'reaction': type.name,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory Reaction.fromJson(
    Map<String, dynamic> json,
    Participant? participant,
  ) {
    final reactionType = ReactionType.fromString(json['reaction'] ?? '');
    return Reaction(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: reactionType ?? ReactionType.heart,
      senderId: participant?.sid ?? 'unknown',
      senderName: participant?.name ?? 'Unknown',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

/// Quick emoji reactions with animated floating overlays
/// Mirrors functionality from Android ReactionManager.kt
class ReactionService extends ChangeNotifier {
  static const String _messageTypeReaction = 'reaction';
  static const int _animationDurationMs = 2500;
  static const int _maxConcurrentReactions = 10;

  Room? _room;
  EventsListener<RoomEvent>? _roomListener;

  final List<Reaction> _activeReactions = [];
  List<Reaction> get activeReactions => List.unmodifiable(_activeReactions);

  /// Initialize reaction service with LiveKit room
  void initialize(Room room) {
    _room = room;
    _setupDataChannelListener();
    debugPrint('ReactionService initialized');
  }

  /// Setup LiveKit DataChannel listener for incoming reactions
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
      debugPrint('Reaction DataChannel listener setup complete');
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

      if (messageType == _messageTypeReaction) {
        final reaction = Reaction.fromJson(json, participant);
        _handleReceivedReaction(reaction);
      }
    } catch (e) {
      debugPrint('❌ Failed to parse reaction data: $e');
    }
  }

  /// Send a reaction to all participants
  Future<bool> sendReaction(ReactionType type) async {
    if (_room == null || _room!.localParticipant == null) {
      debugPrint('❌ Cannot send reaction: room or localParticipant is null');
      return false;
    }

    try {
      final reaction = Reaction(
        type: type,
        senderId: _room!.localParticipant!.sid,
        senderName: _room!.localParticipant!.name,
      );

      // Create JSON payload
      final data = utf8.encode(jsonEncode(reaction.toJson()));

      // Send via DataChannel
      await _room!.localParticipant!.publishData(data);

      // Add to active reactions for UI display
      _addReaction(reaction);

      debugPrint('✅ Sent reaction: ${type.emoji}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to send reaction: $e');
      return false;
    }
  }

  /// Handle received reaction
  void _handleReceivedReaction(Reaction reaction) {
    _addReaction(reaction);
    debugPrint(
      '📬 Received reaction from ${reaction.senderName}: ${reaction.type.emoji}',
    );
  }

  /// Add reaction to active list
  void _addReaction(Reaction reaction) {
    // Limit concurrent reactions
    if (_activeReactions.length >= _maxConcurrentReactions) {
      _activeReactions.removeAt(0);
    }

    _activeReactions.add(reaction);
    notifyListeners();

    // Auto-remove after animation duration
    Future.delayed(Duration(milliseconds: _animationDurationMs), () {
      _activeReactions.remove(reaction);
      notifyListeners();
    });
  }

  /// Get all available reaction types
  List<ReactionType> getAvailableReactions() => ReactionType.values.toList();

  /// Clear all active reactions
  void clearAllReactions() {
    _activeReactions.clear();
    notifyListeners();
    debugPrint('🗑️ Cleared all reactions');
  }

  /// Clean up resources
  void cleanup() {
    _roomListener?.dispose();
    _roomListener = null;
    _room = null;
    _activeReactions.clear();
    debugPrint('🧹 ReactionService cleaned up');
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}

/// Animated reaction overlay widget
/// Displays floating emoji animations
class ReactionOverlay extends StatelessWidget {
  final List<Reaction> reactions;

  const ReactionOverlay({super.key, required this.reactions});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: reactions
          .map((reaction) => _ReactionWidget(reaction: reaction))
          .toList(),
    );
  }
}

/// Individual animated reaction widget
class _ReactionWidget extends StatefulWidget {
  final Reaction reaction;

  const _ReactionWidget({required this.reaction});

  @override
  State<_ReactionWidget> createState() => _ReactionWidgetState();
}

class _ReactionWidgetState extends State<_ReactionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _moveYAnimation;
  late Animation<double> _moveXAnimation;
  late Animation<double> _scaleAnimation;

  late double _startX;
  late double _endX;

  @override
  void initState() {
    super.initState();

    // Generate random horizontal positions
    final random = Random();
    _startX = 0.25 + random.nextDouble() * 0.5; // 25% to 75% of screen width
    _endX =
        _startX +
        (random.nextDouble() - 0.5) * 0.3; // Drift up to 15% left/right

    // Create animation controller
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Fade animation (fade in, stay visible, fade out)
    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_controller);

    // Move upward animation
    _moveYAnimation = Tween<double>(
      begin: 1.0,
      end: 0.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Horizontal drift animation
    _moveXAnimation = Tween<double>(
      begin: _startX,
      end: _endX,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Scale animation (grow then shrink)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.8), weight: 50),
    ]).animate(_controller);

    // Start animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left:
              _moveXAnimation.value * size.width -
              24, // Center emoji (48px / 2)
          top: _moveYAnimation.value * size.height - 24,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Text(
                widget.reaction.type.emoji,
                style: const TextStyle(fontSize: 48),
              ),
            ),
          ),
        );
      },
    );
  }
}
