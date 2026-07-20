import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

/// Auth lewat Supabase (Google/Apple OAuth redirect). Provider dikonfigurasi di
/// dashboard Supabase. Getter null dipertahankan untuk test dan demo eksplisit;
/// konfigurasi production yang hilang dihentikan oleh layar error saat startup.
class AuthService {
  AuthService._();

  static GoTrueClient? get _auth {
    try {
      return Supabase.instance.client.auth;
    } catch (_) {
      return null; // Belum di-initialize: hanya valid selama test/demo bootstrap.
    }
  }

  /// True hanya bila Supabase sudah di-initialize. Test yang tidak memanggil
  /// `Supabase.initialize` tetap dapat memakai jalur FakeBackend eksplisit.
  static bool get isConfigured => _auth != null;
  static bool get isSignedIn => _auth?.currentSession != null;
  static bool get isDemoMode => Env.demoMode;
  static Session? get currentSession => _auth?.currentSession;
  static User? get currentUser => _auth?.currentUser;

  static Stream<AuthState>? get onAuthStateChange => _auth?.onAuthStateChange;

  static Future<bool> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) return false;
    return auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Env.authRedirect,
    );
  }

  static Future<bool> signInWithApple() async {
    final auth = _auth;
    if (auth == null) return false;
    return auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: Env.authRedirect,
    );
  }

  static Future<void> signOut() async {
    await _auth?.signOut(scope: SignOutScope.local);
  }

  /// Mengembalikan sesi startup yang siap dipakai. Sesi tersimpan dapat masih
  /// membawa access token kedaluwarsa ketika proses baru dibuka, jadi refresh
  /// diselesaikan sebelum bootstrap profil dan toko dimulai.
  static Future<Session?> restoreValidSession() async {
    final auth = _auth;
    if (auth == null) return null;
    final session = auth.currentSession;
    if (session == null || !session.isExpired) return session;
    final response = await auth.refreshSession(session.refreshToken);
    return response.session ?? auth.currentSession;
  }
}
