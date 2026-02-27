import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    final chatCollection = instance
        .collection('call_chats')
        .doc(widget.callId)
        .collection('messages');
    _chatStream = chatCollection
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.callTitle ?? 'Call Chat')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _chatStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty)
            return const Center(child: Text('No chat messages for this call'));
          return ListView.builder(
            reverse: true,
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index].data() as Map<String, dynamic>;
              return ListTile(
                title: Text(d['senderName'] ?? 'Unknown'),
                subtitle: Text(d['text'] ?? ''),
                dense: true,
              );
            },
          );
        },
      ),
    );
  }
}
