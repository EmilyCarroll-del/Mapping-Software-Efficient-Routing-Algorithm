import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String? email;
  final String? name;
  final String? companyId;
  final String? companyName;

  UserModel({
    required this.uid,
    this.email,
    this.name,
    this.companyId,
    this.companyName,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'] as String?,
      name: data['name'] as String?,
      companyId: data['companyId'] as String?,
      companyName: data['companyName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'companyId': companyId,
      'companyName': companyName,
    };
  }
}
