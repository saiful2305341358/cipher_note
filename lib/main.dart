import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'core/errors/app_exceptions.dart';
import 'core/startup/app_initializer.dart';
import 'core/startup/startup_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Noto Sans Bengali'], license);
  });

  // The database is opened before the app starts so no screen can reach an
  // unopened box. If it fails, an error screen with a retry is shown instead.
  Widget app;
  try {
    app = buildApp(await AppInitializer.initialize());
  } on AppException catch (error) {
    app = StartupErrorApp(error: error);
  }
  runApp(app);
}
