import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_theme.dart';

class CallChatScreen extends StatefulWidget {
  final String callId;
  final String? callTitle;
  final FirebaseFirestore? firestore;

  const CallChatScreen({
    super.key,
    required this.callId,
    this.callTitle,
    this.firestore,
  });

  @override
  State<CallChatScreen> createState() => _CallChatScreenState();
}

class _CallChatScreenState extends State<CallChatScreen> {
  late Stream<QuerySnapshot> _chatStream;
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(covariant CallChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.callId != oldWidget.callId) {
      _initStream();
    }
  }

  void _initStream() {
    final instance = widget.firestore ?? FirebaseFirestore.instance;
    final chatCollection = instance.collection('call_chats').doc(widget.callId).collection('messages');
    _chatStream = chatCollection.orderBy('timestamp', descending: true).limit(100).snapshots();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    final instance = widget.firestore ?? FirebaseFirestore.instance;
    
    instance.collection('call_chats').doc(widget.callId).collection('messages').add({
      'text': text,
      'senderId': user?.uid ?? 'unknown',
      'senderName': user?.displayName ?? 'User',
      'timestamp': FieldValue.serverTimestamp(),
    });
    
    _messageController.clear();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: Text(widget.callTitle ?? 'Call Chat'),
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No chat messages for this call',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final d = docs[index].data() as Map<String, dynamic>;
                    final isMe = d['senderId'] == FirebaseAuth.instance.currentUser?.uid;
                    
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isMe ? AppColors.primaryBlue : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isMe) ...[
                              Text(
                                d['senderName'] ?? 'Unknown',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            Text(
                              d['text'] ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Chat Input
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.primaryBlue),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
