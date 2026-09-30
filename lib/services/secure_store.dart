import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

class SecureRouterStore {
  const SecureRouterStore();

  static const _storage = FlutterSecureStorage();
  static const _hostKey = 'flyx.host';
  static const _userKey = 'flyx.username';
  static const _passwordKey = 'flyx.password';

  Future<void> save(RouterConnectionConfig config) async {
    await _storage.write(key: _hostKey, value: config.host);
    await _storage.write(key: _userKey, value: config.username);
    await _storage.write(key: _passwordKey, value: config.password);
  }

  Future<RouterConnectionConfig?> load() async {
    final host = await _storage.read(key: _hostKey);
    final username = await _storage.read(key: _userKey);
    final password = await _storage.read(key: _passwordKey);
    if (host == null || password == null) return null;
    return RouterConnectionConfig(
      host: host,
      username: username ?? 'admin',
      password: password,
    );
  }

  Future<void> clear() => _storage.deleteAll();
}
