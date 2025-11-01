import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for managing chat conversations between users.
/// 
/// COMPANY CODE CHAT RULES:
/// Company codes are the PRIMARY way to determine who can chat with whom:
/// 
/// - Company Drivers (with companyCode): Can only chat with admins who have the same companyCode
/// - Freelance Drivers (no companyCode): Can chat with any admin
/// - Drivers: Cannot chat with other drivers
/// - Admins: Can chat with drivers based on the driver's company code (rules enforced from driver side)
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Create or get existing conversation between two users.
  /// 
  /// Enforces company code rules:
  /// - Company drivers can only chat with matching company admins
  /// - Freelance drivers can chat with any admin
  /// - Drivers cannot chat with other drivers
  Future<String> createOrGetConversation(
    String otherUserId, {
    String? orderId,
    String? orderTitle,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('User must be logged in to create conversation');
    }

    final currentUserId = currentUser.uid.trim();
    otherUserId = otherUserId.trim();
    orderId = orderId?.trim();

    // Get current user's details (company code and user type)
    String? currentCompanyCode;
    String? currentUserType;
    try {
      final currentUserDoc = await _db.collection('users').doc(currentUserId).get();
      final currentUserData = currentUserDoc.data();
      currentCompanyCode = currentUserData?['companyCode'] as String?;
      currentUserType = currentUserData?['userType'] as String?;
    } catch (e) {
      print('Error getting current user data: $e');
    }

    // Get other user's details
    String? otherCompanyCode;
    String? otherUserType;
    try {
      final otherUserDoc = await _db.collection('users').doc(otherUserId).get();
      final otherUserData = otherUserDoc.data();
      otherCompanyCode = otherUserData?['companyCode'] as String?;
      otherUserType = otherUserData?['userType'] as String?;
    } catch (e) {
      print('Error getting other user data: $e');
      throw Exception('User not found');
    }

    // Enforce company code and user type rules for chat
    // Company codes are PRIMARY identifier for determining chat permissions
    
    // If current user is a driver (mobile app user)
    if (currentUserType == 'driver') {
      // Drivers cannot chat with other drivers
      if (otherUserType == 'driver') {
        throw Exception('Drivers cannot chat with other drivers');
      }
      
      // All admins must have a companyCode (enforced in web app signup)
      // Company drivers (with companyCode) can only chat with admins from same company
      if (currentCompanyCode != null && currentCompanyCode.isNotEmpty) {
        if (otherCompanyCode != currentCompanyCode) {
          throw Exception('You can only chat with admins from your company');
        }
      }
      // Freelance drivers (no companyCode) can chat with any admin
    }
    // Admins can chat with drivers following the same rules (enforced from driver side)
    
    // Use currentCompanyCode for conversation metadata
    final companyCode = currentCompanyCode;

    // Deterministic keys for fast lookup and strict reuse
    final sortedIds = [currentUserId, otherUserId]..sort();
    final participantsKey = '${sortedIds[0]}_${sortedIds[1]}';

    if (orderId != null && orderId.isNotEmpty) {
      final participantsOrderKey = '${participantsKey}_$orderId';
      // Fast exact lookup by order-specific key
      final orderMatch = await _db
          .collection('conversations')
          .where('participantsOrderKey', isEqualTo: participantsOrderKey)
          .limit(1)
          .get();
      if (orderMatch.docs.isNotEmpty) {
        final conv = orderMatch.docs.first;
        // Ensure orderTitle and display names are set
        final data = conv.data();
        final updates = <String, dynamic>{};
        if ((data['orderTitle'] == null || (data['orderTitle'] as String).isEmpty) && orderTitle != null) {
          updates['orderTitle'] = orderTitle;
        }
        // Backfill display names map
        final displayNames = (data['displayNames'] as Map<String, dynamic>?) ?? {};
        if (!displayNames.containsKey(currentUserId) || (displayNames[currentUserId] as String?)?.isEmpty == true) {
          final me = await getUserDetails(currentUserId);
          if (me != null) displayNames[currentUserId] = me['name'] ?? '';
        }
        if (!displayNames.containsKey(otherUserId) || (displayNames[otherUserId] as String?)?.isEmpty == true) {
          final other = await getUserDetails(otherUserId);
          if (other != null) displayNames[otherUserId] = other['name'] ?? '';
        }
        if (displayNames.isNotEmpty) updates['displayNames'] = displayNames;
        if (updates.isNotEmpty) await conv.reference.update(updates);
        await ensureDisplayNames(conv.id, [currentUserId, otherUserId]);
        return conv.id;
      } else {
        // Fallback: older docs might not have the key yet. Try client-side filter.
        final possible = await _db
            .collection('conversations')
            .where('participants', arrayContains: currentUserId)
            .get();
        for (final conv in possible.docs) {
          final d = conv.data();
          final parts = List<String>.from(d['participants'] ?? []);
          final convOrderId = (d['orderId'] as String?)?.trim();
          if (parts.contains(otherUserId) && convOrderId == orderId) {
            // Backfill keys
            await conv.reference.update({
              'participantsKey': participantsKey,
              'participantsOrderKey': participantsOrderKey,
            });
            await ensureDisplayNames(conv.id, [currentUserId, otherUserId]);
            return conv.id;
          }
        }
      }
    } else {
      // Generic chat (no order)
      final genericMatch = await _db
          .collection('conversations')
          .where('participantsKey', isEqualTo: participantsKey)
          .where('orderId', isEqualTo: null)
          .limit(1)
          .get();
      if (genericMatch.docs.isNotEmpty) {
        final id = genericMatch.docs.first.id;
        await ensureDisplayNames(id, [currentUserId, otherUserId]);
        return id;
      }
    }

    // Also check old 'chats' collection format and migrate if found (only when orderId is null)
    try {
      if (orderId == null) {
        final oldChats = await _db
            .collection('chats')
            .where('users', arrayContains: currentUserId)
            .get();

        for (var chat in oldChats.docs) {
          final users = List<String>.from(chat.data()['users'] ?? []);
          if (users.contains(otherUserId)) {
            // Migrate to new format for generic chat only
            final chatId = chat.id;
            final oldData = chat.data();
            
            final newConvRef = await _db.collection('conversations').add({
              'participants': users,
              'orderId': null,
              'orderTitle': oldData['orderTitle'] ?? '',
              'lastMessage': oldData['lastMessage'] ?? 'Conversation started',
              'lastMessageTime': oldData['lastMessageTime'] ?? FieldValue.serverTimestamp(),
              'unreadCount': {
                currentUserId: 0,
                otherUserId: 0,
              },
              'companyCode': companyCode,
              'createdAt': oldData['createdAt'] ?? FieldValue.serverTimestamp(),
              'participantsKey': participantsKey,
              'participantsOrderKey': null,
              'displayNames': {
                for (final uid in users)
                  uid: (await getUserDetails(uid))?['name'] ?? ''
              },
            });

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
      }
    } catch (e) {
      print('Error checking old chats format: $e');
      // Continue with creating new conversation
    }

    // Create new conversation
    final participantsOrderKey = orderId != null && orderId.isNotEmpty
        ? '${participantsKey}_$orderId'
        : null;

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
      'participantsKey': participantsKey,
      'participantsOrderKey': participantsOrderKey,
      'displayNames': {
        currentUserId: (await getUserDetails(currentUserId))?['name'] ?? '',
        otherUserId: (await getUserDetails(otherUserId))?['name'] ?? '',
      },
    });

    await ensureDisplayNames(conversationRef.id, [currentUserId, otherUserId]);
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
      final firstName = (data?['first_name'] ?? data?['firstName'] ?? data?['firstname'] ?? '').toString();
      final lastName = (data?['last_name'] ?? data?['lastName'] ?? data?['lastname'] ?? '').toString();
      final fullNameAlt = (data?['full_name'] ?? data?['fullName'] ?? '').toString();
      final userNameAlt = (data?['userName'] ?? data?['username'] ?? '').toString();
      final composedName = (firstName.isNotEmpty || lastName.isNotEmpty)
          ? ('$firstName $lastName').trim()
          : '';
      String name = (data?['name'] as String?) ?? composedName;
      if ((name).isEmpty) name = fullNameAlt;
      if ((name).isEmpty) name = userNameAlt;
      final email = (data?['email'] as String?) ?? '';

      return {
        'name': (name.isNotEmpty) ? name : (email.isNotEmpty ? email : 'User'),
        'email': email,
        'profileImageUrl': data?['profileImageUrl'],
        'companyCode': data?['companyCode'],
        'userType': data?['userType'], // Include userType for filtering
      };
    } catch (e) {
      print('Error getting user details: $e');
      return null;
    }
  }

  // Ensure displayNames map on conversation contains up-to-date names for given participants
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


