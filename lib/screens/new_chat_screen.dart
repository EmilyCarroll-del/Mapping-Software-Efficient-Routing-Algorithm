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

  // Finds or creates a chat with the selected user and navigates to it
  Future<void> _startChatWithUser(String otherUserId, String otherUserName) async {
    if (currentUser == null) return;
    final currentUserId = currentUser!.uid;

    // Prevent starting a chat with oneself
    if (currentUserId == otherUserId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot start a chat with yourself.')),
        );
      }
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Create or get conversation using ChatService
      final conversationId = await _chatService.createOrGetConversation(otherUserId);

      if (mounted) {
        Navigator.pop(context); // Close loading
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              conversationId: conversationId,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting chat: ${e.toString()}'),
            backgroundColor: Colors.red,
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
          
          // Get current user's data
          final user = currentUser;
          if (users.isEmpty || user == null) {
            return const Center(child: Text('No users available'));
          }
          
          final currentUserDoc = users.firstWhere(
            (doc) => doc.id == user.uid,
            orElse: () => users.first,
          );
          final currentUserData = currentUserDoc.data() as Map<String, dynamic>?;
          final currentCompanyCode = currentUserData?['companyCode'] as String?;
          final currentUserType = currentUserData?['userType'] as String?;
          
          // Filter users following company code rules:
          // - Drivers with companyCode can only see admins from same company
          // - Freelance drivers (no companyCode) can see all admins
          // - Never show other drivers
          // Note: All admins MUST have a companyCode (enforced in web app signup)
          final otherUsers = users.where((doc) {
            if (doc.id == currentUser?.uid) return false;
            
            final userData = doc.data() as Map<String, dynamic>?;
            final userType = userData?['userType'] as String?;
            final userCompanyCode = userData?['companyCode'] as String?;
            
            // If current user is a driver, only show admins
            if (currentUserType == 'driver') {
              // Never show other drivers
              if (userType == 'driver') return false;
              
              // If driver has company code, only show admins from same company
              if (currentCompanyCode != null && currentCompanyCode.isNotEmpty) {
                return userCompanyCode == currentCompanyCode;
              }
              
              // Freelance drivers can see all admins
              return userType == 'admin';
            }
            
            // For admins (shouldn't happen in mobile app, but handle gracefully)
            return true;
          }).toList();

          if (otherUsers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No users found',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentCompanyCode != null && currentCompanyCode.isNotEmpty
                        ? 'No admins from your company available'
                        : currentUserType == 'driver'
                            ? 'No admins available'
                            : 'No other users available',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: otherUsers.length,
            itemBuilder: (context, index) {
              final userDoc = otherUsers[index];
              final userData = userDoc.data() as Map<String, dynamic>?;
              final userName = userData?['name'] ?? 
                               userData?['email'] ?? 
                               'Unknown User';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[300],
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
                title: Text(userName),
                subtitle: userData?['email'] != null 
                    ? Text(userData!['email'], style: TextStyle(fontSize: 12, color: Colors.grey[600]))
                    : null,
                onTap: () => _startChatWithUser(userDoc.id, userName),
              );
            },
          );
        },
      ),
    );
  }
}
