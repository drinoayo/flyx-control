import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'repositories/mock_router_repository.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'screens/app_shell.dart';

class FlyxApp extends StatefulWidget {
  const FlyxApp({super.key});

  @override
  State<FlyxApp> createState() => _FlyxAppState();
}

class _FlyxAppState extends State<FlyxApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController(repository: MockRouterRepository())..start();
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
