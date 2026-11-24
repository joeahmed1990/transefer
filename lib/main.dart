import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'receiver.dart';
import 'sender.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final isMobile = Platform.isAndroid || Platform.isIOS;
  if (isMobile) FlutterForegroundTask.initCommunicationPort();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'نقل الملفات',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
    home: isMobile
        ? WithForegroundTask(child: const SenderPage())
        : const ReceiverPage(),
  ));
}
