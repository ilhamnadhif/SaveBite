import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

/// Auth lewat Supabase (Google OAuth redirect). Provider dikonfigurasi di
/// dashboard Supabase. Saat offline (Supabase belum di-init), semua getter
/// aman (false/null) sehingga app tetap jalan memakai FakeBackend.
class AuthService {
  AuthService._();

  static GoTrueClient? get _auth {
    try {
      return Supabase.instance.client.auth;
    } catch (_) {
      return null; // Supabase belum di-initialize (mode offline)
    }
  }

  /// True hanya bila Supabase sudah di-initialize (mode online). Di test —
  /// yang tak memanggil Supabase.initialize — ini false sehingga login memakai
  /// jalur offline (FakeBackend).
  static bool get isConfigured => _auth != null;
  static bool get isSignedIn => _auth?.currentSession != null;
  static User? get currentUser => _auth?.currentUser;

  static Stream<AuthState>? get onAuthStateChange => _auth?.onAuthStateChange;

  static Future<void> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) return;
    await auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Env.authRedirect,
    );
  }

  static Future<void> signOut() async {
    await _auth?.signOut();
  }
}
