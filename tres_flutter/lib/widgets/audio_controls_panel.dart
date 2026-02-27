import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../services/audio_device_service.dart';
import '../services/livekit_service.dart';

class AudioControlsPanel extends StatelessWidget {
  const AudioControlsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AudioDeviceService, LiveKitService>(
      builder: (context, audioService, livekit, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'Audio Controls',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Audio Output Selection (only show if multiple devices available)
              if (audioService.availableDevices.length > 1) ...[
                const Text(
                  'Audio Output',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...audioService.availableDevices.map(
                  (device) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      audioService.getDeviceIcon(device),
                      color: audioService.currentOutput == device
                          ? const Color(0xFF6B7FB8)
                          : Colors.white70,
                    ),
                    title: Text(
                      audioService.getDeviceName(device),
                      style: TextStyle(
                        color: audioService.currentOutput == device
                            ? const Color(0xFF6B7FB8)
                            : Colors.white,
                        fontWeight: audioService.currentOutput == device
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: audioService.currentOutput == device
                        ? const Icon(Icons.check, color: Color(0xFF6B7FB8))
                        : null,
                    onTap: () => audioService.setAudioOutput(device),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 16),

              // Volume Control
              const Text(
                'Volume',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.volume_down, color: Colors.white70),
                  Expanded(
                    child: Slider(
                      value: audioService.volume,
                      onChanged: audioService.setVolume,
                      activeColor: const Color(0xFF6B7FB8),
                      inactiveColor: Colors.white30,
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    '${(audioService.volume * 100).round()}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),

              if (kIsWeb) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Volume control affects app audio only',
                          style: TextStyle(color: Colors.orange, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
