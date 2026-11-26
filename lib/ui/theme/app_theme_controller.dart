import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'terminal_color_schemes.dart';

/// 应用级主题配色控制器，管理当前 `TerminalColorScheme` 并持久化到应用支持目录。
class AppThemeController extends ChangeNotifier {
  AppThemeController({
    TerminalColorScheme? initial,
    this.file,
    Future<Directory> Function()? directoryProvider,
    this.persist = true,
  }) : _scheme = initial ?? defaultTerminalColorScheme,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  File? file;
  final Future<Directory> Function() _directoryProvider;
  final bool persist;
  TerminalColorScheme _scheme;

  TerminalColorScheme get scheme => _scheme;

  Future<void> load() async {
    if (!persist) return;
    try {
      final target = await _resolveFile();
      if (!await target.exists()) return;
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is Map<String, dynamic>) {
        final id = decoded['scheme'];
        if (id is String) {
          final next = resolveTerminalColorScheme(id);
          if (next.id != _scheme.id) {
            _scheme = next;
            notifyListeners();
          }
        }
      }
    } catch (error) {
      debugPrint('应用主题载入失败，使用默认值：$error');
    }
  }

  void select(TerminalColorScheme next) {
    if (_scheme.id == next.id) return;
    _scheme = next;
    notifyListeners();
    if (persist) unawaited(_save());
  }

  Future<void> _save() async {
    try {
      final target = await _resolveFile();
      await target.parent.create(recursive: true);
      await target.writeAsString(jsonEncode({'scheme': _scheme.id}));
    } catch (error) {
      debugPrint('应用主题保存失败：$error');
    }
  }

  Future<File> _resolveFile() async {
    final explicit = file;
    if (explicit != null) return explicit;
    final dir = await _directoryProvider();
    return file = File('${dir.path}/app_theme.json');
  }
}

/// 将 `AppThemeController` 向下传递给全应用组件树。
class AppThemeScope extends InheritedNotifier<AppThemeController> {
  const AppThemeScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>()?.notifier;
}

/// 构建统一的主题配色菜单项列表（浅色/深色分组，带色彩预览）。
List<Widget> buildThemeMenuChildren({
  required TerminalColorScheme current,
  required ValueChanged<TerminalColorScheme> onSelect,
}) {
  Widget item(TerminalColorScheme scheme) {
    final selected = scheme.id == current.id;
    return MenuItemButton(
      key: ValueKey('color-scheme-${scheme.id}'),
      onPressed: () => onSelect(scheme),
      style: MenuItemButton.styleFrom(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 20, 0),
      ),
      leadingIcon: selected
          ? const Icon(Icons.check, size: 16)
          : const SizedBox(width: 16),
      trailingIcon: ThemeColorSwatch(scheme: scheme),
      child: Text(scheme.name),
    );
  }

  return [
    for (final scheme in terminalColorSchemes.where((s) => !s.isDark))
      item(scheme),
    const Divider(height: 1),
    for (final scheme in terminalColorSchemes.where((s) => s.isDark))
      item(scheme),
  ];
}

/// 主题配色预览色块（展示背景色、RX 色与 TX 色）。
class ThemeColorSwatch extends StatelessWidget {
  const ThemeColorSwatch({super.key, required this.scheme});

  final TerminalColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final bg = scheme.background ?? Theme.of(context).colorScheme.surface;
    final border = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: scheme.rx, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: scheme.tx, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
