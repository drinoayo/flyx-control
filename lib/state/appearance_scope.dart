import 'package:flutter/material.dart';

import '../services/secure_store.dart';

class AppearanceController extends ValueNotifier<ThemeMode> {
  AppearanceController({
    required ThemeMode initialMode,
    AppearanceStore? store,
  })  : _store = store ?? const AppearanceStore(),
        super(initialMode);

  final AppearanceStore _store;

  Future<void> setMode(ThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    await _store.save(mode);
  }
}

class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope({
    super.key,
    required AppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppearanceController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppearanceScope>();
    assert(scope != null, 'AppearanceScope not found');
    return scope!.notifier!;
  }
}
