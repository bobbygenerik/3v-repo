import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// Layout modes for video grid
enum LayoutMode {
  grid,       // Gallery view (all participants in grid)
  spotlight,  // Active speaker full screen
  pinned,     // Pinned participant full screen
  sidebar;    // Active speaker with sidebar thumbnails

  String get label {
    switch (this) {
      case LayoutMode.grid:
        return 'Grid View';
      case LayoutMode.spotlight:
        return 'Spotlight';
      case LayoutMode.pinned:
        return 'Pinned';
      case LayoutMode.sidebar:
        return 'Sidebar';
    }
  }

  String get description {
    switch (this) {
      case LayoutMode.grid:
        return 'All participants in equal-sized tiles';
      case LayoutMode.spotlight:
        return 'Active speaker takes full screen';
      case LayoutMode.pinned:
        return 'Selected participant takes full screen';
      case LayoutMode.sidebar:
        return 'Active speaker with sidebar thumbnails';
    }
  }
}

/// Participant tile configuration
class ParticipantTile {
  final Participant participant;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool isActive;
  final bool isPinned;
  final bool isLocal;

  const ParticipantTile({
    required this.participant,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.isActive = false,
    this.isPinned = false,
    this.isLocal = false,
  });

  ParticipantTile copyWith({
    Participant? participant,
    double? x,
    double? y,
    double? width,
    double? height,
    bool? isActive,
    bool? isPinned,
    bool? isLocal,
  }) {
    return ParticipantTile(
      participant: participant ?? this.participant,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      isActive: isActive ?? this.isActive,
      isPinned: isPinned ?? this.isPinned,
      isLocal: isLocal ?? this.isLocal,
    );
  }
}

/// Grid Layout Manager
/// 
/// Manages video participant layout and positioning for video calls.
/// 
/// Features:
/// - Multiple layout modes (grid, spotlight, pinned, sidebar)
/// - Dynamic participant positioning
/// - Active speaker detection
/// - Pinned participant support
/// - Responsive grid calculations
/// 
/// Usage:
/// ```dart
/// final layoutManager = GridLayoutManager();
/// layoutManager.initialize(room);
/// 
/// // Set layout mode
/// layoutManager.setLayoutMode(LayoutMode.spotlight);
/// 
/// // Pin a participant
/// layoutManager.pinParticipant(participant);
/// 
/// // Get tile positions
/// final tiles = layoutManager.getTiles(
///   containerWidth: 1920,
///   containerHeight: 1080,
/// );
/// ```
class GridLayoutManager extends ChangeNotifier {
  static const String _tag = 'GridLayout';

  Room? _room;
  LayoutMode _layoutMode = LayoutMode.grid;
  Participant? _pinnedParticipant;
  Participant? _activeSpeaker;
  List<Participant> _participants = [];

  LayoutMode get layoutMode => _layoutMode;
  Participant? get pinnedParticipant => _pinnedParticipant;
  Participant? get activeSpeaker => _activeSpeaker;
  List<Participant> get participants => List.unmodifiable(_participants);
  int get participantCount => _participants.length;

  /// Initialize layout manager
  Future<void> initialize(Room room) async {
    _room = room;
    _updateParticipants();
    
    // Listen to room events
    _room!.addListener(_onRoomChanged);
    
    debugPrint('$_tag: Manager initialized with ${_participants.length} participants');
  }

  /// Handle room changes
  void _onRoomChanged() {
    _updateParticipants();
    notifyListeners();
  }

  /// Update participants list
  void _updateParticipants() {
    if (_room == null) return;

    _participants = [
      if (_room!.localParticipant != null) _room!.localParticipant!,
      ..._room!.remoteParticipants.values,
    ];

    // Update active speaker (would come from LiveKit events in production)
    // For now, just use the first remote participant
    if (_room!.remoteParticipants.isNotEmpty) {
      _activeSpeaker = _room!.remoteParticipants.values.first;
    }

    debugPrint('$_tag: Updated participants: ${_participants.length}');
  }

  /// Set layout mode
  void setLayoutMode(LayoutMode mode) {
    if (_layoutMode == mode) return;
    
    _layoutMode = mode;
    debugPrint('$_tag: Layout mode changed to ${mode.label}');
    notifyListeners();
  }

  /// Pin a participant
  void pinParticipant(Participant? participant) {
    _pinnedParticipant = participant;
    
    if (participant != null) {
      debugPrint('$_tag: Pinned participant: ${participant.identity}');
      // Auto-switch to pinned layout
      setLayoutMode(LayoutMode.pinned);
    } else {
      debugPrint('$_tag: Unpinned participant');
    }
    
    notifyListeners();
  }

  /// Unpin current participant
  void unpinParticipant() {
    pinParticipant(null);
  }

  /// Toggle pin for a participant
  void togglePinParticipant(Participant participant) {
    if (_pinnedParticipant == participant) {
      unpinParticipant();
    } else {
      pinParticipant(participant);
    }
  }

  /// Set active speaker (called from LiveKit events)
  void setActiveSpeaker(Participant? participant) {
    if (_activeSpeaker == participant) return;
    
    _activeSpeaker = participant;
    debugPrint('$_tag: Active speaker: ${participant?.identity ?? "none"}');
    notifyListeners();
  }

  /// Get participant tiles based on current layout
  List<ParticipantTile> getTiles({
    required double containerWidth,
    required double containerHeight,
  }) {
    if (_participants.isEmpty) {
      return [];
    }

    switch (_layoutMode) {
      case LayoutMode.grid:
        return _calculateGridLayout(containerWidth, containerHeight);
      case LayoutMode.spotlight:
        return _calculateSpotlightLayout(containerWidth, containerHeight);
      case LayoutMode.pinned:
        return _calculatePinnedLayout(containerWidth, containerHeight);
      case LayoutMode.sidebar:
        return _calculateSidebarLayout(containerWidth, containerHeight);
    }
  }

  /// Calculate grid layout (equal-sized tiles)
  List<ParticipantTile> _calculateGridLayout(double width, double height) {
    final count = _participants.length;
    
    // Calculate optimal grid dimensions
    final cols = _calculateOptimalColumns(count, width / height);
    final rows = (count / cols).ceil();

    final tileWidth = width / cols;
    final tileHeight = height / rows;

    final tiles = <ParticipantTile>[];
    
    for (var i = 0; i < count; i++) {
      final row = i ~/ cols;
      final col = i % cols;
      
      tiles.add(ParticipantTile(
        participant: _participants[i],
        x: col * tileWidth,
        y: row * tileHeight,
        width: tileWidth,
        height: tileHeight,
        isActive: _participants[i] == _activeSpeaker,
        isLocal: _participants[i] == _room?.localParticipant,
      ));
    }

    return tiles;
  }

  /// Calculate spotlight layout (active speaker full screen)
  List<ParticipantTile> _calculateSpotlightLayout(double width, double height) {
    final spotlight = _activeSpeaker ?? _participants.first;
    
    return [
      ParticipantTile(
        participant: spotlight,
        x: 0,
        y: 0,
        width: width,
        height: height,
        isActive: true,
        isLocal: spotlight == _room?.localParticipant,
      ),
    ];
  }

  /// Calculate pinned layout (pinned participant full screen)
  List<ParticipantTile> _calculatePinnedLayout(double width, double height) {
    final pinned = _pinnedParticipant ?? _participants.first;
    
    return [
      ParticipantTile(
        participant: pinned,
        x: 0,
        y: 0,
        width: width,
        height: height,
        isPinned: true,
        isLocal: pinned == _room?.localParticipant,
      ),
    ];
  }

  /// Calculate sidebar layout (main + thumbnails)
  List<ParticipantTile> _calculateSidebarLayout(double width, double height) {
    final tiles = <ParticipantTile>[];
    final mainParticipant = _activeSpeaker ?? _participants.first;
    final others = _participants.where((p) => p != mainParticipant).toList();

    // Main participant takes 75% width
    const mainWidthRatio = 0.75;
    final mainWidth = width * mainWidthRatio;
    final sidebarWidth = width - mainWidth;

    // Add main tile
    tiles.add(ParticipantTile(
      participant: mainParticipant,
      x: 0,
      y: 0,
      width: mainWidth,
      height: height,
      isActive: true,
      isLocal: mainParticipant == _room?.localParticipant,
    ));

    // Add sidebar thumbnails
    if (others.isNotEmpty) {
      final thumbnailHeight = height / others.length;
      
      for (var i = 0; i < others.length; i++) {
        tiles.add(ParticipantTile(
          participant: others[i],
          x: mainWidth,
          y: i * thumbnailHeight,
          width: sidebarWidth,
          height: thumbnailHeight,
          isLocal: others[i] == _room?.localParticipant,
        ));
      }
    }

    return tiles;
  }

  /// Calculate optimal number of columns for grid layout
  int _calculateOptimalColumns(int count, double aspectRatio) {
    if (count <= 1) return 1;
    if (count == 2) return 2;
    if (count <= 4) return 2;
    if (count <= 6) return 3;
    if (count <= 9) return 3;
    if (count <= 12) return 4;
    return (count / 3).ceil();
  }

  /// Get participant by identity
  Participant? getParticipantByIdentity(String identity) {
    try {
      return _participants.firstWhere((p) => p.identity == identity);
    } catch (e) {
      return null;
    }
  }

  /// Check if participant is visible in current layout
  bool isParticipantVisible(Participant participant) {
    final tiles = getTiles(containerWidth: 1920, containerHeight: 1080);
    return tiles.any((tile) => tile.participant == participant);
  }

  /// Get layout statistics
  Map<String, dynamic> getStats() {
    return {
      'layoutMode': _layoutMode.label,
      'participantCount': participantCount,
      'hasPinnedParticipant': _pinnedParticipant != null,
      'hasActiveSpeaker': _activeSpeaker != null,
      'pinnedParticipant': _pinnedParticipant?.identity,
      'activeSpeaker': _activeSpeaker?.identity,
    };
  }

  /// Clean up resources
  Future<void> cleanup() async {
    debugPrint('$_tag: Cleaning up...');
    
    _room?.removeListener(_onRoomChanged);
    _room = null;
    _participants = [];
    _pinnedParticipant = null;
    _activeSpeaker = null;
    
    debugPrint('$_tag: ✅ Cleaned up');
  }

  @override
  void dispose() {
    cleanup(); // Fire and forget
    super.dispose();
  }
}
