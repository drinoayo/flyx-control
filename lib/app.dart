import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'repositories/router_repository.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'state/appearance_scope.dart';
import 'screens/app_shell.dart';
import 'screens/connect_router_screen.dart';

class FlyxApp extends StatefulWidget {
  const FlyxApp({
    super.key,
    required this.repository,
    required this.initiallyConfigured,
    required this.initialThemeMode,
  });

  final RouterRepository repository;
  final bool initiallyConfigured;
  final ThemeMode initialThemeMode;

  @override
  State<FlyxApp> createState() => _FlyxAppState();
}

class _FlyxAppState extends State<FlyxApp> {
  late final AppController controller;
  late final AppearanceController appearance;

  @override
  void initState() {
    super.initState();
    controller = AppController(repository: widget.repository);
    appearance = AppearanceController(
      initialMode: widget.initialThemeMode,
    );
    if (widget.initiallyConfigured) {
      controller.start();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appearance,
      builder: (context, themeMode, _) {
        return AppearanceScope(
          controller: appearance,
          child: AppScope(
            controller: controller,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'FlyX Control',
              theme: FlyxTheme.light(),
              darkTheme: FlyxTheme.dark(),
              themeMode: themeMode,
              home: widget.initiallyConfigured
                  ? const AppShell()
                  : const ConnectRouterScreen(),
            ),
          ),
        );
      },
    );
  }
}
