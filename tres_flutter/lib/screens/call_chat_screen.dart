import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CallChatScreen extends StatelessWidget {
  final String callId;
  final String? callTitle;
  const CallChatScreen({super.key, required this.callId, this.callTitle});

  @override
  Widget build(BuildContext context) {
    final chatCollection = FirebaseFirestore.instance.collection('call_chats').doc(callId).collection('messages');
    return Scaffold(
      appBar: AppBar(title: Text(callTitle ?? 'Call Chat')),
      body: StreamBuilder<QuerySnapshot>(
        stream: chatCollection.orderBy('timestamp', descending: true).limit(100).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No chat messages for this call'));
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
