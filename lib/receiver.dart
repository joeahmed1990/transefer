import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const kPort = 40405; // HTTP
const kDiscoveryPort = 40404; // UDP

/// نسخة الكمبيوتر: تستقبل الملفات وتحفظها في Downloads/PhoneTransfer
class ReceiverPage extends StatefulWidget {
  const ReceiverPage({super.key});
  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  String ip = '...';
  String savePath = '';
  final log = <String>[];
  late Directory saveDir;
  HttpServer? _server;
  RawDatagramSocket? _udp;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final dl = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    saveDir = Directory(p.join(dl.path, 'PhoneTransfer'));
    await saveDir.create(recursive: true);

    final addrs = (await NetworkInterface.list(type: InternetAddressType.IPv4))
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .toList();
    ip = addrs.firstWhere((a) => a.startsWith('192.168.'),
        orElse: () => addrs.isNotEmpty ? addrs.first : '127.0.0.1');

    _server = await HttpServer.bind(InternetAddress.anyIPv4, kPort);
    _server!.listen(_handle);

    // اكتشاف تلقائي: الموبايل يبعت broadcast والكمبيوتر يرد
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kDiscoveryPort);
    _udp!.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = _udp!.receive();
      if (d != null && String.fromCharCodes(d.data) == 'PT_DISCOVER') {
        _udp!.send('PT_HERE'.codeUnits, d.address, d.port);
      }
    });

    if (mounted) setState(() => savePath = saveDir.path);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.method != 'PUT') {
        res.statusCode = 405;
        return;
      }
      // تنظيف المسار لمنع الخروج من فولدر الحفظ
      final parts = (req.uri.queryParameters['path'] ?? '')
          .replaceAll('\\', '/')
          .split('/')
          .where((s) => s.isNotEmpty && s != '.' && s != '..')
          .map((s) => s.replaceAll(RegExp(r'[<>:"|?*]'), '_'))
          .toList();
      if (parts.isEmpty) {
        res.statusCode = 400;
        return;
      }
      final file = File(p.joinAll([saveDir.path, ...parts]));
      await file.parent.create(recursive: true);
      await req.pipe(file.openWrite()); // بث مباشر للقرص، مفيش تحميل في الرام
      if (mounted) setState(() => log.insert(0, '✓ ${parts.join('/')}'));
    } catch (e) {
      res.statusCode = 500;
      if (mounted) setState(() => log.insert(0, '✗ $e'));
    } finally {
      await res.close();
    }
  }

  @override
  void dispose() {
    _server?.close(force: true);
    _udp?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('استقبال الملفات')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('عنوان الكمبيوتر: $ip', style: t.titleMedium),
          const SizedBox(height: 8),
          Text('بيتحفظ في: $savePath'),
          const Divider(height: 32),
          Text('آخر الملفات المستلمة', style: t.titleSmall),
          Expanded(
            child: ListView.builder(
              itemCount: log.length,
              itemBuilder: (_, i) => Text(log[i]),
            ),
          ),
        ]),
      ),
    );
  }
}
