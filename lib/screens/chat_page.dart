import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/chat_service.dart';
import '../services/notification_service.dart';

class ChatPage extends StatefulWidget {
  final String conversationId; // conversationId (new) or chatId (old)
  final String otherUserId;
  final String otherUserName;
  final String? orderId;
  final String? orderTitle;
  final bool isOldFormat; // true => /chats, false => /conversations

  const ChatPage({
    Key? key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.orderId,
    this.orderTitle,
    this.isOldFormat = false,
  }) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final ChatService _chatService = ChatService();

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markMessagesAsRead() async {
    if (!widget.isOldFormat) {
      await _chatService.markMessagesAsRead(widget.conversationId);
    }
    // Old-format /chats have no read tracking
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || currentUser == null) return;

    setState(() => _isSending = true);

    try {
      if (widget.isOldFormat) {
        // Legacy /chats/* path
        final db = FirebaseFirestore.instance;

        // 1) write message
        final msgRef = await db
            .collection('chats')
            .doc(widget.conversationId)
            .collection('messages')
            .add({
          'message': text,
          'senderId': currentUser!.uid,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // 2) update chat summary
        await db.collection('chats').doc(widget.conversationId).update({
          'lastMessage': text,
          'lastMessageTime': FieldValue.serverTimestamp(),
        });

        // 3) find recipient and create notification via NotificationService
        final chatSnap =
        await db.collection('chats').doc(widget.conversationId).get();
        final users =
        List<String>.from((chatSnap.data() ?? const {})['users'] ?? const []);
        final recipientId =
        users.firstWhere((u) => u != currentUser!.uid, orElse: () => '');

        if (recipientId.isNotEmpty) {
          final senderName = (currentUser!.displayName?.trim().isNotEmpty ?? false)
              ? currentUser!.displayName!.trim()
              : (currentUser!.email ?? 'User');

          await NotificationService.instance.createChatNotificationForRecipient(
            recipientUserId: recipientId,
            conversationId: widget.conversationId,
            senderUserId: currentUser!.uid,
            senderName: senderName,
            messageId: msgRef.id,
            messageText: text,
            messageType: 'text',
            isOldFormat: true,
          );
        }
      } else {
        // New-format /conversations/*
        await _chatService.sendMessage(
          widget.conversationId,
          text,
        );
        // ChatService already writes notifications to /notifications
      }

      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _messageStream() {
    if (widget.isOldFormat) {
      return FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.conversationId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots();
    } else {
      // Uses ChatService to keep the path consistent with mobile
      return _chatService
          .getMessages(widget.conversationId)
          .map((snap) => snap as QuerySnapshot<Map<String, dynamic>>);
    }
  }

  Widget _buildMessageBubble(
      {required Map<String, dynamic> data, required bool isMe}) {
    final text = (data['message'] ?? '').toString();
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final messageType = (data['messageType'] ?? 'text').toString();

    String timeText = '';
    if (timestamp != null) {
      final now = DateTime.now();
      final diff = now.difference(timestamp);
      if (diff.inDays > 0) {
        timeText =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
      } else if (diff.inHours > 0) {
        timeText = '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        timeText = '${diff.inMinutes}m ago';
      } else {
        timeText = 'now';
      }
    }

    final isImageOnly = messageType == 'image' && text == 'Photo';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container
        (
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isImageOnly)
              Text(
                text,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
            if (timeText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                timeText,
                style: TextStyle(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderHeader() {
    if (widget.orderTitle == null || widget.orderTitle!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
      child: Row(
        children: [
          Icon(
            Icons.local_shipping,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.orderTitle!,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInputArea() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 2,
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: _isSending
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.orderTitle != null && widget.orderTitle!.isNotEmpty
        ? '${widget.otherUserName} • ${widget.orderTitle}'
        : widget.otherUserName;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          _buildOrderHeader(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messageStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child:
                    Text('Error loading messages: ${snapshot.error}'),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Say hello!'));
                }

                // Mark messages as read while viewing
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markMessagesAsRead();
                });

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // newest at bottom
                  padding: const EdgeInsets.all(8.0),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final isMe = data['senderId'] == currentUser?.uid;
                    return _buildMessageBubble(data: data, isMe: isMe);
                  },
                );
              },
            ),
          ),
          _buildMessageInputArea(),
        ],
      ),
    );
  }
}
