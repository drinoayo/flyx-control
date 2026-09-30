import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'repositories/router_repository.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'screens/app_shell.dart';

class FlyxApp extends StatefulWidget {
  const FlyxApp({
    super.key,
    required this.repository,
  });

  final RouterRepository repository;

  @override
  State<FlyxApp> createState() => _FlyxAppState();
}

class _FlyxAppState extends State<FlyxApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController(repository: widget.repository)..start();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FlyX Control',
        theme: FlyxTheme.light(),
        darkTheme: FlyxTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    );
  }
}
