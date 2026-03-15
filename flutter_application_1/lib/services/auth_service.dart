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
        final email = user.email!;
        
        // 5. Check if user already exists in Firestore by UID
        UserModel? existingUser = await _firestoreService.getUser(user.uid);
        
        // 6. AD-HOC DATA INHERITANCE: If UID match fails, check if an account exists with the same email
        if (existingUser == null) {
          final results = await _firestoreService.searchUsers(email);
          if (results.isNotEmpty) {
             // We found an account with the same email.
             // Inherit their existing profile data to ensure consistency.
             final inherited = results.first;
             existingUser = inherited;
             
             // Create/Update the new Google UID record with inherited data
             await _firestoreService.updateUser(UserModel(
               uid: user.uid,
               email: email,
               username: inherited.username,
               displayName: inherited.displayName,
               photoUrl: inherited.photoUrl, // Keep existing pic!
             ));
          }
        }
        
        if (existingUser == null) {
          // Truly New user: Create with Google info
          await _firestoreService.updateUser(UserModel(
            uid: user.uid,
            email: email,
            displayName: user.displayName ?? 'User',
            photoUrl: user.photoURL,
          ));
        }
      }

      return user;
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
