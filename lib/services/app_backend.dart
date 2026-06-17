import '../data/backend/backend.dart';
import '../data/backend/fake_backend.dart';
import '../data/backend/supabase_backend.dart';

/// Pemilih backend aktif. Default [FakeBackend] (offline/test); diganti ke
/// [SupabaseBackend] di main() bila kredensial Supabase tersedia.
Backend backend = FakeBackend();

void useSupabaseBackend() => backend = SupabaseBackend();

void useFakeBackend() => backend = FakeBackend();
