import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'core.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) FlutterForegroundTask.initCommunicationPort();
  await core.init();
  runApp(const App());
}
