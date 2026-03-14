import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isSaving = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    _loadUserProfile();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  void _loadUserProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final newName = _nameController.text.trim();

      // 1. Update Firebase Auth (Login profile)
      await user.updateDisplayName(newName);

      // 2. Update Firestore (Public profile for contacts/calls)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': newName,
        'name': newName, // Keep both fields synced for compatibility
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _uploadPhoto() async {
    try {
      Uint8List? bytes;

      if (kIsWeb) {
        // On web, ImagePicker should be supported via image_picker_for_web
        final XFile? picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (picked == null) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('No image selected')));
          }
          return;
        }
        bytes = await picked.readAsBytes();
      } else {
        // Mobile platforms: use native image picker
        final XFile? picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        if (picked == null) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('No image selected')));
          }
          return;
        }
        bytes = await picked.readAsBytes();
      }

      // Show crop dialog
      if (!mounted) return;
      final croppedBytes = await _showCropDialog(bytes!);

      if (croppedBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo upload cancelled')),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('${user.uid}.jpg');

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploaded-by': user.uid},
      );

      await storageRef.putData(croppedBytes, metadata);

      // Get download URL
      final photoURL = await storageRef.getDownloadURL();

      // Update user profile in Firebase Auth
      await user.updatePhotoURL(photoURL);

      // Update user document in Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoURL': photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Force reload to get updated photoURL
      await user.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;

      debugPrint('✅ Updated photoURL in Firestore: $photoURL');
      debugPrint(
        '✅ Current user photoURL after reload: ${updatedUser?.photoURL}',
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✓ Photo updated successfully! Please go back to see changes.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show image crop dialog for web
  Future<Uint8List?> _showCropDialog(Uint8List imageBytes) async {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImageCropDialog(imageBytes: imageBytes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isBusy = _isSaving || _isUploading;

    return Scaffold(
      backgroundColor: const Color(
        0xFF1C1C1E,
      ), // Dark background matching Android
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text(
          'Profile Settings',
          style: TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 20,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            children: [
              // Profile Picture with ring
              Semantics(
                label: 'Change profile picture',
                button: true,
                child: GestureDetector(
                  onTap: isBusy ? null : _uploadPhoto,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFF6B7FB8,
                            ), // App's main blue color
                            width: 4,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 80,
                          backgroundColor: const Color(0xFF2C2C2E),
                          backgroundImage:
                              user?.photoURL != null &&
                                  user!.photoURL!.isNotEmpty
                              ? NetworkImage(user.photoURL!)
                              : null,
                          child:
                              user?.photoURL == null || user!.photoURL!.isEmpty
                              ? Text(
                                  (user?.displayName?.isNotEmpty == true
                                      ? user!.displayName![0].toUpperCase()
                                      : user?.email?[0].toUpperCase() ?? 'U'),
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      if (_isUploading)
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Semantics(
                              label: 'Uploading profile picture...',
                              child: const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                        ),
                      if (!_isUploading)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6B7FB8),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF1C1C1E),
                                width: 3,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // "Tap to change profile picture" text
              const Text(
                'Tap to change profile picture',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
              ),

              const SizedBox(height: 48),

              // Display Name input
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text(
                      'Display Name',
                      style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2128),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white10,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _nameController,
                      enabled: !isBusy,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saveProfile(),
                      style: TextStyle(
                        color: isBusy ? Colors.white54 : Colors.white,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        hintText: 'Enter your name',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                        suffixIcon: _nameController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: Color(0xFF8E8E93),
                                ),
                                onPressed: () => _nameController.clear(),
                                tooltip: 'Clear name',
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Save Profile button - large rounded button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isBusy ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B7FB8),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFF6B7FB8,
                    ).withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        28,
                      ), // Very rounded like Android
                    ),
                  ),
                  child: _isSaving
                      ? Semantics(
                          label: 'Saving profile...',
                          child: const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Save Profile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 48),

              // Additional options section (collapsible/expandable)
              IgnorePointer(
                ignoring: isBusy,
                child: Opacity(
                  opacity: isBusy ? 0.6 : 1.0,
                  child: ExpansionTile(
                    title: const Text(
                      'Additional Options',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    backgroundColor: const Color(0xFF1F2128),
                    collapsedBackgroundColor: const Color(0xFF1F2128),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Colors.white10),
                    ),
                    collapsedShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Colors.white10),
                    ),
                    children: [
                      // Email/Phone info
                      Container(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: Icon(
                            user?.email != null ? Icons.email : Icons.phone,
                            color: const Color(0xFF6B7FB8),
                            size: 20,
                          ),
                          title: const Text(
                            'Contact',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: Text(
                            user?.email ?? user?.phoneNumber ?? 'Not set',
                            style: const TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),

                      // User ID
                      Container(
                        color: const Color(0xFF2C2C2E),
                        child: ListTile(
                          leading: const Icon(
                            Icons.fingerprint,
                            color: Color(0xFF6B7FB8),
                            size: 20,
                          ),
                          title: const Text(
                            'User ID',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: Text(
                            user?.uid ?? 'Unknown',
                            style: const TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 10,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),

                      // Member Since
                      Container(
                        color: const Color(0xFF2C2C2E),
                        child: ListTile(
                          leading: const Icon(
                            Icons.calendar_today,
                            color: Color(0xFF6B7FB8),
                            size: 20,
                          ),
                          title: const Text(
                            'Member Since',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          subtitle: Text(
                            user?.metadata.creationTime?.toString().split(
                                  ' ',
                                )[0] ??
                                'Unknown',
                            style: const TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),

                      const Divider(color: Color(0xFF3A3A3C), height: 1),

                      // Change Password
                      Container(
                        color: const Color(0xFF2C2C2E),
                        child: ListTile(
                          leading: const Icon(
                            Icons.lock,
                            color: Color(0xFF6B7FB8),
                            size: 20,
                          ),
                          title: const Text(
                            'Change Password',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Color(0xFF8E8E93),
                            size: 20,
                          ),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password change coming soon'),
                                backgroundColor: Color(0xFF2C2C2E),
                              ),
                            );
                          },
                        ),
                      ),

                      // Privacy Settings
                      Container(
                        color: const Color(0xFF2C2C2E),
                        child: ListTile(
                          leading: const Icon(
                            Icons.security,
                            color: Color(0xFF6B7FB8),
                            size: 20,
                          ),
                          title: const Text(
                            'Privacy Settings',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Color(0xFF8E8E93),
                            size: 20,
                          ),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Privacy settings coming soon'),
                                backgroundColor: Color(0xFF2C2C2E),
                              ),
                            );
                          },
                        ),
                      ),

                      // Delete Account
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(16), // rounded-xl
                            bottomRight: Radius.circular(16), // rounded-xl
                          ),
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.delete_forever,
                            color: Colors.red,
                            size: 20,
                          ),
                          title: const Text(
                            'Delete Account',
                            style: TextStyle(color: Colors.red, fontSize: 14),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: Color(0xFF8E8E93),
                            size: 20,
                          ),
                          onTap: () => _showDeleteAccountDialog(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // rounded-xl
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
          style: TextStyle(color: Color(0xFF8E8E93)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Account deletion requires re-authentication'),
                  backgroundColor: Color(0xFF2C2C2E),
                ),
              );
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// Image Crop Dialog for Web
class _ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const _ImageCropDialog({required this.imageBytes});

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  Offset _cropOffset = Offset.zero;
  double _scale = 1.0;
  ui.Image? _image;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Offset _clampOffset(Offset offset, double scale, double cropSize) {
    if (_image == null) return offset;

    // Calculate the scaled image dimensions
    final scaledWidth = cropSize * scale;
    final scaledHeight = cropSize * scale;

    // Calculate max offset (how far we can drag)
    // The image can be dragged until its edge reaches the crop area edge
    final maxOffsetX = (scaledWidth - cropSize) / 2;
    final maxOffsetY = (scaledHeight - cropSize) / 2;

    return Offset(
      offset.dx.clamp(-maxOffsetX, maxOffsetX),
      offset.dy.clamp(-maxOffsetY, maxOffsetY),
    );
  }

  Future<void> _loadImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _image = frame.image;
      _isLoading = false;
      // Center the image initially
      _scale = 1.5; // Start zoomed in a bit
    });
  }

  Future<Uint8List> _cropImage() async {
    if (_image == null) return widget.imageBytes;

    const cropSize = 400.0; // Square crop size
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Calculate the source rectangle (what part of the image to crop)
    final imageWidth = _image!.width.toDouble();
    final imageHeight = _image!.height.toDouble();

    // Convert crop offset to image coordinates
    final scaleX = imageWidth / cropSize;
    final scaleY = imageHeight / cropSize;

    final srcLeft = (-_cropOffset.dx / _scale) * scaleX;
    final srcTop = (-_cropOffset.dy / _scale) * scaleY;
    final srcSize = cropSize / _scale * scaleX;

    final srcRect = Rect.fromLTWH(
      srcLeft.clamp(0, imageWidth - srcSize),
      srcTop.clamp(0, imageHeight - srcSize),
      srcSize,
      srcSize,
    );

    final dstRect = const Rect.fromLTWH(0, 0, cropSize, cropSize);

    // Draw the cropped portion
    canvas.drawImageRect(_image!, srcRect, dstRect, Paint());

    final picture = recorder.endRecording();
    final img = await picture.toImage(cropSize.toInt(), cropSize.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1C1C1E),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Crop Profile Photo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Drag to position, use slider to zoom',
                  style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Crop area
                if (_isLoading)
                  SizedBox(
                    height: MediaQuery.of(context).size.width > 400
                        ? 400
                        : MediaQuery.of(context).size.width - 64,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6B7FB8),
                      ),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cropSize = MediaQuery.of(context).size.width > 400
                          ? 400.0
                          : MediaQuery.of(context).size.width - 64;

                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: cropSize,
                          height: cropSize,
                          color: Colors.black,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                final newOffset = _cropOffset + details.delta;
                                _cropOffset = _clampOffset(
                                  newOffset,
                                  _scale,
                                  cropSize,
                                );
                              });
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Image
                                if (_image != null)
                                  Transform.translate(
                                    offset: _cropOffset,
                                    child: Transform.scale(
                                      scale: _scale,
                                      child: RawImage(
                                        image: _image,
                                        fit: BoxFit.cover,
                                        width: cropSize,
                                        height: cropSize,
                                      ),
                                    ),
                                  ),

                                // Circular crop guide
                                Container(
                                  width: cropSize * 0.75,
                                  height: cropSize * 0.75,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.8),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 16),

                // Zoom slider
                Row(
                  children: [
                    const Icon(
                      Icons.zoom_out,
                      color: Color(0xFF8E8E93),
                      size: 20,
                    ),
                    Expanded(
                      child: Slider(
                        value: _scale,
                        min: 1.0,
                        max: 3.0,
                        activeColor: const Color(0xFF6B7FB8),
                        onChanged: (value) {
                          setState(() {
                            _scale = value;
                            // Re-clamp offset when scale changes
                            final cropSize =
                                MediaQuery.of(context).size.width > 400
                                ? 400.0
                                : MediaQuery.of(context).size.width - 64;
                            _cropOffset = _clampOffset(
                              _cropOffset,
                              _scale,
                              cropSize,
                            );
                          });
                        },
                      ),
                    ),
                    const Icon(
                      Icons.zoom_in,
                      color: Color(0xFF8E8E93),
                      size: 20,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Color(0xFF8E8E93)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        final croppedBytes = await _cropImage();
                        if (context.mounted) {
                          Navigator.pop(context, croppedBytes);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B7FB8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
