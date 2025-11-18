import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
// import 'dart:html' as html;
import 'dart:ui' as ui;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isEditing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  void _loadUserProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.updateDisplayName(_nameController.text);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadPhoto() async {
    try {
      // Mobile image upload not implemented
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image upload not available on mobile')),
      );
      return;
      
      final bytes = Uint8List(0); // Placeholder

      // Show crop dialog
      if (!mounted) return;
      final croppedBytes = await _showCropDialog(bytes);
      
      if (croppedBytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo upload cancelled')),
          );
        }
        return;
      }

      setState(() => _isLoading = true);

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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'photoURL': photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      // Force reload to get updated photoURL
      await user.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;
      
      debugPrint('✅ Updated photoURL in Firestore: $photoURL');
      debugPrint('✅ Current user photoURL after reload: ${updatedUser?.photoURL}');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Photo updated successfully! Please go back to see changes.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      setState(() => _isLoading = false);
      if (mounted) {
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
    
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E), // Dark background matching Android
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
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
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6B7FB8)),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  children: [
                    // Profile Picture with ring
                    GestureDetector(
                      onTap: _uploadPhoto,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF6B7FB8), // App's main blue color
                            width: 4,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 80,
                          backgroundColor: const Color(0xFF2C2C2E),
                          backgroundImage: user?.photoURL != null && user!.photoURL!.isNotEmpty
                              ? NetworkImage(user.photoURL!) 
                              : null,
                          child: user?.photoURL == null || user!.photoURL!.isEmpty
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
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // "Tap to change profile picture" text
                    const Text(
                      'Tap to change profile picture',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                      ),
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
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF3A3A3C),
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: _nameController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              hintText: 'Enter your name',
                              hintStyle: TextStyle(
                                color: Color(0xFF8E8E93),
                              ),
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
                        onPressed: _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B7FB8),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28), // Very rounded like Android
                          ),
                        ),
                        child: const Text(
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
                    ExpansionTile(
                      title: const Text(
                        'Additional Options',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      iconColor: const Color(0xFF6B7FB8),
                      collapsedIconColor: const Color(0xFF8E8E93),
                      backgroundColor: const Color(0xFF2C2C2E),
                      collapsedBackgroundColor: const Color(0xFF2C2C2E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      collapsedShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      children: [
                        // Email/Phone info
                        Container(
                          color: const Color(0xFF2C2C2E),
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
                              user?.metadata.creationTime?.toString().split(' ')[0] ?? 'Unknown',
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
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
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
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                              ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.red),
            ),
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
                      child: CircularProgressIndicator(color: Color(0xFF6B7FB8)),
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
                                _cropOffset = _clampOffset(newOffset, _scale, cropSize);
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
                                      color: Colors.white.withOpacity(0.8),
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
                    const Icon(Icons.zoom_out, color: Color(0xFF8E8E93), size: 20),
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
                            final cropSize = MediaQuery.of(context).size.width > 400 
                              ? 400.0 
                              : MediaQuery.of(context).size.width - 64;
                            _cropOffset = _clampOffset(_cropOffset, _scale, cropSize);
                          });
                        },
                      ),
                    ),
                    const Icon(Icons.zoom_in, color: Color(0xFF8E8E93), size: 20),
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
