import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';
import 'dart:html' as html;
import 'diagnostics_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  // ignore: unused_field
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadPhoto() async {
    try {
      // Use native HTML file picker for web
      final html.FileUploadInputElement uploadInput =
          html.FileUploadInputElement();
      uploadInput.accept = 'image/*';
      uploadInput.click();

      await uploadInput.onChange.first;
      final files = uploadInput.files;

      if (files == null || files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No image selected')));
        }
        return;
      }

      setState(() => _isLoading = true);

      // Read file as bytes
      final reader = html.FileReader();
      reader.readAsArrayBuffer(files[0]);
      await reader.onLoad.first;
      final bytes = reader.result as Uint8List;

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

      await storageRef.putData(bytes, metadata);

      // Get download URL
      final photoURL = await storageRef.getDownloadURL();

      // Update user profile
      await user.updatePhotoURL(photoURL);
      await user.reload();

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Photo updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        // Trigger rebuild
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  children: [
                    // Profile Picture with ring
                    GestureDetector(
                      onTap: _uploadPhoto,
                      child: Container(
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
                          backgroundImage: user?.photoURL != null
                              ? NetworkImage(user!.photoURL!)
                              : null,
                          child: user?.photoURL == null
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
                              hintStyle: TextStyle(color: Color(0xFF8E8E93)),
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
                            borderRadius: BorderRadius.circular(
                              28,
                            ), // Very rounded like Android
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
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
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
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
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
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
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

                        // Diagnostics
                        Container(
                          color: const Color(0xFF2C2C2E),
                          child: ListTile(
                            leading: const Icon(
                              Icons.bug_report,
                              color: Color(0xFF6B7FB8),
                              size: 20,
                            ),
                            title: const Text(
                              'Diagnostics',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: Color(0xFF8E8E93),
                              size: 20,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const DiagnosticsScreen(),
                                ),
                              );
                            },
                          ),
                        ),

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
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
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
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
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
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
