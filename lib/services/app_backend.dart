import '../data/backend/backend.dart';
import '../data/backend/fake_backend.dart';
import '../data/backend/supabase_backend.dart';

/// Pemilih backend aktif. Instance awal mendukung test/bootstrap; `main()`
/// memilih [SupabaseBackend] untuk build normal atau [FakeBackend] hanya saat
/// `SAVEBITE_DEMO=true` diminta eksplisit.
Backend backend = FakeBackend();

void useSupabaseBackend() => backend = SupabaseBackend();

void useFakeBackend() => backend = FakeBackend();
