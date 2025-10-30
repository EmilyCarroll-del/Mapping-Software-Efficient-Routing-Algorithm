import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Create or get existing conversation between two users
  Future<String> createOrGetConversation(
    String otherUserId, {
    String? orderId,
    String? orderTitle,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be logged in to create conversation');
    }

    final currentUserId = currentUser.uid;

    // Get current user's company code first
    String? companyCode;
    try {
      final currentUserDoc = await _db.collection('users').doc(currentUserId).get();
      companyCode = currentUserDoc.data()?['companyCode'] as String?;
    } catch (e) {
      print('Error getting company code: $e');
    }

    // Check if conversation already exists in 'conversations' collection
    final existingConversations = await _db
        .collection('conversations')
        .where('participants', arrayContains: currentUserId)
        .get();

    for (var conv in existingConversations.docs) {
      final participants = List<String>.from(conv.data()['participants'] ?? []);
      if (participants.contains(otherUserId)) {
        // Update orderId if provided and not already set
        if (orderId != null && conv.data()['orderId'] == null) {
          await conv.reference.update({
            'orderId': orderId,
            'orderTitle': orderTitle ?? '',
          });
        }
        return conv.id;
      }
    }

    // Also check old 'chats' collection format and migrate if found
    try {
      final oldChats = await _db
          .collection('chats')
          .where('users', arrayContains: currentUserId)
          .get();

      for (var chat in oldChats.docs) {
        final users = List<String>.from(chat.data()['users'] ?? []);
        if (users.contains(otherUserId)) {
          // Migrate to new format
          final chatId = chat.id;
          final oldData = chat.data();
          
          // Create in new format
          final newConvRef = await _db.collection('conversations').add({
            'participants': users,
            'orderId': orderId,
            'orderTitle': orderTitle ?? oldData['orderTitle'] ?? '',
            'lastMessage': oldData['lastMessage'] ?? 'Conversation started',
            'lastMessageTime': oldData['lastMessageTime'] ?? FieldValue.serverTimestamp(),
            'unreadCount': {
              currentUserId: 0,
              otherUserId: 0,
            },
            'companyCode': companyCode,
            'createdAt': oldData['createdAt'] ?? FieldValue.serverTimestamp(),
          });

          // Migrate messages
          final messagesSnapshot = await _db
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .get();

          for (var msgDoc in messagesSnapshot.docs) {
            await _db
                .collection('conversations')
                .doc(newConvRef.id)
                .collection('messages')
                .add(msgDoc.data());
          }

          return newConvRef.id;
        }
      }
    } catch (e) {
      print('Error checking old chats format: $e');
      // Continue with creating new conversation
    }

    // Create new conversation
    final conversationRef = await _db.collection('conversations').add({
      'participants': [currentUserId, otherUserId],
      'orderId': orderId,
      'orderTitle': orderTitle ?? '',
      'lastMessage': 'Conversation started',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': {
        currentUserId: 0,
        otherUserId: 0,
      },
      'companyCode': companyCode,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return conversationRef.id;
  }

  // Send a message
  Future<void> sendMessage(
    String conversationId,
    String message, {
    String? imageUrl,
    String messageType = 'text',
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be logged in to send messages');
    }

    // Add message to subcollection
    await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .add({
      'message': message,
      'senderId': currentUser.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'imageUrl': imageUrl,
      'messageType': messageType,
      'readBy': [currentUser.uid],
    });

    // Get conversation participants
    final conversationDoc = await _db.collection('conversations').doc(conversationId).get();
    final conversationData = conversationDoc.data();
    if (conversationData == null) return;

    final participants = List<String>.from(conversationData['participants'] ?? []);
    final unreadCount = Map<String, dynamic>.from(conversationData['unreadCount'] ?? {});

    // Update unread counts (mark as unread for other participants)
    for (var participantId in participants) {
      if (participantId != currentUser.uid) {
        unreadCount[participantId] = (unreadCount[participantId] ?? 0) + 1;
      }
    }

    // Update conversation with last message info
    await _db.collection('conversations').doc(conversationId).update({
      'lastMessage': message,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': unreadCount,
    });
  }

  // Get messages stream for a conversation
  Stream<QuerySnapshot> getMessages(String conversationId) {
    return _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Mark messages as read
  Future<void> markMessagesAsRead(String conversationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final messagesQuery = await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('senderId', isNotEqualTo: currentUser.uid)
        .get();

    // Get unread messages (messages not in readBy)
    final unreadMessages = messagesQuery.docs.where((doc) {
      final data = doc.data();
      final readBy = List<String>.from(data['readBy'] ?? []);
      return !readBy.contains(currentUser.uid);
    }).toList();

    // Update unread messages
    for (var messageDoc in unreadMessages) {
      await messageDoc.reference.update({
        'readBy': FieldValue.arrayUnion([currentUser.uid]),
      });
    }

    // Reset unread count for current user
    final conversationDoc = await _db.collection('conversations').doc(conversationId).get();
    final conversationData = conversationDoc.data();
    if (conversationData != null) {
      final unreadCount = Map<String, dynamic>.from(conversationData['unreadCount'] ?? {});
      unreadCount[currentUser.uid] = 0;

      await _db.collection('conversations').doc(conversationId).update({
        'unreadCount': unreadCount,
      });
    }
  }

  // Get all conversations for current user (checks both new and old formats)
  Stream<QuerySnapshot> getUserConversations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    // Query conversations collection (new format)
    // Query without orderBy to avoid index requirement, we'll sort client-side
    // This will return conversations from 'conversations' collection
    // Old 'chats' collection will be handled separately in inbox if needed
    return _db
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots();
  }

  // Get conversations from old 'chats' collection format
  Stream<QuerySnapshot> getOldChats() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _db
        .collection('chats')
        .where('users', arrayContains: currentUser.uid)
        .snapshots();
  }

  // Get user details
  Future<Map<String, dynamic>?> getUserDetails(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      if (!userDoc.exists) return null;

      final data = userDoc.data();
      return {
        'name': data?['name'] ?? '',
        'email': data?['email'] ?? '',
        'profileImageUrl': data?['profileImageUrl'],
        'companyCode': data?['companyCode'],
      };
    } catch (e) {
      print('Error getting user details: $e');
      return null;
    }
  }

  // Search conversations
  Future<List<QueryDocumentSnapshot>> searchConversations(String query) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return [];

    try {
      final conversations = await _db
          .collection('conversations')
          .where('participants', arrayContains: currentUser.uid)
          .get();

      final results = <QueryDocumentSnapshot>[];
      final queryLower = query.toLowerCase();

      for (var conv in conversations.docs) {
        final data = conv.data();
        final lastMessage = (data['lastMessage'] ?? '').toString().toLowerCase();
        final orderTitle = (data['orderTitle'] ?? '').toString().toLowerCase();

        if (lastMessage.contains(queryLower) || orderTitle.contains(queryLower)) {
          results.add(conv);
        }
      }

      return results;
    } catch (e) {
      print('Error searching conversations: $e');
      return [];
    }
  }

  // Test conversation setup (for debugging)
  void testConversationSetup(String conversationId) {
    print('🧪 Testing conversation: $conversationId');
    _db.collection('conversations').doc(conversationId).get().then((doc) {
      if (doc.exists) {
        print('✅ Conversation exists: ${doc.data()}');
      } else {
        print('❌ Conversation does not exist');
      }
    });
  }
}

