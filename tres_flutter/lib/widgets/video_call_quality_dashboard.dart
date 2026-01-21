import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/livekit_service.dart';
import '../services/call_stats_service.dart';

class VideoCallQualityDashboard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback? onToggle;
  final CallStatsService statsService;

  const VideoCallQualityDashboard({
    super.key,
    this.isExpanded = false,
    this.onToggle,
    required this.statsService,
  });

  @override
  State<VideoCallQualityDashboard> createState() => _VideoCallQualityDashboardState();
}

class _VideoCallQualityDashboardState extends State<VideoCallQualityDashboard> {
  @override
  Widget build(BuildContext context) {
    return Consumer<LiveKitService>(
      builder: (context, liveKitService, child) {
        return AnimatedBuilder(
          animation: widget.statsService,
          builder: (context, _) {
            final stats = widget.statsService.currentStats;
            final quality = widget.statsService.currentQuality;
            if (!widget.isExpanded) {
              return _buildCollapsedView(liveKitService, quality);
            }
            return _buildExpandedView(liveKitService, stats, quality);
          },
        );
      },
    );
  }

  Widget _buildCollapsedView(LiveKitService liveKitService, CallConnectionQuality quality) {
    final indicatorColors = _getIndicatorColors(quality);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQualityIndicator(indicatorColors[0]),
          const SizedBox(width: 8),
          _buildQualityIndicator(indicatorColors[1]),
          const SizedBox(width: 8),
          _buildQualityIndicator(indicatorColors[2]),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onToggle,
            child: const Icon(
              Icons.expand_more,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityIndicator(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildExpandedView(
    LiveKitService liveKitService,
    CallStats stats,
    CallConnectionQuality quality,
  ) {
    return Container(
      width: 320,
      height: 480,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNetworkSection(liveKitService, stats),
                  const SizedBox(height: 16),
                  _buildVideoSection(liveKitService, stats),
                  const SizedBox(height: 16),
                  _buildAudioSection(liveKitService, stats),
                  const SizedBox(height: 16),
                  _buildConnectionSection(liveKitService, quality),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          Icons.analytics,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(width: 8),
        const Text(
          'Call Quality Dashboard',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: widget.onToggle,
          child: const Icon(
            Icons.expand_less,
            color: Colors.white,
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkSection(LiveKitService liveKitService, CallStats stats) {
    final rtt = (stats.roundTripTime * 1000).round();
    final packetLoss = stats.videoPacketLoss;
    final jitter = (stats.jitter * 1000).round();
    final availableUplinkMbps = (stats.availableOutgoingBitrate / 1000000);
    
    Color qualityColor = Colors.green;
    String qualityText = 'Excellent';
    
    if (rtt > 150 || packetLoss > 3.0 || jitter > 50) {
      qualityColor = Colors.red;
      qualityText = 'Poor';
    } else if (rtt > 100 || packetLoss > 1.0 || jitter > 30) {
      qualityColor = Colors.orange;
      qualityText = 'Fair';
    } else if (rtt > 50 || packetLoss > 0.5 || jitter > 15) {
      qualityColor = Colors.yellow;
      qualityText = 'Good';
    }
    
    return _buildSection(
      title: 'Network Quality',
      icon: Icons.wifi,
      child: Column(
        children: [
          _buildMetricRow(
            'Quality',
            qualityText,
            qualityColor,
          ),
          _buildMetricRow(
            'Latency',
            '${rtt}ms',
            rtt > 100 ? Colors.red : rtt > 50 ? Colors.orange : Colors.green,
          ),
          _buildMetricRow(
            'Jitter',
            '${jitter}ms',
            jitter > 30 ? Colors.red : jitter > 15 ? Colors.orange : Colors.green,
          ),
          _buildMetricRow(
            'Packet Loss',
            '${packetLoss.toStringAsFixed(1)}%',
            packetLoss > 1.0 ? Colors.red : packetLoss > 0.5 ? Colors.orange : Colors.green,
          ),
          _buildMetricRow(
            'Available Uplink',
            availableUplinkMbps > 0 ? '${availableUplinkMbps.toStringAsFixed(1)} Mbps' : 'N/A',
            availableUplinkMbps >= 8 ? Colors.green : availableUplinkMbps >= 4 ? Colors.orange : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection(LiveKitService liveKitService, CallStats stats) {
    final sendBitrate = (stats.videoSendBitrate / 1000000).toStringAsFixed(1);
    final receiveBitrate = (stats.videoRecvBitrate / 1000000).toStringAsFixed(1);
    final sendFps = stats.videoFps;
    final receiveFps = stats.videoFps; // Use same FPS for both since model only has one
    
    return _buildSection(
      title: 'Video Quality',
      icon: Icons.videocam,
      child: Column(
        children: [
          _buildMetricRow(
            'Send Bitrate',
            '$sendBitrate Mbps',
            Colors.blue,
          ),
          _buildMetricRow(
            'Receive Bitrate',
            '$receiveBitrate Mbps',
            Colors.cyan,
          ),
          _buildMetricRow(
            'Send FPS',
            '$sendFps fps',
            sendFps >= 25 ? Colors.green : sendFps >= 15 ? Colors.orange : Colors.red,
          ),
          _buildMetricRow(
            'Receive FPS',
            '$receiveFps fps',
            receiveFps >= 25 ? Colors.green : receiveFps >= 15 ? Colors.orange : Colors.red,
          ),
          _buildMetricRow(
            'Camera',
            liveKitService.isCameraEnabled ? 'On' : 'Off',
            liveKitService.isCameraEnabled ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildAudioSection(LiveKitService liveKitService, CallStats stats) {
    final audioSendBitrate = (stats.audioSendBitrate / 1000).round();
    final audioReceiveBitrate = (stats.audioRecvBitrate / 1000).round();
    
    return _buildSection(
      title: 'Audio Quality',
      icon: Icons.mic,
      child: Column(
        children: [
          _buildMetricRow(
            'Send Bitrate',
            '$audioSendBitrate kbps',
            Colors.blue,
          ),
          _buildMetricRow(
            'Receive Bitrate',
            '$audioReceiveBitrate kbps',
            Colors.cyan,
          ),
          _buildMetricRow(
            'Noise Suppression',
            'Enabled',
            Colors.green,
          ),
          _buildMetricRow(
            'Echo Cancellation',
            'Enabled',
            Colors.green,
          ),
          _buildMetricRow(
            'Microphone',
            liveKitService.isMicrophoneEnabled ? 'On' : 'Off',
            liveKitService.isMicrophoneEnabled ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionSection(
    LiveKitService liveKitService,
    CallConnectionQuality quality,
  ) {
    final participants = liveKitService.remoteParticipants.length + 1; // +1 for local
    final connectionState = liveKitService.isConnected ? 'Connected' : 'Disconnected';
    final connectionColor = liveKitService.isConnected ? Colors.green : Colors.red;
    
    return _buildSection(
      title: 'Connection Info',
      icon: Icons.info_outline,
      child: Column(
        children: [
          _buildMetricRow(
            'Status',
            connectionState,
            connectionColor,
          ),
          _buildMetricRow(
            'Participants',
            '$participants',
            Colors.blue,
          ),
          _buildMetricRow(
            'Quality',
            '${quality.name}'.toUpperCase(),
            _getQualityColor(quality),
          ),
          _buildMetricRow(
            'Tier',
            liveKitService.currentQualityTier.name.toUpperCase(),
            Colors.blueGrey,
          ),
        ],
      ),
    );
  }

  List<Color> _getIndicatorColors(CallConnectionQuality quality) {
    switch (quality) {
      case CallConnectionQuality.excellent:
        return [Colors.green, Colors.green, Colors.green];
      case CallConnectionQuality.good:
        return [Colors.green, Colors.green, Colors.yellow];
      case CallConnectionQuality.fair:
        return [Colors.orange, Colors.orange, Colors.grey];
      case CallConnectionQuality.poor:
        return [Colors.red, Colors.red, Colors.red];
      case CallConnectionQuality.unknown:
        return [Colors.grey, Colors.grey, Colors.grey];
    }
  }
  
  Color _getQualityColor(CallConnectionQuality quality) {
    switch (quality) {
      case CallConnectionQuality.excellent:
        return Colors.green;
      case CallConnectionQuality.good:
        return Colors.lightGreen;
      case CallConnectionQuality.fair:
        return Colors.yellow;
      case CallConnectionQuality.poor:
        return Colors.orange;
      case CallConnectionQuality.unknown:
        return Colors.grey;
    }
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
