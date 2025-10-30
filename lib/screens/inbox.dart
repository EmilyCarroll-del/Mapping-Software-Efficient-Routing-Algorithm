import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'chat_page.dart';
import 'new_chat_screen.dart';
import '../services/chat_service.dart';
import '../colors.dart';

class InboxPage extends StatefulWidget {
  final String? openConversationId;
  const InboxPage({super.key, this.openConversationId});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<QueryDocumentSnapshot> _filteredConversations = [];
  bool _isSearching = false;
  bool _openedFromLink = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // If an external conversation id was provided, open it once when the
    // widget is built and user is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenConversationFromLink();
    });
    // Trigger a lightweight backfill for missing display names on first load
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('conversations')
            .where('participants', arrayContains: currentUser.uid)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final participants = List<String>.from(
            data['participants'] ?? data['users'] ?? []
          );
          final displayNames = Map<String, dynamic>.from(data['displayNames'] ?? {});
          bool missing = false;
          for (final uid in participants) {
            if ((displayNames[uid] as String?) == null || (displayNames[uid] as String?)!.isEmpty) {
              missing = true;
              break;
            }
          }
          if (missing) {
            await _chatService.ensureDisplayNames(doc.id, participants);
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _maybeOpenConversationFromLink() async {
    if (_openedFromLink) return;
    final convoId = widget.openConversationId;
    final currentUser = _auth.currentUser;
    if (convoId == null || currentUser == null) return;

    try {
      final convDoc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(convoId)
          .get();
      if (!convDoc.exists) return;

      final data = convDoc.data() as Map<String, dynamic>;
      final participants = List<String>.from(data['participants'] ?? []);
      final otherUserId = participants.firstWhere(
        (id) => id != currentUser.uid,
        orElse: () => '',
      );
      if (otherUserId.isEmpty) return;

      final userData = await _chatService.getUserDetails(otherUserId);
      final otherUserName = userData?['name'] ?? userData?['email'] ?? 'User';

      _openedFromLink = true;
      if (!mounted) return;
      context.push('/chat', extra: {
        'conversationId': convoId,
        'otherUserId': otherUserId,
        'otherUserName': otherUserName,
        'orderId': data['orderId'] as String?,
        'orderTitle': data['orderTitle'] as String?,
      });
    } catch (_) {
      // Silently ignore; user can still tap from list.
    }
  }

  Future<void> _searchConversations(String query) async {
    if (query.isEmpty) {
      setState(() {
        _filteredConversations = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _chatService.searchConversations(query);
      setState(() {
        _filteredConversations = results;
      });
    } catch (e) {
      print('Error searching conversations: $e');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search conversations...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _searchConversations('');
                  },
                  icon: const Icon(Icons.clear),
                )
              : null,
        ),
        onChanged: _searchConversations,
      ),
    );
  }

  Widget _buildConversationTile(DocumentSnapshot conversation) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    final data = conversation.data() as Map<String, dynamic>;
    
    // Handle both old format ('users') and new format ('participants')
    final participantList = List<String>.from(
      data['participants'] ?? data['users'] ?? []
    );
    final otherUserId = participantList.firstWhere(
      (id) => id != currentUser.uid,
      orElse: () => '',
    );

    final lastMessage = data['lastMessage'] as String?;
    final lastMessageTime = (data['lastMessageTime'] as Timestamp?)?.toDate();
    
    // Handle unread count for both formats
    int unreadCount = 0;
    if (data['unreadCount'] != null) {
      unreadCount = ((data['unreadCount'] as Map<String, dynamic>)[currentUser.uid] ?? 0) as int;
    }
    
    final orderTitle = data['orderTitle'] as String?;
    final displayNames = (data['displayNames'] as Map<String, dynamic>?) ?? {};

    return FutureBuilder<Map<String, dynamic>?>(
      future: _chatService.getUserDetails(otherUserId),
      builder: (context, snapshot) {
        final otherUserData = snapshot.data;
        String otherUserName = (displayNames[otherUserId] as String?) ?? '';
        if (otherUserName.isEmpty) {
          otherUserName = otherUserData?['name'] ?? otherUserData?['email'] ?? 'User';
          // Also trigger background backfill using ChatService for reliability
          if (otherUserId.isNotEmpty) {
            _chatService.ensureDisplayNames(conversation.id, participantList);
          }
        }
        // Backfill displayNames into the conversation document if missing
        if ((displayNames[otherUserId] as String?) == null && otherUserName.isNotEmpty) {
          try {
            FirebaseFirestore.instance
                .collection('conversations')
                .doc(conversation.id)
                .update({'displayNames.$otherUserId': otherUserName});
          } catch (_) {}
        }
        final otherUserImage = otherUserData?['profileImageUrl'];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: unreadCount > 0 
                ? kPrimaryColor.withOpacity(0.05) 
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            onTap: () {
              // Check if this is from old 'chats' collection
              final isOldFormat = data['users'] != null && data['participants'] == null;
              context.push('/chat', extra: {
                'conversationId': conversation.id,
                'otherUserId': otherUserId,
                'otherUserName': otherUserName,
                'orderId': data['orderId'] as String?,
                'orderTitle': orderTitle,
                'isOldFormat': isOldFormat,
              });
            },
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: otherUserImage != null 
                      ? NetworkImage(otherUserImage)
                      : null,
                  backgroundColor: kPrimaryColor.withOpacity(0.1),
                  child: otherUserImage == null
                      ? Text(
                          otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              otherUserName,
              style: TextStyle(
                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (orderTitle != null && orderTitle.isNotEmpty) ...[
                  Text(
                    'Order: $orderTitle',
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  lastMessage ?? 'No messages yet',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      lastMessageTime != null ? _formatTimestamp(lastMessageTime!) : '',
                      style: TextStyle(
                        color: unreadCount > 0 ? kPrimaryColor : Colors.grey[500],
                        fontSize: 12,
                        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: kPrimaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete conversation?'),
                          content: const Text('This will delete all messages in this conversation.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await _chatService.deleteConversation(conversation.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Conversation deleted')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to delete: $e')),
                            );
                          }
                        }
                      }
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 18),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: kPrimaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start a conversation with your dispatcher or admin',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            const Text(
              'Please log in',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You need to log in to view your messages',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text(
                'Log In',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 7) {
      return '${timestamp.month}/${timestamp.day}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredConversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No conversations found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredConversations.length,
      itemBuilder: (context, index) {
        return _buildConversationTile(_filteredConversations[index]);
      },
    );
  }

  Widget _buildConversationsList() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return _buildEmptyState();
    }

    // Query both new and old formats
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getUserConversations(),
      builder: (context, newSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _chatService.getOldChats(),
          builder: (context, oldSnapshot) {
            // Combine conversations from both streams
            final allConversations = <QueryDocumentSnapshot>[];
            
            if (newSnapshot.hasData) {
              allConversations.addAll(newSnapshot.data!.docs);
            }
            
            if (oldSnapshot.hasData) {
              allConversations.addAll(oldSnapshot.data!.docs);
            }

            // Check for errors
            if ((newSnapshot.hasError || oldSnapshot.hasError) && allConversations.isEmpty) {
              print('Error loading conversations: ${newSnapshot.error ?? oldSnapshot.error}');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading conversations',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please try again or contact support',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {}); // Retry
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            // Show loading if both are waiting
            if ((newSnapshot.connectionState == ConnectionState.waiting || 
                 oldSnapshot.connectionState == ConnectionState.waiting) && 
                allConversations.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading conversations...'),
                  ],
                ),
              );
            }

            if (allConversations.isEmpty) {
              return _buildEmptyState();
            }

            // Sort conversations client-side by last message time (newest first)
            final sortedConversations = List<QueryDocumentSnapshot>.from(allConversations);
            sortedConversations.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              
              final aTime = aData['lastMessageTime'] as Timestamp?;
              final bTime = bData['lastMessageTime'] as Timestamp?;
              
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              
              return bTime.compareTo(aTime); // Descending order (newest first)
            });

            return RefreshIndicator(
              onRefresh: () async {
                setState(() {}); // Refresh the streams
              },
              child: ListView.builder(
                itemCount: sortedConversations.length,
                itemBuilder: (context, index) {
                  return _buildConversationTile(sortedConversations[index]);
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Inbox'),
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
        ),
        body: _buildLoginPrompt(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Messages',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(
            child: _searchController.text.isNotEmpty
                ? _buildSearchResults()
                : _buildConversationsList(),
          ),
        ],
      ),
    );
  }
}
