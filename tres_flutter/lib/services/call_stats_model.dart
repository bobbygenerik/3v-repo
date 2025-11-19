import 'package:flutter/foundation.dart';

/// Connection quality levels
enum CallConnectionQuality {
  excellent,
  good,
  fair,
  poor,
  unknown,
}

extension CallConnectionQualityExtensions on CallConnectionQuality {
  String get label {
    switch (this) {
      case CallConnectionQuality.excellent:
        return 'Excellent';
      case CallConnectionQuality.good:
        return 'Good';
      case CallConnectionQuality.fair:
        return 'Fair';
      case CallConnectionQuality.poor:
        return 'Poor';
      case CallConnectionQuality.unknown:
        return 'Unknown';
    }
  }

  int get score {
    switch (this) {
      case CallConnectionQuality.excellent:
        return 100;
      case CallConnectionQuality.good:
        return 75;
      case CallConnectionQuality.fair:
        return 50;
      case CallConnectionQuality.poor:
        return 25;
      case CallConnectionQuality.unknown:
        return 0;
    }
  }
}

/// Call statistics data class
class CallStats {
  // Video stats
  final double videoSendBitrate;
  final double videoRecvBitrate;
  final double videoPacketLoss;
  final String videoResolution;
  final int videoFps;

  // Audio stats
  final double audioSendBitrate;
  final double audioRecvBitrate;
  final double audioPacketLoss;

  // Network stats
  final double roundTripTime; // RTT in seconds
  final double jitter; // in seconds
  final CallConnectionQuality quality;

  const CallStats({
    this.videoSendBitrate = 0.0,
    this.videoRecvBitrate = 0.0,
    this.videoPacketLoss = 0.0,
    this.videoResolution = 'N/A',
    this.videoFps = 0,
    this.audioSendBitrate = 0.0,
    this.audioRecvBitrate = 0.0,
    this.audioPacketLoss = 0.0,
    this.roundTripTime = 0.0,
    this.jitter = 0.0,
    this.quality = CallConnectionQuality.unknown,
  });

  String get videoSendBitrateFormatted => _formatBitrate(videoSendBitrate);
  String get videoRecvBitrateFormatted => _formatBitrate(videoRecvBitrate);
  String get audioSendBitrateFormatted => _formatBitrate(audioSendBitrate);
  String get audioRecvBitrateFormatted => _formatBitrate(audioRecvBitrate);
  String get roundTripTimeFormatted => _formatLatency(roundTripTime);
  String get jitterFormatted => _formatJitter(jitter);
  String get videoPacketLossFormatted => _formatPacketLoss(videoPacketLoss);
  String get audioPacketLossFormatted => _formatPacketLoss(audioPacketLoss);

  static String _formatBitrate(double bytesPerSecond) {
    final kbps = (bytesPerSecond * 8) / 1000;
    if (kbps > 1000) {
      return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
    } else {
      return '${kbps.toStringAsFixed(0)} kbps';
    }
  }

  static String _formatLatency(double seconds) {
    return '${(seconds * 1000).toStringAsFixed(0)} ms';
  }

  static String _formatJitter(double seconds) {
    return '${(seconds * 1000).toStringAsFixed(1)} ms';
  }

  static String _formatPacketLoss(double packets) {
    return '${packets.toStringAsFixed(1)}%';
  }

  Map<String, dynamic> toJson() {
    return {
      'videoSendBitrate': videoSendBitrate,
      'videoRecvBitrate': videoRecvBitrate,
      'videoPacketLoss': videoPacketLoss,
      'videoResolution': videoResolution,
      'videoFps': videoFps,
      'audioSendBitrate': audioSendBitrate,
      'audioRecvBitrate': audioRecvBitrate,
      'audioPacketLoss': audioPacketLoss,
      'roundTripTime': roundTripTime,
      'jitter': jitter,
      'quality': quality.toString(),
    };
  }
}
