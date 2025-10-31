import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
    ],
  );

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sign in with Google
  static Future<UserCredential?> signInWithGoogle() async {
    try {
      print('Starting Google Sign-In...');
      
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        print('User cancelled Google Sign-In');
        return null;
      }

      print('Google user obtained: ${googleUser.email}');
      
      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      print('Google auth tokens obtained');
      print('Access token: ${googleAuth.accessToken?.substring(0, 20)}...');
      print('ID token: ${googleAuth.idToken?.substring(0, 20)}...');

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      print('Firebase credential created');

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      
      print('Firebase sign-in successful: ${userCredential.user?.email}');
      
      // Save user data to Firestore if it's a new user
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        print('New user detected, saving to Firestore...');
        await _saveUserToFirestore(userCredential.user!);
        print('User saved to Firestore');
      } else {
        // Update last sign-in time for existing users
        await updateLastSignIn();
      }

      return userCredential;
    } catch (e) {
      print('Google Sign-In Error Details: $e');
      print('Error type: ${e.runtimeType}');
      
      // Handle specific type casting errors (known issue with google_sign_in package)
      if (e.toString().contains('PigeonUserDetails') || 
          e.toString().contains('type \'List<Object?>\' is not a subtype')) {
        print('Type casting error detected - this is a known issue with google_sign_in package');
        // Wait a moment for auth state to update
        await Future.delayed(const Duration(milliseconds: 300));
        // Check if user is actually signed in despite the error
        final user = _auth.currentUser;
        if (user != null) {
          print('User is already signed in despite error: ${user.email}');
          // Update last sign-in time
          await updateLastSignIn();
          // Return null to indicate success but let the app handle the redirect
          // The app will check currentUser and redirect accordingly
          return null;
        }
      }
      
      rethrow;
    }
  }

  /// Sign out from Google and Firebase
  static Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } catch (e) {
      print('Sign out error: $e');
      rethrow;
    }
  }

  /// Check if user is currently signed in with Google
  static bool isSignedInWithGoogle() {
    final user = _auth.currentUser;
    return user != null && user.providerData.any((provider) => provider.providerId == 'google.com');
  }

  /// Get current Google user
  static GoogleSignInAccount? getCurrentGoogleUser() {
    return _googleSignIn.currentUser;
  }

  /// Save user data to Firestore
  static Future<void> _saveUserToFirestore(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'first_name': user.displayName?.split(' ').first ?? '',
        'last_name': user.displayName?.split(' ').last ?? '',
        'email': user.email ?? '',
        'photo_url': user.photoURL ?? '',
        'provider': 'google',
        'userType': 'driver', // Mobile app users are always drivers
        'created_at': Timestamp.now(),
        'last_sign_in': Timestamp.now(),
        'role': 'Driver',
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving user to Firestore: $e');
      rethrow;
    }
  }

  /// Update last sign-in time
  static Future<void> updateLastSignIn() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'last_sign_in': Timestamp.now(),
          'role': 'Driver',
        });
      }
    } catch (e) {
      print('Error updating last sign-in: $e');
    }
  }
}
