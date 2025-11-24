import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_page.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

/// A unified representation of a conversation/thread, coming either from
/// the new `/conversations` collection or the legacy `/chats` collection.
class _UnifiedThread {
  final String id; // conversationId or chatId
  final bool isOldFormat; // true = /chats, false = /conversations
  final String otherUserId;
  final String? otherUserName; // for conversations we have this from displayNames
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final String? orderId;
  final String? orderTitle;

  _UnifiedThread({
    required this.id,
    required this.isOldFormat,
    required this.otherUserId,
    this.otherUserName,
    this.lastMessage,
    this.lastMessageTime,
    this.orderId,
    this.orderTitle,
  });
}

class _InboxPageState extends State<InboxPage> {
  // Legacy chats stream – old-format `/chats`
  Stream<QuerySnapshot<Map<String, dynamic>>> _getLegacyChatsStream(
      String userId) {
    return FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots();
  }

  // New conversations stream – new-format `/conversations`
  Stream<QuerySnapshot<Map<String, dynamic>>> _getConversationsStream(
      String userId) {
    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: userId)
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _getConversationsStream(currentUser.uid),
        builder: (context, convSnapshot) {
          if (convSnapshot.hasError) {
            return Center(
              child: Text('Error loading conversations: ${convSnapshot.error}'),
            );
          }

          if (convSnapshot.connectionState == ConnectionState.waiting &&
              !convSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _getLegacyChatsStream(currentUser.uid),
            builder: (context, chatsSnapshot) {
              if (chatsSnapshot.hasError) {
                // If the error mentions index, show a helpful message
                if (chatsSnapshot.error
                    .toString()
                    .contains('requires an index') ==
                    true) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Error: Your Firestore database is missing an index for the legacy chats.\n\n'
                            'Create a composite index on the "chats" collection for "users" (array-contains) '
                            'and "lastMessageTime" (descending).',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return Center(
                  child: Text('Error loading legacy chats: ${chatsSnapshot.error}'),
                );
              }

              // Build unified list of threads from both collections
              final threads = <_UnifiedThread>[];

              // 1) New-format conversations
              final convDocs = convSnapshot.data?.docs ?? [];
              for (final doc in convDocs) {
                final data = doc.data();
                final participants =
                List<String>.from(data['participants'] ?? const <String>[]);
                if (!participants.contains(currentUser.uid)) continue;

                // For now we assume 1:1 conversations (admin + driver)
                final otherUserId = participants
                    .firstWhere((id) => id != currentUser.uid, orElse: () => '');

                if (otherUserId.isEmpty) continue;

                final displayNamesRaw =
                    (data['displayNames'] as Map<String, dynamic>?) ?? {};
                final displayNames = Map<String, dynamic>.from(displayNamesRaw);
                final otherUserName =
                    (displayNames[otherUserId] as String?) ?? 'Unknown User';

                final lastMessage = data['lastMessage'] as String?;
                final lastMessageTime =
                (data['lastMessageTime'] as Timestamp?)?.toDate();

                final orderId = (data['orderId'] as String?)?.trim();
                final orderTitle = (data['orderTitle'] as String?)?.trim();

                threads.add(
                  _UnifiedThread(
                    id: doc.id,
                    isOldFormat: false,
                    otherUserId: otherUserId,
                    otherUserName: otherUserName,
                    lastMessage: lastMessage,
                    lastMessageTime: lastMessageTime,
                    orderId: orderId?.isEmpty == true ? null : orderId,
                    orderTitle: orderTitle?.isEmpty == true ? null : orderTitle,
                  ),
                );
              }

              // 2) Legacy chats
              final chatDocs = chatsSnapshot.data?.docs ?? [];
              for (final doc in chatDocs) {
                final data = doc.data();
                final users =
                List<String>.from(data['users'] ?? const <String>[]);
                if (!users.contains(currentUser.uid)) continue;

                final otherUserId =
                users.firstWhere((id) => id != currentUser.uid,
                    orElse: () => 'unknown');

                final lastMessage = data['lastMessage'] as String?;
                final lastMessageTime =
                (data['lastMessageTime'] as Timestamp?)?.toDate();

                threads.add(
                  _UnifiedThread(
                    id: doc.id,
                    isOldFormat: true,
                    otherUserId: otherUserId,
                    otherUserName: null, // will be loaded via FutureBuilder
                    lastMessage: lastMessage,
                    lastMessageTime: lastMessageTime,
                    orderId: null,
                    orderTitle: null,
                  ),
                );
              }

              if (threads.isEmpty) {
                return const Center(
                  child: Text('No conversations yet. Tap + to start a chat.'),
                );
              }

              // Sort by lastMessageTime descending
              threads.sort((a, b) {
                final aTime = a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
                final bTime = b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
                return bTime.compareTo(aTime);
              });

              return _buildChatList(threads, currentUser.uid);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // For now, you can continue to use your existing NewChatScreen,
          // which probably creates legacy /chats.
          // Later we can update it to create /conversations as well.
          Navigator.pushNamed(context, '/new-chat');
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

  Widget _buildChatList(List<_UnifiedThread> threads, String currentUserId) {
    return ListView.builder(
      itemCount: threads.length,
      itemBuilder: (context, index) {
        final thread = threads[index];

        // For new-format conversations we already have the otherUserName.
        if (!thread.isOldFormat && thread.otherUserName != null) {
          return _buildChatListItem(
            context: context,
            thread: thread,
            effectiveOtherUserName: thread.otherUserName!,
          );
        }

        // For legacy /chats we still need to look up the other user's info
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(thread.otherUserId)
              .get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const ListTile(
                title: Text("Loading chat..."),
                subtitle: Text(""),
              );
            }

            String otherUserName = 'Unknown User';
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data();
              otherUserName = (userData?['email'] as String?) ??
                  (userData?['name'] as String?) ??
                  'Unknown User';
            }

            return _buildChatListItem(
              context: context,
              thread: thread,
              effectiveOtherUserName: otherUserName,
            );
          },
        );
      },
    );
  }

  Widget _buildChatListItem({
    required BuildContext context,
    required _UnifiedThread thread,
    required String effectiveOtherUserName,
  }) {
    final subtitleText = thread.orderTitle != null && thread.orderTitle!.isNotEmpty
        ? '${thread.orderTitle} • ${thread.lastMessage ?? 'No messages yet'}'
        : (thread.lastMessage ?? 'No messages yet');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                conversationId: thread.id,
                otherUserId: thread.otherUserId,
                otherUserName: effectiveOtherUserName,
                orderId: thread.orderId,
                orderTitle: thread.orderTitle,
                isOldFormat: thread.isOldFormat,
              ),
            ),
          );
        },
        leading: CircleAvatar(
          child: Text(
            effectiveOtherUserName.isNotEmpty
                ? effectiveOtherUserName[0].toUpperCase()
                : '?',
          ),
        ),
        title: Text(
          effectiveOtherUserName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: thread.lastMessageTime != null
            ? Text(
          _formatTimestamp(thread.lastMessageTime!),
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
