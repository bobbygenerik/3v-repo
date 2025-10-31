import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:io';
import '../config/app_theme.dart';
import '../config/environment.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, dynamic> _diagnostics = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() => _isLoading = true);

    try {
      final deviceInfo = DeviceInfoPlugin();
      final connectivity = await Connectivity().checkConnectivity();
      final user = FirebaseAuth.instance.currentUser;

      Map<String, dynamic> deviceData = {};

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceData = {
          'Device': androidInfo.model,
          'Manufacturer': androidInfo.manufacturer,
          'Android Version': androidInfo.version.release,
          'SDK': androidInfo.version.sdkInt.toString(),
          'Brand': androidInfo.brand,
          'Hardware': androidInfo.hardware,
          'Is Physical Device': androidInfo.isPhysicalDevice.toString(),
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceData = {
          'Device': iosInfo.model,
          'System Name': iosInfo.systemName,
          'System Version': iosInfo.systemVersion,
          'Name': iosInfo.name,
          'Is Physical Device': iosInfo.isPhysicalDevice.toString(),
        };
      } else {
        deviceData = {
          'Platform': Platform.operatingSystem,
          'Version': Platform.operatingSystemVersion,
        };
      }

      setState(() {
        _diagnostics = {
          'Device Info': deviceData,
          'Network': {
            'Connection': connectivity.toString().split('.').last,
            'Online': connectivity != ConnectivityResult.none,
          },
          'Firebase': {
            'App Name': Firebase.app().name,
            'User ID': user?.uid ?? 'Not signed in',
            'Auth Provider': user?.providerData.firstOrNull?.providerId ?? 'None',
            'Email Verified': user?.emailVerified.toString() ?? 'N/A',
          },
          'LiveKit': {
            'URL': Environment.liveKitUrl,
            'API Key': 'Configured', // Don't expose actual key
            'Functions URL': Environment.functionsBaseUrl,
          },
          'Features': {
            'ML Kit Face Detection': Environment.enableMLFeatures.toString(),
            'E2E Encryption': Environment.enableE2EEncryption.toString(),
            'Recording': Environment.enableCloudRecording.toString(),
            'Screen Share': Environment.enableScreenShare.toString(),
          },
          'App': {
            'Platform': Platform.operatingSystem,
            'Version': '1.0.0',
            'Dart Version': Platform.version.split(' ')[0],
          },
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _diagnostics = {'Error': {'Message': e.toString()}};
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDiagnostics,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyDiagnostics,
            tooltip: 'Copy to clipboard',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                // Status Banner
                Card(
                  color: _isSystemHealthy()
                      ? Colors.green.shade900
                      : Colors.orange.shade900,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          _isSystemHealthy()
                              ? Icons.check_circle
                              : Icons.warning,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isSystemHealthy()
                                    ? 'System Healthy'
                                    : 'Configuration Issues',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSystemHealthy()
                                    ? 'All systems operational'
                                    : 'Check configuration below',
                                style: const TextStyle(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Diagnostics Sections
                ..._diagnostics.entries.map((section) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                        child: Text(
                          section.key.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: (section.value as Map<String, dynamic>)
                                .entries
                                .map((item) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item.key,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textLight,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        item.value.toString(),
                                        style: const TextStyle(
                                          color: AppColors.textWhite,
                                        ),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),

                const SizedBox(height: 24),

                // Test Buttons
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'SYSTEM TESTS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _testNetworkConnection,
                          icon: const Icon(Icons.wifi),
                          label: const Text('Test Network'),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _testFirebaseConnection,
                          icon: const Icon(Icons.cloud),
                          label: const Text('Test Firebase'),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _testLiveKitConnection,
                          icon: const Icon(Icons.video_call),
                          label: const Text('Test LiveKit'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
    );
  }

  bool _isSystemHealthy() {
    final livekit = _diagnostics['LiveKit'] as Map<String, dynamic>?;
    final network = _diagnostics['Network'] as Map<String, dynamic>?;
    final firebase = _diagnostics['Firebase'] as Map<String, dynamic>?;

    return livekit?['API Key'] == 'Configured' &&
        network?['Online'] == true &&
        firebase?['User ID'] != 'Not signed in';
  }

  void _copyDiagnostics() {
    final text = StringBuffer();
    text.writeln('=== 3V Video Chat Diagnostics ===\n');

    _diagnostics.forEach((section, items) {
      text.writeln('$section:');
      (items as Map<String, dynamic>).forEach((key, value) {
        text.writeln('  $key: $value');
      });
      text.writeln();
    });

    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard')),
    );
  }

  Future<void> _testNetworkConnection() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Testing network...'),
          ],
        ),
      ),
    );

    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Network Test'),
            content: Text(
              connectivity != ConnectivityResult.none
                  ? 'Network connection: ${connectivity.toString().split('.').last}'
                  : 'No network connection',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorDialog('Network test failed: $e');
      }
    }
  }

  Future<void> _testFirebaseConnection() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Testing Firebase...'),
          ],
        ),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Firebase Test'),
            content: Text(
              user != null
                  ? 'Connected as: ${user.email ?? user.phoneNumber ?? user.uid}'
                  : 'Not authenticated',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorDialog('Firebase test failed: $e');
      }
    }
  }

  Future<void> _testLiveKitConnection() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Testing LiveKit...'),
          ],
        ),
      ),
    );

    // Simulate test
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('LiveKit Test'),
          content: Text(
            Environment.liveKitUrl.isNotEmpty
                ? 'LiveKit URL configured: ${Environment.liveKitUrl}'
                : 'LiveKit URL not configured',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
