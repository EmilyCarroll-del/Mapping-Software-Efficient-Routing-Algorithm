
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_page.dart';
import 'new_chat_screen.dart'; // Import the new chat screen

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  // Gets all chats where the current user is a participant
  Stream<QuerySnapshot<Map<String, dynamic>>> _getChatsStream(String userId) {
    return FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return _buildLoggedOutView();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getChatsStream(currentUser.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            if (snapshot.error.toString().contains('requires an index')) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Error: Your Firestore database is missing an index. Please create a composite index for the \'chats\' collection on \'users\' (array-contains) and \'lastMessageTime\' (descending).',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data?.docs ?? [];

          if (chats.isEmpty) {
            return const Center(
              child: Text('No conversations yet. Tap + to start a chat.'),
            );
          }

          return _buildChatList(chats, currentUser.uid);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to the screen to select a user for a new chat
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NewChatScreen()),
          );
        },
        tooltip: 'New Chat',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildLoggedOutView() {
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Please log in to see your messages.'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushReplacementNamed('/login');
              },
              child: const Text('Log In'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(List<QueryDocumentSnapshot> chats, String currentUserId) {
    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, index) {
        final chat = chats[index];
        final data = chat.data() as Map<String, dynamic>;
        final users = List<String>.from(data['users'] ?? []);

        final otherUserId = users.firstWhere((id) => id != currentUserId, orElse: () => 'unknown');

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const ListTile(title: Text("Loading chat..."), subtitle: Text(""));
            }

            String otherUserName = 'Unknown User';
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
              otherUserName = userData?['email'] ?? 'Unknown User';
            }

            return _buildChatListItem(
              context: context,
              chatId: chat.id,
              otherUserName: otherUserName,
              lastMessage: data['lastMessage'] as String?,
              lastMessageTime: (data['lastMessageTime'] as Timestamp?)?.toDate(),
            );
          },
        );
      },
    );
  }

  Widget _buildChatListItem({
    required BuildContext context,
    required String chatId,
    required String otherUserName,
    String? lastMessage,
    DateTime? lastMessageTime,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                chatId: chatId,
                otherUserName: otherUserName,
              ),
            ),
          );
        },
        leading: CircleAvatar(
          child: Text(otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : '?'),
        ),
        title: Text(otherUserName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          lastMessage ?? 'No messages yet',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: lastMessageTime != null
            ? Text(
                _formatTimestamp(lastMessageTime),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              )
            : null,
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inDays > 7) {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
