import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps Supabase sessions and PKCE verifiers in platform-secure storage.
///
/// Existing v2 sessions are migrated from SharedPreferences on first startup.
/// The old value is removed only after the secure copy has been read back and
/// verified, so a failed migration does not silently sign the user out.
class SecureSupabaseStorage extends LocalStorage implements GotrueAsyncStorage {
  SecureSupabaseStorage({required this.persistSessionKey});

  final String persistSessionKey;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'supabase_auth_secure',
      preferencesKeyPrefix: 'supabase_auth_',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      accountName: 'supabase_auth',
      synchronizable: false,
    ),
  );

  static const _pkceVerifierKey = 'supabase.auth.token-code-verifier';
  Future<void>? _initialization;

  @override
  Future<void> initialize() => _initialization ??= _migrateLegacyCredentials();

  Future<void> _migrateLegacyCredentials() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in <String>[persistSessionKey, _pkceVerifierKey]) {
      final legacyValue = preferences.getString(key);
      if (legacyValue == null) continue;

      final secureValue = await _storage.read(key: key);
      if (secureValue == null) {
        await _storage.write(key: key, value: legacyValue);
        final migratedValue = await _storage.read(key: key);
        if (migratedValue != legacyValue) {
          throw StateError('No se pudo verificar la migración segura de Auth.');
        }
      }
      await preferences.remove(key);
      if (preferences.get(key) != null) {
        throw StateError('No se pudo limpiar la copia antigua de Auth.');
      }
    }
  }

  @override
  Future<bool> hasAccessToken() async =>
      await _storage.read(key: persistSessionKey) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() =>
      _storage.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: persistSessionKey, value: persistSessionString);

  @override
  Future<String?> getItem({required String key}) => _storage.read(key: key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> removeItem({required String key}) => _storage.delete(key: key);
}
