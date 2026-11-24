import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const kHttpPort = 40405;
const kUdpPort = 40404;
const kAppTag = 'pt1';
const kReady = 'جاهز للاستلام';

class Device {
  final String id;
  String name;
  String type;
  String ip;
  int port;
  DateTime seen;
  Device(this.id, this.name, this.type, this.ip, this.port, this.seen);
}

class Item {
  final File file;
  final String rel;
  final int size;
  Item(this.file, this.rel, this.size);
}

class Entry {
  final String text;
  final bool ok;
  Entry(this.text, this.ok);
}

final core = Core();

class Core extends ChangeNotifier {
  String id = '';
  String name = 'Device';
  String type = 'other';
  bool keepBg = true;
  String myIp = '';
  String saveDirPath = '';
  final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
  ThemeMode get themeMode => themeNotifier.value;

  final Map<String, Device> devices = {};
  final List<Item> selected = [];
  final List<Entry> history = [];

  bool sending = false;
  double sendProgress = 0;
  String sendText = '';
  bool receiving = false;
  double receiveProgress = 0;
  String receiveText = '';

  int get selectedBytes => selected.fold<int>(0, (a, b) => a + b.size);

  int _active = 0;
  int _tick = 0;
  late File _settingsFile;
  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _timer;
  Timer? _recvTimer;
  List<String> _broadcasts = ['255.255.255.255'];
  final Stopwatch _clock = Stopwatch()..start();

  // ---------------------------------------------------------------- init

  Future<void> init() async {
    type = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
            ? 'windows'
            : Platform.isLinux
                ? 'linux'
                : Platform.isIOS
                    ? 'ios'
                    : 'other';
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _settingsFile = File(p.join(dir.path, 'settings.json'));
    Map<String, dynamic> s = {};
    try {
      s = jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>;
    } catch (_) {}
    id = (s['id'] as String?) ?? _randomId();
    name = (s['name'] as String?) ?? await _defaultName();
    keepBg = (s['bg'] as bool?) ?? true;
    var t = (s['theme'] as int?) ?? 0;
    if (t < 0 || t > 2) t = 0;
    themeNotifier.value = ThemeMode.values[t];
    await _save();

    if (Platform.isAndroid) _initService();
    await _refreshIp();
    await _resolveSaveDir();
    try {
      await _startServer();
    } catch (e) {
      history.insert(0, Entry('تعذر تشغيل الاستلام: $e', false));
    }
    try {
      await _startUdp();
    } catch (e) {
      history.insert(0, Entry('تعذر تشغيل اكتشاف الأجهزة: $e', false));
    }
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_tick++ % 5 == 0) await _refreshIp();
      _announce();
      _prune();
    });
  }

  String _randomId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Future<String> _defaultName() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final man = a.manufacturer;
        final model = a.model;
        if (model.toLowerCase().startsWith(man.toLowerCase())) return model;
        return '$man $model'.trim();
      }
      if (Platform.isLinux) {
        final l = await info.linuxInfo;
        return l.prettyName;
      }
      if (Platform.isWindows) {
        try {
          final r = await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            '(Get-CimInstance Win32_ComputerSystem).Model'
          ]);
          final m = (r.stdout as String).trim();
          if (m.isNotEmpty) return m;
        } catch (_) {}
        final w = await info.windowsInfo;
        return w.computerName;
      }
    } catch (_) {}
    return Platform.localHostname;
  }

  Future<void> _save() async {
    try {
      await _settingsFile.writeAsString(jsonEncode({
        'id': id,
        'name': name,
        'bg': keepBg,
        'theme': themeNotifier.value.index,
      }));
    } catch (_) {}
  }

  Future<void> _refreshIp() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final addrs = list
          .expand((i) => i.addresses)
          .map((a) => a.address)
          .where((a) => !a.startsWith('127.') && !a.startsWith('169.254.'))
          .toList();
      final ip = addrs.firstWhere((a) => a.startsWith('192.168.'),
          orElse: () => addrs.isNotEmpty ? addrs.first : '');
      final b = <String>['255.255.255.255'];
      for (final a in addrs) {
        final x = a.split('.');
        b.add('${x[0]}.${x[1]}.${x[2]}.255');
      }
      _broadcasts = b;
      if (ip != myIp) {
        myIp = ip;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _resolveSaveDir() async {
    Directory base;
    if (Platform.isAndroid) {
      base = Directory('/storage/emulated/0/Download/FileTransfer');
    } else {
      final dl = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      base = Directory(p.join(dl.path, 'FileTransfer'));
    }
    try {
      await base.create(recursive: true);
    } catch (_) {
      final alt = await getApplicationDocumentsDirectory();
      base = Directory(p.join(alt.path, 'FileTransfer'));
      await base.create(recursive: true);
    }
    saveDirPath = base.path;
  }

  // ------------------------------------------------------ android service

  void _initService() {
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
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> startAndroid() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.requestNotificationPermission();
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      await Permission.manageExternalStorage.request();
    } catch (_) {}
    await _resolveSaveDir();
    if (keepBg) await _bgStart(kReady);
    notifyListeners();
  }

  Future<void> _bgStart(String text) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationText: text);
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'نقل الملفات',
          notificationText: text,
        );
      }
    } catch (_) {}
  }

  Future<void> _bgUpdate(String text) async {
    try {
      await FlutterForegroundTask.updateService(notificationText: text);
    } catch (_) {}
  }

  Future<void> _bgStop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  void _begin(String text) {
    _active++;
    if (Platform.isAndroid) _bgStart(text);
  }

  void _end() {
    _active = max(0, _active - 1);
    if (_active == 0 && Platform.isAndroid) {
      if (keepBg) {
        _bgUpdate(kReady);
      } else {
        _bgStop();
      }
    }
  }

  void _progress(String text, double frac) {
    if (_clock.elapsedMilliseconds < 700) return;
    _clock.reset();
    notifyListeners();
    if (Platform.isAndroid && _active > 0) {
      _bgUpdate('$text  ${(frac * 100).toStringAsFixed(0)}%');
    }
  }

  void _log(Entry e) {
    history.insert(0, e);
    if (history.length > 50) history.removeLast();
  }

  // ------------------------------------------------------------ settings

  Future<void> setName(String v) async {
    name = v;
    await _save();
    _announce();
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeNotifier.value = m;
    await _save();
  }

  Future<void> setKeepBg(bool v) async {
    keepBg = v;
    await _save();
    if (Platform.isAndroid) {
      if (v) {
        await _bgStart(kReady);
      } else if (_active == 0) {
        await _bgStop();
      }
    }
    notifyListeners();
  }

  // ----------------------------------------------------------- discovery

  Future<void> _startUdp() async {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kUdpPort,
        reuseAddress: true);
    s.broadcastEnabled = true;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = s.receive();
      if (d == null) return;
      try {
        final m = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
        if (m['app'] != kAppTag || m['id'] == id) return;
        final did = m['id'] as String;
        final old = devices[did];
        final dev = Device(did, m['name'] as String, m['type'] as String,
            d.address.address, m['port'] as int, DateTime.now());
        devices[did] = dev;
        if (old == null) {
          _announceTo(d.address);
          notifyListeners();
        } else if (old.name != dev.name || old.ip != dev.ip) {
          notifyListeners();
        }
      } catch (_) {}
    });
    _udp = s;
    _announce();
  }

  List<int> _payload() => utf8.encode(jsonEncode({
        'app': kAppTag,
        'id': id,
        'name': name,
        'type': type,
        'port': kHttpPort,
      }));

  void _announce() {
    final s = _udp;
    if (s == null) return;
    final data = _payload();
    for (final b in _broadcasts) {
      try {
        s.send(data, InternetAddress(b), kUdpPort);
      } catch (_) {}
    }
  }

  void _announceTo(InternetAddress a) {
    try {
      _udp?.send(_payload(), a, kUdpPort);
    } catch (_) {}
  }

  void _prune() {
    final now = DateTime.now();
    final before = devices.length;
    devices.removeWhere((_, d) => now.difference(d.seen).inSeconds > 12);
    if (devices.length != before) notifyListeners();
  }

  void refreshDevices() {
    devices.clear();
    _announce();
    notifyListeners();
  }

  // -------------------------------------------------------------- server

  Future<void> _startServer() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, kHttpPort);
    _server!.listen(_handle);
  }

  void _recvStart(String text) {
    _recvTimer?.cancel();
    if (!receiving) {
      receiving = true;
      _begin(text);
    }
    receiveText = text;
    receiveProgress = 0;
    notifyListeners();
  }

  void _recvDone() {
    _recvTimer?.cancel();
    _recvTimer = Timer(const Duration(seconds: 3), () {
      receiving = false;
      _end();
      notifyListeners();
    });
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.method == 'GET') {
        res.write(kAppTag);
        return;
      }
      if (req.method != 'PUT') {
        res.statusCode = 405;
        return;
      }
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
      var from = 'جهاز';
      try {
        from = Uri.decodeComponent(req.headers.value('x-from') ?? from);
      } catch (_) {}
      final rel = parts.join('/');
      final total = req.contentLength;
      final file = File(p.joinAll([saveDirPath, ...parts]));
      await file.parent.create(recursive: true);
      _recvStart('$from  ←  $rel');
      var got = 0;
      final sink = file.openWrite();
      await sink.addStream(req.map((c) {
        got += c.length;
        if (total > 0) {
          receiveProgress = got / total;
          _progress(receiveText, receiveProgress);
        }
        return c;
      }));
      await sink.close();
      _log(Entry('$rel  ←  $from', true));
      _recvDone();
    } catch (e) {
      res.statusCode = 500;
      _log(Entry('فشل الاستلام: $e', false));
      _recvDone();
    } finally {
      await res.close();
      notifyListeners();
    }
  }

  // -------------------------------------------------------------- client

  void clearSelection() {
    selected.clear();
    notifyListeners();
  }

  Future<String?> addFiles() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return null;
      for (final f in files) {
        final path = f.path;
        if (path == null) continue;
        selected.add(Item(File(path), f.name, await File(path).length()));
      }
    } catch (e) {
      return 'خطأ: $e';
    }
    notifyListeners();
    return null;
  }

  Future<String?> addFolder() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return null;
    if (Platform.isAndroid && !await Permission.manageExternalStorage.isGranted) {
      final st = await Permission.manageExternalStorage.request();
      if (!st.isGranted) {
        return 'لازم تسمح بالوصول لكل الملفات من إعدادات الموبايل عشان تبعت فولدرات';
      }
    }
    final base = p.basename(dir);
    var n = 0;
    try {
      await for (final e
          in Directory(dir).list(recursive: true, followLinks: false)) {
        if (e is File) {
          final rel = p.relative(e.path, from: dir).replaceAll('\\', '/');
          selected.add(Item(e, '$base/$rel', await e.length()));
          n++;
        }
      }
    } catch (e) {
      notifyListeners();
      return 'مقدرتش أقرا الفولدر بالكامل: $e';
    }
    if (n == 0) return 'الفولدر فاضي أو مفيش صلاحية لقراءته';
    notifyListeners();
    return null;
  }

  Future<void> send(Device d) async {
    if (sending || selected.isEmpty) return;
    sending = true;
    sendProgress = 0;
    sendText = 'جارٍ الإرسال إلى ${d.name}';
    notifyListeners();
    _begin(sendText);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final items = List<Item>.from(selected);
    var total = 0;
    for (final it in items) {
      total += await it.file.length();
    }
    var sent = 0;
    var done = 0;
    try {
      for (final it in items) {
        final uri =
            Uri.http('${d.ip}:${d.port}', '/upload', {'path': it.rel});
        final req = await client.putUrl(uri);
        req.headers.set('x-from', Uri.encodeComponent(name));
        req.contentLength = await it.file.length();
        await req.addStream(it.file.openRead().map((c) {
          sent += c.length;
          sendProgress = total == 0 ? 1.0 : sent / total;
          _progress(sendText, sendProgress);
          return c;
        }));
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode != 200) {
          throw Exception('رد الجهاز ${res.statusCode} عند ${it.rel}');
        }
        done++;
        sendText = 'إلى ${d.name}  •  $done من ${items.length}';
        notifyListeners();
      }
      selected.clear();
      _log(Entry('تم إرسال $done ملف إلى ${d.name}', true));
    } catch (e) {
      _log(Entry('فشل الإرسال إلى ${d.name}: $e', false));
    } finally {
      client.close();
      sending = false;
      _end();
      notifyListeners();
    }
  }
}
