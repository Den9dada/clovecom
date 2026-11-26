import '../../src/application/app_update.dart';
import '../../src/application/communication_runtime.dart';

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/protocol_library.dart';
import '../../ui/controllers/app_controller.dart';
import '../../ui/layout/responsive.dart';
import '../../ui/pages/protocol_editor_page.dart';
import '../../widgets/desktop_title_bar.dart';
import '../../services/status_bar_service.dart';
import '../serial_port/serial_port_view.dart';
import '../toolbox/toolbox_view.dart';
import '../i2c_tool/i2c_tool_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    this.communication,
    this.updateController,
    this.onExitForUpdate,
  });

  final CommunicationRuntime? communication;
  final AppUpdateController? updateController;
  final Future<void> Function()? onExitForUpdate;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _currentIndex = 0;
  bool? _navigationExpanded;
  final _protocolLibrary = ProtocolLibrary();
  late final _protocolController = AppController(_protocolLibrary);
  bool _protocolReady = false;
  String? _protocolError;
  @override
  void initState() {
    super.initState();
    _loadProtocols();
  }

  Future<void> _loadProtocols() async {
    try {
      final dir = await getApplicationSupportDirectory();
      if (!mounted) return;
      await _protocolLibrary.initialize(
        file: File('${dir.path}/protocols/library.json'),
      );
      if (mounted) setState(() => _protocolReady = true);
    } catch (error) {
      if (mounted) setState(() => _protocolError = '协议库载入失败：$error');
    }
  }

  @override
  void dispose() {
    _protocolController.dispose();
    _protocolLibrary.dispose();
    super.dispose();
  }

  static const _labels = ['接口通信', '工具箱', 'CH34x调试', '协议编辑'];
  static const _icons = [
    Icons.device_hub,
    Icons.handyman_outlined,
    Icons.memory_outlined,
    Icons.schema_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final expanded =
              _navigationExpanded ??
              appDensityFor(constraints.biggest) != AppLayoutDensity.compact;
          return Column(
            children: [
              DesktopTitleBar(
                navigationExpanded: expanded,
                onMenu: () => setState(() => _navigationExpanded = !expanded),
                updateController: widget.updateController,
                onExitForUpdate: widget.onExitForUpdate,
              ),
              Expanded(
                child: Row(
                  children: [
                    if (expanded)
                      Container(
                        width: AppWindowMetrics.navWidth,
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          border: Border(
                            right: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                              child: Text(
                                '设备通信',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            for (
                              var index = 0;
                              index < _labels.length;
                              index++
                            ) ...[
                              if (index == 1) ...[
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    12,
                                    8,
                                  ),
                                  child: Text(
                                    '开发工具',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                child: Material(
                                  color: index == _currentIndex
                                      ? colors.primary.withValues(alpha: 0.09)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () =>
                                        setState(() => _currentIndex = index),
                                    child: SizedBox(
                                      height: 36,
                                      child: Row(
                                        children: [
                                          const SizedBox(width: 12),
                                          Icon(
                                            _icons[index],
                                            size: 17,
                                            color: index == _currentIndex
                                                ? colors.primary
                                                : colors.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _labels[index],
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: index == _currentIndex
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: index == _currentIndex
                                                  ? colors.primary
                                                  : colors.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'CloveCOM · 开发工作台',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      key: const ValueKey('home-content'),
                      child: Column(
                        children: [
                          Expanded(
                            child: IndexedStack(
                              index: _currentIndex,
                              children: [
                                SerialPortView(
                                  runtime: widget.communication,
                                  protocolLibrary: _protocolLibrary,
                                ),
                                ToolboxView(),
                                I2cToolView(),
                                _protocolReady
                                    ? ProtocolEditorPage(
                                        controller: _protocolController,
                                      )
                                    : Center(
                                        child: _protocolError != null
                                            ? Text(_protocolError!)
                                            : const CircularProgressIndicator(),
                                      ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBarWidget(tabIndex: _currentIndex),
            ],
          );
        },
      ),
    );
  }
}

/// 状态栏 — StatefulWidget 自行管理对 [StatusBarService.version] 的监听，
/// 确保监听器生命周期不依赖外层重建频率。
class _StatusBarWidget extends StatefulWidget {
  const _StatusBarWidget({required this.tabIndex});

  final int tabIndex;

  @override
  State<_StatusBarWidget> createState() => _StatusBarWidgetState();
}

class _StatusBarWidgetState extends State<_StatusBarWidget> {
  void _onVersionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    StatusBarService().version.addListener(_onVersionChanged);
  }

  @override
  void dispose() {
    StatusBarService().version.removeListener(_onVersionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = StatusBarService().statusFor(widget.tabIndex);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (info.icon != null) ...[
            Icon(
              info.icon,
              size: 14,
              color: info.color ?? colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              info.text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: info.color ?? colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
