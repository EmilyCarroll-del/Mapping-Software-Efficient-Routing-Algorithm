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
      throw Exception('User must be logged in to create a conversation');
    }

    final currentUserId = currentUser.uid.trim();
    otherUserId = otherUserId.trim();
    orderId = orderId?.trim();

    // --- Start: New, Corrected Logic ---

    // 1. Build the base query to find conversations the current user is part of.
    // This query is secure and will be allowed by your security rules.
    Query query = _db
        .collection('conversations')
        .where('participants', arrayContains: currentUserId);

    // 2. Add a filter for the specific orderId, if provided.
    if (orderId != null && orderId.isNotEmpty) {
      query = query.where('orderId', isEqualTo: orderId);
    } else {
      // For generic chats, ensure we don't accidentally match an order-specific chat.
      query = query.where('orderId', isEqualTo: null);
    }

    final querySnapshot = await query.get();

    // 3. From the results, find the specific conversation that includes the other user.
    final existingConvo = querySnapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final participants = List<String>.from(data?['participants'] ?? []);
      return participants.contains(otherUserId);
    }).toList();


    if (existingConvo.isNotEmpty) {
      final conversationId = existingConvo.first.id;
      // If found, ensure display names are up to date and return the ID.
      await ensureDisplayNames(conversationId, [currentUserId, otherUserId]);
      return conversationId;
    }

    // --- End: New, Corrected Logic ---

    // 4. If no conversation exists, create a new one.
    print('No existing conversation found. Creating a new one.');

    // Get user details for display names
    final currentUserDetails = await getUserDetails(currentUserId);
    final otherUserDetails = await getUserDetails(otherUserId);
    final companyCode = currentUserDetails?['companyCode'] as String?;

    // For deterministic keys if needed elsewhere, though not for primary lookup.
    final sortedIds = [currentUserId, otherUserId]..sort();
    final participantsKey = '${sortedIds[0]}_${sortedIds[1]}';
    final participantsOrderKey = (orderId != null && orderId.isNotEmpty)
        ? '${participantsKey}_$orderId'
        : null;

    final conversationRef = await _db.collection('conversations').add({
      'participants': [currentUserId, otherUserId],
      'participantsKey': participantsKey, // Kept for potential secondary lookups
      'participantsOrderKey': participantsOrderKey, // Kept for potential secondary lookups
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
      'displayNames': {
        currentUserId: currentUserDetails?['name'] ?? '',
        otherUserId: otherUserDetails?['name'] ?? '',
      },
    });

    return conversationRef.id;
  }

  // -------------------------------
  // Send a message + create recipient notification (Spark-friendly)
  // -------------------------------
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

    // 1) Write message
    final msgRef = await _db
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

    // 2) Update conversation summaries + unread counts
    final conversationDoc = await _db.collection('conversations').doc(conversationId).get();
    final conversationData = conversationDoc.data();
    if (conversationData == null) return;

    final participants = List<String>.from(conversationData['participants'] ?? []);
    final unreadCount = Map<String, dynamic>.from(conversationData['unreadCount'] ?? {});
    for (var participantId in participants) {
      if (participantId != currentUser.uid) {
        unreadCount[participantId] = (unreadCount[participantId] ?? 0) + 1;
      }
    }

    await _db.collection('conversations').doc(conversationId).update({
      'lastMessage': (messageType == 'image' && (message == 'Photo' || message.isEmpty))
          ? '📷 Photo'
          : message,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': unreadCount,
    });

    // 3) Create recipient notification doc(s) immediately (Spark: no Functions)
    final senderDetails = await getUserDetails(currentUser.uid);
    final senderName = senderDetails?['name'] ?? senderDetails?['email'] ?? 'User';
    final preview = (messageType == 'image')
        ? '📷 Photo'
        : (message.length > 120 ? '${message.substring(0, 120)}…' : message);

    final otherUserIds = participants.where((id) => id != currentUser.uid).toList();
    for (final recipientId in otherUserIds) {
      await _db.collection('notifications').add({
        'userId': recipientId,
        'type': 'message',
        'title': 'New message from $senderName',
        'message': preview,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'actionType': 'open_chat',
        'actionData': {
          'conversationId': conversationId,
          'otherUserId': currentUser.uid,
        },
        'metadata': {
          'senderName': senderName,
          'senderId': currentUser.uid,
          'messageId': msgRef.id,
        },
      });
    }
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

    final unreadMessages = messagesQuery.docs.where((doc) {
      final data = doc.data();
      final readBy = List<String>.from(data['readBy'] ?? []);
      return !readBy.contains(currentUser.uid);
    }).toList();

    for (var messageDoc in unreadMessages) {
      await messageDoc.reference.update({
        'readBy': FieldValue.arrayUnion([currentUser.uid]),
      });
    }

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

  // Get all conversations for current user (no orderBy; sort client-side)
  Stream<QuerySnapshot> getUserConversations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }
    return _db
        .collection('conversations')
        .where('participants', arrayContains: currentUser.uid)
        .snapshots();
  }

  // Old-format chats
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
      final firstName = (data?['first_name'] ?? data?['firstName'] ?? data?['firstname'] ?? '').toString();
      final lastName = (data?['last_name'] ?? data?['lastName'] ?? data?['lastname'] ?? '').toString();
      final fullNameAlt = (data?['full_name'] ?? data?['fullName'] ?? '').toString();
      final userNameAlt = (data?['userName'] ?? data?['username'] ?? '').toString();
      final composedName = (firstName.isNotEmpty || lastName.isNotEmpty)
          ? ('$firstName $lastName').trim()
          : '';
      String name = (data?['name'] as String?) ?? composedName;
      if (name.isEmpty) name = fullNameAlt;
      if (name.isEmpty) name = userNameAlt;
      final email = (data?['email'] as String?) ?? '';

      return {
        'name': (name.isNotEmpty) ? name : (email.isNotEmpty ? email : 'User'),
        'email': email,
        'profileImageUrl': data?['profileImageUrl'],
        'companyCode': data?['companyCode'],
        'userType': data?['userType'],
      };
    } catch (e) {
      print('Error getting user details: $e');
      return null;
    }
  }

  // Ensure displayNames map on conversation contains up-to-date names
  Future<void> ensureDisplayNames(String conversationId, List<String> participantIds) async {
    try {
      final convRef = _db.collection('conversations').doc(conversationId);
      final convSnap = await convRef.get();
      if (!convSnap.exists) return;
      final data = convSnap.data() as Map<String, dynamic>;
      final existing = Map<String, dynamic>.from(data['displayNames'] ?? {});
      bool changed = false;
      for (final uid in participantIds) {
        final details = await getUserDetails(uid);
        final resolved = details?['name'] ?? '';
        if ((existing[uid] as String?) != resolved && resolved.isNotEmpty) {
          existing[uid] = resolved;
          changed = true;
        }
      }
      if (changed) {
        await convRef.update({'displayNames': existing});
      }
    } catch (e) {
      print('ensureDisplayNames error for $conversationId: $e');
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

  // Delete a conversation and all of its messages (batched)
  Future<void> deleteConversation(String conversationId) async {
    try {
      const int batchSize = 400;
      while (true) {
        final snap = await _db
            .collection('conversations')
            .doc(conversationId)
            .collection('messages')
            .limit(batchSize)
            .get();
        if (snap.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
      await _db.collection('conversations').doc(conversationId).delete();
    } catch (e) {
      print('Error deleting conversation $conversationId: $e');
      rethrow;
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
