import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'receiver.dart' show kPort, kDiscoveryPort;

class _Item {
  final File file;
  final String rel;
  _Item(this.file, this.rel);
}

/// نسخة الموبايل: تبعت ملفات/فولدرات، وتكمل في الخلفية بفضل Foreground Service
class SenderPage extends StatefulWidget {
  const SenderPage({super.key});
  @override
  State<SenderPage> createState() => _SenderPageState();
}

class _SenderPageState extends State<SenderPage> {
  final ip = TextEditingController();
  String status = 'جاهز';
  double progress = 0;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'transfer',
        channelName: 'نقل الملفات',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true, // يمنع الموبايل من النوم أثناء النقل
        allowWifiLock: true, // يبقي الواي فاي شغال
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _permissions());
  }

  Future<void> _permissions() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.requestNotificationPermission();
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    await Permission.manageExternalStorage.request(); // لقراءة الفولدرات
  }

  Future<String?> _discover() async {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.broadcastEnabled = true;
    final c = Completer<String?>();
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = s.receive();
      if (d != null && !c.isCompleted) c.complete(d.address.address);
    });
    s.send('PT_DISCOVER'.codeUnits, InternetAddress('255.255.255.255'),
        kDiscoveryPort);
    final r = await c.future
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    s.close();
    return r;
  }

  Future<void> _find() async {
    setState(() => status = 'جارٍ البحث عن الكمبيوتر...');
    final found = await _discover();
    setState(() {
      if (found != null) ip.text = found;
      status = found != null
          ? 'تم العثور على الكمبيوتر'
          : 'مش لاقي الكمبيوتر، اكتب العنوان بإيدك';
    });
  }

  Future<void> _sendFiles() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    await _upload([
      for (final f in files)
        if (f.path != null) _Item(File(f.path!), f.name)
    ]);
  }

  Future<void> _sendFolder() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return;
    final base = p.basename(dir);
    final items = <_Item>[];
    await for (final e in Directory(dir).list(recursive: true)) {
      if (e is File) {
        final rel = p.relative(e.path, from: dir).replaceAll('\\', '/');
        items.add(_Item(e, '$base/$rel'));
      }
    }
    await _upload(items);
  }

  Future<void> _upload(List<_Item> items) async {
    if (items.isEmpty || busy) return;
    if (ip.text.trim().isEmpty) {
      setState(() => status = 'دوس «بحث» أو اكتب عنوان الكمبيوتر الأول');
      return;
    }
    setState(() {
      busy = true;
      progress = 0;
    });
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'جارٍ نقل الملفات',
      notificationText: 'بدء النقل...',
    );

    final client = HttpClient();
    var total = 0;
    for (final i in items) {
      total += await i.file.length();
    }
    var sent = 0, done = 0;
    final clock = Stopwatch()..start();
    try {
      for (final it in items) {
        final req = await client.putUrl(
            Uri.http('${ip.text.trim()}:$kPort', '/upload', {'path': it.rel}));
        req.contentLength = await it.file.length();
        await req.addStream(it.file.openRead().map((chunk) {
          sent += chunk.length;
          if (clock.elapsedMilliseconds > 800) {
            clock.reset();
            final pct = total == 0 ? 1.0 : sent / total;
            if (mounted) setState(() => progress = pct);
            FlutterForegroundTask.updateService(
              notificationText:
                  '${(pct * 100).toStringAsFixed(0)}%  •  ${done + 1}/${items.length}',
            );
          }
          return chunk;
        }));
        final res = await req.close();
        await res.drain();
        if (res.statusCode != 200) {
          throw Exception('خطأ ${res.statusCode} في ${it.rel}');
        }
        done++;
        if (mounted) {
          setState(() {
            status = 'تم $done من ${items.length}';
            progress = total == 0 ? 1.0 : sent / total;
          });
        }
      }
      if (mounted) setState(() => status = 'اكتمل نقل $done ملف ✓');
    } catch (e) {
      if (mounted) setState(() => status = 'فشل: $e');
    } finally {
      client.close();
      await FlutterForegroundTask.stopService();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إرسال للكمبيوتر')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: ip,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'عنوان الكمبيوتر', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
                onPressed: busy ? null : _find, child: const Text('بحث')),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _sendFiles,
                icon: const Icon(Icons.insert_drive_file),
                label: const Text('ملفات'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _sendFolder,
                icon: const Icon(Icons.folder),
                label: const Text('فولدر'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          LinearProgressIndicator(value: busy ? progress : 0),
          const SizedBox(height: 12),
          Text(status),
        ]),
      ),
    );
  }
}
