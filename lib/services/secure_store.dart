import 'package:flutter/material.dart';
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

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _hostKey),
      _storage.delete(key: _userKey),
      _storage.delete(key: _passwordKey),
    ]);
  }
}


class AppearanceStore {
  const AppearanceStore();

  static const _storage = FlutterSecureStorage();
  static const _themeKey = 'flyx.theme_mode';

  Future<ThemeMode> load() async {
    final value = await _storage.read(key: _themeKey);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> save(ThemeMode mode) {
    return _storage.write(
      key: _themeKey,
      value: switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }
}
