import 'package:flutter/material.dart';
import '../services/call_stats_service.dart';

/// Stats Overlay Widget
///
/// Shows real-time call quality statistics in an expandable overlay
class StatsOverlay extends StatefulWidget {
  final CallStatsService statsService;

  const StatsOverlay({super.key, required this.statsService});

  @override
  State<StatsOverlay> createState() => _StatsOverlayState();
}

class _StatsOverlayState extends State<StatsOverlay> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _isExpanded ? _buildExpandedView() : _buildCollapsedView(),
    );
  }

  Widget _buildCollapsedView() {
    final stats = widget.statsService.currentStats;
    final quality = widget.statsService.currentQuality;

    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getQualityColor(quality).withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getQualityIcon(quality), color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              quality.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '• ${stats.roundTripTimeFormatted}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedView() {
    final stats = widget.statsService.currentStats;
    final quality = widget.statsService.currentQuality;

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _getQualityColor(quality), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _getQualityIcon(quality),
                color: _getQualityColor(quality),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Call Quality: ${quality.label}',
                style: TextStyle(
                  color: _getQualityColor(quality),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: () => setState(() => _isExpanded = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 24),

          // Video Stats
          _buildSectionHeader('Video'),
          const SizedBox(height: 8),
          _buildStatRow('Resolution', stats.videoResolution),
          _buildStatRow('FPS', '${stats.videoFps}'),
          _buildStatRow('Send', stats.videoSendBitrateFormatted),
          _buildStatRow('Receive', stats.videoRecvBitrateFormatted),
          _buildStatRow(
            'Packet Loss',
            stats.videoPacketLossFormatted,
            warning: stats.videoPacketLoss > 2,
          ),

          const SizedBox(height: 12),

          // Audio Stats
          _buildSectionHeader('Audio'),
          const SizedBox(height: 8),
          _buildStatRow('Send', stats.audioSendBitrateFormatted),
          _buildStatRow('Receive', stats.audioRecvBitrateFormatted),
          _buildStatRow(
            'Packet Loss',
            stats.audioPacketLossFormatted,
            warning: stats.audioPacketLoss > 2,
          ),

          const SizedBox(height: 12),

          // Network Stats
          _buildSectionHeader('Network'),
          const SizedBox(height: 8),
          _buildStatRow(
            'RTT',
            stats.roundTripTimeFormatted,
            warning: stats.roundTripTime > 0.15,
          ), // > 150ms
          _buildStatRow(
            'Jitter',
            stats.jitterFormatted,
            warning: stats.jitter > 0.005,
          ), // > 5ms

          const SizedBox(height: 12),

          // Quality Score
          _buildQualityBar(quality.score),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {bool warning = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          Row(
            children: [
              if (warning)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 14,
                  ),
                ),
              Text(
                value,
                style: TextStyle(
                  color: warning ? Colors.orange : Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQualityBar(int score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Quality Score',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$score/100',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation(
              _getQualityColor(widget.statsService.currentQuality),
            ),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Color _getQualityColor(CallConnectionQuality quality) {
    switch (quality) {
      case CallConnectionQuality.excellent:
        return Colors.green;
      case CallConnectionQuality.good:
        return Colors.lightGreen;
      case CallConnectionQuality.fair:
        return Colors.orange;
      case CallConnectionQuality.poor:
        return Colors.red;
      case CallConnectionQuality.unknown:
        return Colors.grey;
    }
  }

  IconData _getQualityIcon(CallConnectionQuality quality) {
    switch (quality) {
      case CallConnectionQuality.excellent:
        return Icons.signal_cellular_4_bar;
      case CallConnectionQuality.good:
        return Icons.signal_cellular_alt;
      case CallConnectionQuality.fair:
        return Icons.signal_cellular_alt_2_bar;
      case CallConnectionQuality.poor:
        return Icons.signal_cellular_alt_1_bar;
      case CallConnectionQuality.unknown:
        return Icons.signal_cellular_null;
    }
  }
}
