import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'core.dart';

String fmtBytes(int b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

IconData deviceIcon(String type) {
  switch (type) {
    case 'android':
      return Icons.smartphone;
    case 'ios':
      return Icons.phone_iphone;
    case 'windows':
      return Icons.laptop_windows;
    case 'linux':
      return Icons.computer;
    default:
      return Icons.devices;
  }
}

// ------------------------------------------------------------------ app

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    ColorScheme scheme(Brightness b) =>
        ColorScheme.fromSeed(seedColor: const Color(0xFF7C96F5), brightness: b);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: core.themeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'نقل الملفات',
          themeMode: mode,
          theme: ThemeData(
              useMaterial3: true, colorScheme: scheme(Brightness.light)),
          darkTheme: ThemeData(
              useMaterial3: true, colorScheme: scheme(Brightness.dark)),
          builder: (c, w) =>
              Directionality(textDirection: TextDirection.rtl, child: w!),
          home: Platform.isAndroid
              ? WithForegroundTask(child: const HomePage())
              : const HomePage(),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => core.startAndroid());
  }

  @override
  Widget build(BuildContext context) {
    const pages = [ReceivePage(), SendPage(), SettingsPage()];
    final body = SafeArea(child: IndexedStack(index: tab, children: pages));
    final wide = MediaQuery.of(context).size.width >= 700;
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: tab,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.wifi), label: Text('استقبال')),
              NavigationRailDestination(
                  icon: Icon(Icons.send), label: Text('إرسال')),
              NavigationRailDestination(
                  icon: Icon(Icons.settings), label: Text('الإعدادات')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wifi), label: 'استقبال'),
          NavigationDestination(icon: Icon(Icons.send), label: 'إرسال'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- logo

class LogoPainter extends CustomPainter {
  final Color color;
  final double turn;
  LogoPainter(this.color, this.turn);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(center, r * 0.42, Paint()..color = color);
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final start = turn + i * pi / 4 + 0.2;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r * 0.82), start,
          pi / 4 - 0.4, false, ring);
    }
  }

  @override
  bool shouldRepaint(covariant LogoPainter old) =>
      old.turn != turn || old.color != color;
}

class AnimatedLogo extends StatefulWidget {
  final double size;
  const AnimatedLogo({super.key, required this.size});
  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController ctl =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))
        ..repeat();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: ctl,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: LogoPainter(color, ctl.value * 2 * pi),
      ),
    );
  }
}

// -------------------------------------------------------------- widgets

class _ProgressCard extends StatelessWidget {
  final String title;
  final double value;
  const _ProgressCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          LinearProgressIndicator(
              value: (value > 0 && value <= 1) ? value : null),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------- receive

class ReceivePage extends StatelessWidget {
  const ReceivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            const Center(child: AnimatedLogo(size: 180)),
            const SizedBox(height: 24),
            Center(
              child: Text(core.name,
                  style: t.textTheme.headlineMedium,
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                core.myIp.isEmpty
                    ? 'مفيش اتصال بالواي فاي'
                    : '$kReady  •  ${core.myIp}',
                style: t.textTheme.bodyMedium
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
            ),
            if (core.receiving) ...[
              const SizedBox(height: 24),
              _ProgressCard(
                  title: core.receiveText, value: core.receiveProgress),
            ],
            const SizedBox(height: 24),
            if (core.history.isNotEmpty) ...[
              Text('آخر العمليات', style: t.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final e in core.history.take(15))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    e.ok ? Icons.check_circle : Icons.error,
                    color: e.ok ? Colors.green : t.colorScheme.error,
                  ),
                  title: Text(e.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
            const SizedBox(height: 16),
            Center(
              child: Text(
                'بيتحفظ في: ${core.saveDirPath}',
                style: t.textTheme.bodySmall
                    ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------- send

class SendPage extends StatelessWidget {
  const SendPage({super.key});

  Future<void> _run(BuildContext context, Future<String?> job) async {
    final msg = await job;
    if (msg != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _bigButton(IconData icon, String label, VoidCallback? onTap) {
    return SizedBox(
      height: 96,
      child: FilledButton.tonal(
        onPressed: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 32),
          const SizedBox(height: 6),
          Text(label),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final devs = core.devices.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('إرسال', style: t.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _bigButton(Icons.insert_drive_file, 'ملفات',
                    core.sending ? null : () => _run(context, core.addFiles())),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _bigButton(Icons.folder, 'فولدر',
                    core.sending ? null : () => _run(context, core.addFolder())),
              ),
            ]),
            if (core.selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(
                      '${core.selected.length} ملف  •  ${fmtBytes(core.selectedBytes)}'),
                  subtitle: const Text('اختار الجهاز من تحت للإرسال'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: core.sending ? null : core.clearSelection,
                  ),
                ),
              ),
            ],
            if (core.sending) ...[
              const SizedBox(height: 12),
              _ProgressCard(title: core.sendText, value: core.sendProgress),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Text('الأجهزة القريبة', style: t.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: core.refreshDevices,
              ),
            ]),
            if (devs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(children: [
                  const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(height: 16),
                  Text(
                    'بيدوّر على أجهزة...\nتأكد إن التطبيق شغال على الجهاز التاني وعلى نفس الواي فاي',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodyMedium
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ]),
              )
            else
              for (final d in devs)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(deviceIcon(d.type))),
                    title: Text(d.name),
                    subtitle: Text(d.ip),
                    onTap: () {
                      if (core.selected.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('اختار ملفات أو فولدر الأول')),
                        );
                      } else {
                        core.send(d);
                      }
                    },
                  ),
                ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------- settings

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _rename(BuildContext context) async {
    final ctl = TextEditingController(text: core.name);
    final v = await showDialog<String>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('اسم الجهاز'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(dc, ctl.text.trim()),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) core.setName(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('الإعدادات', style: t.textTheme.headlineSmall),
            const SizedBox(height: 20),
            Text('المظهر', style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('النظام')),
                ButtonSegment(value: ThemeMode.light, label: Text('فاتح')),
                ButtonSegment(value: ThemeMode.dark, label: Text('داكن')),
              ],
              selected: {core.themeMode},
              onSelectionChanged: (s) => core.setTheme(s.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اسم الجهاز'),
              subtitle: Text(core.name),
              trailing: const Icon(Icons.edit),
              onTap: () => _rename(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مكان حفظ الملفات'),
              subtitle: Text(core.saveDirPath),
            ),
            if (Platform.isAndroid)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الاستمرار في الخلفية'),
                subtitle: const Text(
                    'يخلي الإرسال والاستلام شغالين لما تقفل الشاشة أو تخرج من التطبيق'),
                value: core.keepBg,
                onChanged: core.setKeepBg,
              ),
            const SizedBox(height: 24),
            Center(
              child: Text('نقل الملفات  •  الإصدار 2.0',
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
          ],
        );
      },
    );
  }
}
