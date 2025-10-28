
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_page.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Finds or creates a chat with the selected user and navigates to it
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

    // Check if a chat already exists
    final chatQuery = await FirebaseFirestore.instance
        .collection('chats')
        .where('users', whereIn: [
          [currentUserId, otherUserId],
          [otherUserId, currentUserId]
        ])
        .limit(1)
        .get();

    if (mounted) {
        // If a chat exists, navigate to it
        if (chatQuery.docs.isNotEmpty) {
        final existingChatId = chatQuery.docs.first.id;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
            builder: (context) => ChatPage(
                chatId: existingChatId,
                otherUserName: otherUserName,
            ),
            ),
        );
        } else {
        // If no chat exists, create a new one
        final newChatDoc = await FirebaseFirestore.instance.collection('chats').add({
            'users': [currentUserId, otherUserId],
            'lastMessage': 'Chat started.',
            'lastMessageTime': FieldValue.serverTimestamp(),
        });
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
            builder: (context) => ChatPage(
                chatId: newChatDoc.id,
                otherUserName: otherUserName,
            ),
            ),
        );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          final otherUsers = users.where((doc) => doc.id != currentUser?.uid).toList();

          if (otherUsers.isEmpty) {
            return const Center(child: Text('No other users found.'));
          }

          return ListView.builder(
            itemCount: otherUsers.length,
            itemBuilder: (context, index) {
              final userDoc = otherUsers[index];
              final userData = userDoc.data() as Map<String, dynamic>?;
              final userName = userData?['email'] ?? 'Unknown User';

              return ListTile(
                leading: CircleAvatar(
                  child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?'),
                ),
                title: Text(userName),
                onTap: () => _startChatWithUser(userDoc.id, userName),
              );
            },
          );
        },
      ),
    );
  }
}
