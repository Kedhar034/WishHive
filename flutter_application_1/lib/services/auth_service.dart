import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? '371898205121-7in762okpr7hr6mnp0itkqc4fptd5fce.apps.googleusercontent.com' : null,
    serverClientId: '371898205121-7in762okpr7hr6mnp0itkqc4fptd5fce.apps.googleusercontent.com',
  );
  final FirestoreService _firestoreService = FirestoreService();

  /// Sign in with Google and update/create user in Firestore.
  Future<User?> signInWithGoogle() async {
    try {
      // 1. Trigger the Google Authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User canceled the picker

      // 2. Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // 3. Create a new credential for Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Once signed in, return the UserCredential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // Only create a document when this UID is genuinely new. The previous
        // version searched by email and copied another account's username,
        // display name and photo onto the new UID — without its friends, hives
        // or wishes — so users saw their own name and concluded their data had
        // been deleted, while two accounts claimed the same username.
        final existingUser = await _firestoreService.getUser(user.uid);
        if (existingUser == null) {
          await _firestoreService.updateUser(UserModel(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName ?? 'User',
            photoUrl: user.photoURL,
          ));
        }
      }

      return user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        throw Exception(
          'An account already exists with this email. Sign in with your '
          'original method first, then link Google from Settings.',
        );
      }
      debugPrint('Error during Google Sign-In: ${e.code} ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error during Google Sign-In: $e');
      rethrow;
    }
  }

  /// Sign out from both Firebase and Google
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      debugPrint('Error during sign out: $e');
      rethrow;
    }
  }
}
