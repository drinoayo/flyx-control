import 'package:flutter/material.dart';

import 'app.dart';
import 'repositories/mock_router_repository.dart';
import 'repositories/router_repository.dart';
import 'repositories/zlt_router_repository.dart';
import 'services/secure_store.dart';
import 'services/zlt_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final saved = await const SecureRouterStore().load();
  final configured = saved != null;
  RouterRepository repository = MockRouterRepository();

  if (saved != null) {
    repository = ZltRouterRepository(
      client: ZltClient(host: saved.host),
      username: saved.username,
      password: saved.password,
    );
  }

  runApp(
    FlyxApp(
      repository: repository,
      initiallyConfigured: configured,
    ),
  );
}
