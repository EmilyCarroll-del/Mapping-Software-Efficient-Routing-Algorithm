import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_page.dart';
import '../services/chat_service.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final ChatService _chatService = ChatService();

  // Start a NEW-style conversation in /conversations (not /chats)
  Future<void> _startChatWithUser(String otherUserId, String otherUserName) async {
    if (currentUser == null) return;
    final currentUserId = currentUser!.uid;

    // Prevent starting a chat with oneself
    if (currentUserId == otherUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot start a chat with yourself.')),
      );
      return;
    }

    try {
      // Use the shared ChatService to get or create a conversation
      final conversationId = await _chatService.createOrGetConversation(
        otherUserId,
        orderId: null,
        orderTitle: null,
      );

      if (!mounted) return;

      // Navigate to the new ChatPage API (conversations-based)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            conversationId: conversationId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            orderId: null,
            orderTitle: null,
            isOldFormat: false, // new /conversations format
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start chat: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Start a new chat')),
        body: const Center(
          child: Text('You must be logged in to start a chat.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start a new chat'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Stream all users from the 'users' collection
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data?.docs ?? [];

          // Filter out the current user from the list
          final otherUsers =
          users.where((doc) => doc.id != currentUser!.uid).toList();

          if (otherUsers.isEmpty) {
            return const Center(child: Text('No other users found.'));
          }

          return ListView.builder(
            itemCount: otherUsers.length,
            itemBuilder: (context, index) {
              final userDoc = otherUsers[index];
              final userData = userDoc.data() as Map<String, dynamic>?;

              // Try to resolve a decent display name
              final email = (userData?['email'] as String?) ?? '';
              final name = (userData?['name'] as String?) ?? '';
              final userName =
              name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Unknown User');

              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                  ),
                ),
                title: Text(userName),
                subtitle: email.isNotEmpty ? Text(email) : null,
                onTap: () => _startChatWithUser(userDoc.id, userName),
              );
            },
          );
        },
      ),
    );
  }
}