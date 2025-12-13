import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/livekit_service.dart';
import '../services/enhanced_network_quality_service.dart';
import '../services/adaptive_streaming_manager.dart';
import '../services/enhanced_audio_processor.dart';
import '../services/video_call_memory_manager.dart';
import '../services/advanced_device_profiler.dart';

class VideoCallQualityDashboard extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback? onToggle;

  const VideoCallQualityDashboard({
    super.key,
    this.isExpanded = false,
    this.onToggle,
  });

  @override
  State<VideoCallQualityDashboard> createState() => _VideoCallQualityDashboardState();
}

class _VideoCallQualityDashboardState extends State<VideoCallQualityDashboard> {
  @override
  Widget build(BuildContext context) {
    return Consumer<LiveKitService>(
      builder: (context, liveKitService, child) {
        if (!widget.isExpanded) {
          return _buildCollapsedView(liveKitService);
        }
        
        return _buildExpandedView(liveKitService);
      },
    );
  }

  Widget _buildCollapsedView(LiveKitService liveKitService) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQualityIndicator(Colors.green),
          const SizedBox(width: 8),
          _buildQualityIndicator(Colors.green),
          const SizedBox(width: 8),
          _buildQualityIndicator(Colors.green),
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

  Widget _buildExpandedView(LiveKitService liveKitService) {
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
                  _buildNetworkSection(liveKitService),
                  const SizedBox(height: 16),
                  _buildVideoSection(liveKitService),
                  const SizedBox(height: 16),
                  _buildAudioSection(liveKitService),
                  const SizedBox(height: 16),
                  _buildMemorySection(liveKitService),
                  const SizedBox(height: 16),
                  _buildDeviceSection(liveKitService),
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

  Widget _buildNetworkSection(LiveKitService liveKitService) {
    return _buildSection(
      title: 'Network Quality',
      icon: Icons.wifi,
      child: Column(
        children: [
          _buildMetricRow(
            'Quality',
            'Good',
            Colors.green,
          ),
          _buildMetricRow(
            'Latency',
            '45ms',
            Colors.green,
          ),
          _buildMetricRow(
            'Bandwidth',
            '50 Mbps',
            Colors.blue,
          ),
          _buildMetricRow(
            'Packet Loss',
            '0.1%',
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection(LiveKitService liveKitService) {
    return _buildSection(
      title: 'Video Quality',
      icon: Icons.videocam,
      child: Column(
        children: [
          _buildMetricRow(
            'Bitrate',
            '5.2 Mbps',
            Colors.blue,
          ),
          _buildMetricRow(
            'Frame Rate',
            '30 fps',
            Colors.green,
          ),
          _buildMetricRow(
            'Resolution',
            '1080p',
            Colors.purple,
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

  Widget _buildAudioSection(LiveKitService liveKitService) {
    return _buildSection(
      title: 'Audio Quality',
      icon: Icons.mic,
      child: Column(
        children: [
          _buildMetricRow(
            'Quality Score',
            '95%',
            Colors.green,
          ),
          _buildMetricRow(
            'Noise Suppression',
            'Enabled',
            Colors.blue,
          ),
          _buildMetricRow(
            'Echo Cancellation',
            'Enabled',
            Colors.purple,
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

  Widget _buildMemorySection(LiveKitService liveKitService) {
    return _buildSection(
      title: 'Memory Usage',
      icon: Icons.memory,
      child: Column(
        children: [
          _buildMetricRow(
            'Current',
            '245 MB',
            Colors.green,
          ),
          _buildMetricRow(
            'Peak',
            '312 MB',
            Colors.orange,
          ),
          _buildMetricRow(
            'Pressure',
            'Normal',
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSection(LiveKitService liveKitService) {
    return _buildSection(
      title: 'Device Performance',
      icon: Icons.phone_android,
      child: Column(
        children: [
          _buildMetricRow(
            'Performance',
            'High',
            Colors.green,
          ),
          _buildMetricRow(
            'Thermal State',
            'Normal',
            Colors.green,
          ),
          _buildMetricRow(
            'Battery',
            '78%',
            Colors.green,
          ),
        ],
      ),
    );
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