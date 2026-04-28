import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. The Offline Gatekeeper
  // This instantly checks the phone's hard drive for a saved token.
  // It doesn't need an internet connection to return the user!
  User? get currentUser => _auth.currentUser;

  // 2. The Base Camp Login
  // Used when the rescuer first authenticates while connected to the Drone Tower.
  Future<String?> signInRescueTeam(String email, String password) async {
    try {
      // Upon success, Firebase automatically writes the session token to the local disk.
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null; // Null means success (no error string)
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return 'No rescue team found for that email.';
      } else if (e.code == 'wrong-password') {
        return 'Incorrect master password.';
      } else if (e.code == 'network-request-failed') {
        return 'Network Error: You must have internet for the initial login.';
      }
      return e.message; // Return generic error
    } catch (e) {
      return e.toString();
    }
  }

  // 3. The Base Camp Logout
  Future<void> signOut() async {
    await _auth.signOut();
  }
}