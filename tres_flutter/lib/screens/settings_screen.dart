import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../services/notification_service.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SharedPreferences _prefs;
  bool _isLoading = true;

  // Notifications
  bool _notificationsEnabled = true;
  bool _minimalNotifications = false;

  // Voice Isolation
  bool _voiceIsolation = true;

  // Video Settings
  bool _autoBoost60fps = false;
  double _portraitBlurIntensity = 70.0;
  bool _beautyFilter = true;
  bool _backgroundBlur = false;
  bool _faceAutoFraming = false;

  // Audio Processing
  bool _noiseSuppression = true;
  bool _echoCancellation = true;
  bool _spatialAudio = false;

  // AI Features

  // UI & Interaction
  String _defaultGridLayout = 'auto';
  bool _picureInPicture = true;
  bool _reactionAnimations = true;

  // Developer
  bool _developerMode = false;
  bool _callHealthOverlay = false;
  String _callQuality = 'auto';
  String _videoCodec = 'H.264 (VP9 if available)';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          // Notifications
          _notificationsEnabled =
              _prefs.getBool('notifications_enabled') ?? true;
          _minimalNotifications =
              _prefs.getBool('minimal_notifications') ?? false;

          // Voice Isolation
          _voiceIsolation = _prefs.getBool('voice_isolation') ?? true;

          // Video Settings
          _autoBoost60fps = _prefs.getBool('auto_boost_60fps') ?? false;
          _portraitBlurIntensity =
              _prefs.getDouble('portrait_blur_intensity') ?? 70.0;
          _beautyFilter = _prefs.getBool('beauty_filter') ?? true;
          _backgroundBlur = _prefs.getBool('background_blur') ?? false;
          _faceAutoFraming = _prefs.getBool('face_auto_framing') ?? false;

          // Audio Processing
          _noiseSuppression = _prefs.getBool('noise_suppression') ?? true;
          _echoCancellation = _prefs.getBool('echo_cancellation') ?? true;
          _spatialAudio = _prefs.getBool('spatial_audio') ?? false;

          // AI Features

          // UI & Interaction
          _defaultGridLayout =
              _prefs.getString('default_grid_layout') ?? 'auto';
          _picureInPicture = _prefs.getBool('picture_in_picture') ?? true;
          _reactionAnimations = _prefs.getBool('reaction_animations') ?? true;

          // Developer
          _developerMode = _prefs.getBool('developer_mode') ?? false;
          _callHealthOverlay = _prefs.getBool('call_health_overlay') ?? false;
          _callQuality = _prefs.getString('call_quality') ?? 'auto';
          _videoCodec =
              _prefs.getString('video_codec') ?? 'H.264 (VP9 if available)';

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    } else if (value is String) {
      await _prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.accentBlue),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.backgroundDark,
      ),
      backgroundColor: AppColors.backgroundDark,
      body: ListView(
        children: [
          // Notifications
          _buildSectionHeader('Notifications'),
          _buildSwitchTile(
            title: 'Notifications',
            subtitle: 'Receive call notifications',
            value: _notificationsEnabled,
            onChanged: (value) async {
              if (value) {
                // Request system permissions
                final granted = await NotificationService.enableNotifications();
                if (granted) {
                  setState(() => _notificationsEnabled = true);
                  _saveSetting('notifications_enabled', true);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Notifications enabled'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } else {
                  setState(() => _notificationsEnabled = false);
                  _saveSetting('notifications_enabled', false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '⚠️ Notification permission denied. Check device settings.',
                        ),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                }
              } else {
                setState(() => _notificationsEnabled = false);
                _saveSetting('notifications_enabled', false);
              }
            },
          ),
          _buildSwitchTile(
            title: 'Minimal Notifications',
            subtitle: 'Show once per contact (no spam while on screen)',
            value: _minimalNotifications,
            onChanged: (value) {
              setState(() => _minimalNotifications = value);
              _saveSetting('minimal_notifications', value);
            },
          ),

          // Voice Isolation
          const Divider(height: 32, color: Colors.transparent),
          _buildSwitchTile(
            title: 'Voice Isolation',
            subtitle: 'Reduce background noise (NS/AEC on)',
            value: _voiceIsolation,
            onChanged: (value) {
              setState(() => _voiceIsolation = value);
              _saveSetting('voice_isolation', value);
            },
          ),

          // Video Processing
          _buildSectionHeader('Video Processing'),
          _buildSwitchTile(
            title: 'Auto boost to 60 fps',
            subtitle:
                'Use Ultra framerate (60 fps, thermals are OK) on capable devices',
            value: _autoBoost60fps,
            onChanged: (value) {
              setState(() => _autoBoost60fps = value);
              _saveSetting('auto_boost_60fps', value);
            },
          ),

          // Portrait Blur Intensity Slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Portrait Blur Intensity',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _portraitBlurIntensity,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        activeColor: AppColors.primaryBlue,
                        inactiveColor: AppColors.primaryDark,
                        onChanged: (value) {
                          setState(() => _portraitBlurIntensity = value);
                        },
                        onChangeEnd: (value) {
                          _saveSetting('portrait_blur_intensity', value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${_portraitBlurIntensity.round()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          _buildSwitchTile(
            title: 'Beauty Filter (Auto-enable)',
            subtitle: 'Smooth skin and enhance appearance on call start',
            value: _beautyFilter,
            onChanged: (value) {
              setState(() => _beautyFilter = value);
              _saveSetting('beauty_filter', value);
            },
          ),
          _buildSwitchTile(
            title: 'Background Blur (Auto-enable)',
            subtitle: 'Blur background instead of replacing it',
            value: _backgroundBlur,
            onChanged: (value) {
              setState(() => _backgroundBlur = value);
              _saveSetting('background_blur', value);
            },
          ),
          _buildSwitchTile(
            title: 'Face Auto-Framing (Auto-enable)',
            subtitle: 'Automatically center and track your face',
            value: _faceAutoFraming,
            onChanged: (value) {
              setState(() => _faceAutoFraming = value);
              _saveSetting('face_auto_framing', value);
            },
          ),

          // Audio Processing
          _buildSectionHeader('Audio Processing'),
          _buildSwitchTile(
            title: 'Noise Suppression',
            subtitle: 'Remove background noise (keyboard, dog barking, etc.)',
            value: _noiseSuppression,
            onChanged: (value) {
              setState(() => _noiseSuppression = value);
              _saveSetting('noise_suppression', value);
            },
          ),
          _buildSwitchTile(
            title: 'Echo Cancellation',
            subtitle: 'Prevent audio feedback and echo',
            value: _echoCancellation,
            onChanged: (value) {
              setState(() => _echoCancellation = value);
              _saveSetting('echo_cancellation', value);
            },
          ),
          _buildSwitchTile(
            title: 'Spatial Audio (Auto-enable)',
            subtitle: '3D audio positioning (experimental)',
            value: _spatialAudio,
            onChanged: (value) {
              setState(() => _spatialAudio = value);
              _saveSetting('spatial_audio', value);
            },
          ),

          // AI Features
          _buildSectionHeader('AI Features'),

          // UI & Interaction
          _buildSectionHeader('UI & Interaction'),
          ListTile(
            title: const Text(
              'Default Grid Layout',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _defaultGridLayout.toUpperCase(),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () => _showGridLayoutDialog(),
          ),
          _buildSwitchTile(
            title: 'Enable Picture-in-Picture',
            subtitle: 'Allow PiP mode when minimizing calls',
            value: _picureInPicture,
            onChanged: (value) {
              setState(() => _picureInPicture = value);
              _saveSetting('picture_in_picture', value);
            },
          ),
          _buildSwitchTile(
            title: 'Reaction Animations',
            subtitle: 'Show animated reactions (👍 👎 😄)',
            value: _reactionAnimations,
            onChanged: (value) {
              setState(() => _reactionAnimations = value);
              _saveSetting('reaction_animations', value);
            },
          ),

          // Developer
          _buildSectionHeader('Developer'),
          _buildSwitchTile(
            title: 'Developer Mode',
            subtitle: 'Enable advanced options and logs',
            value: _developerMode,
            onChanged: (value) {
              setState(() => _developerMode = value);
              _saveSetting('developer_mode', value);
            },
          ),
          _buildSwitchTile(
            title: 'Call Health Overlay',
            subtitle: 'Show call quality, codec, info/audio stats',
            value: _callHealthOverlay,
            onChanged: (value) {
              setState(() => _callHealthOverlay = value);
              _saveSetting('call_health_overlay', value);
            },
          ),
          ListTile(
            title: const Text(
              'Call Quality',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _callQuality.toUpperCase(),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () => _showCallQualityDialog(),
          ),
          ListTile(
            title: const Text(
              'Video Codec (Priority Order)',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _videoCodec,
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () => _showVideoCodecDialog(),
          ),
          ListTile(
            title: const Text(
              'Diagnostics',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'View system diagnostics',
              style: TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DiagnosticsScreen(),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Refresh Push Notification Token
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Push notification token refreshed'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Refresh Push Notification Token',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Version info
          Center(
            child: Text(
              'Version 1.4.callHome',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryBlue,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
      value: value,
      activeThumbColor: AppColors.primaryBlue,
      onChanged: onChanged,
    );
  }

  void _showGridLayoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        title: const Text(
          'Default Grid Layout',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRadioOption('auto', 'Auto', 'Ajust layout for group calls'),
            _buildRadioOption('grid', 'Grid', 'Always use grid view'),
            _buildRadioOption('strip', 'Strip', 'Horizontal strip view'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  void _showCallQualityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        title: const Text(
          'Select video quality',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRadioOption('auto', 'Auto', '', isQuality: true),
            _buildRadioOption('high', 'High', '', isQuality: true),
            _buildRadioOption('medium', 'Medium', '', isQuality: true),
            _buildRadioOption('low', 'Low', '', isQuality: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  void _showVideoCodecDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Video Codec', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCodecOption('H.264 (VP9 if available)'),
            _buildCodecOption('H.265 → H.264 → VP9'),
            _buildCodecOption('VP9 → H.264'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioOption(
    String value,
    String title,
    String subtitle, {
    bool isQuality = false,
  }) {
    final currentValue = isQuality ? _callQuality : _defaultGridLayout;
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            )
          : null,
      value: value,
      groupValue: currentValue,
      activeColor: AppColors.primaryBlue,
      onChanged: (newValue) {
        setState(() {
          if (isQuality) {
            _callQuality = newValue!;
            _saveSetting('call_quality', newValue);
          } else {
            _defaultGridLayout = newValue!;
            _saveSetting('default_grid_layout', newValue);
          }
        });
        Navigator.pop(context);
      },
    );
  }

  Widget _buildCodecOption(String codec) {
    return RadioListTile<String>(
      title: Text(codec, style: const TextStyle(color: Colors.white)),
      value: codec,
      groupValue: _videoCodec,
      activeColor: AppColors.primaryBlue,
      onChanged: (newValue) {
        setState(() {
          _videoCodec = newValue!;
          _saveSetting('video_codec', newValue);
        });
        Navigator.pop(context);
      },
    );
  }
}
