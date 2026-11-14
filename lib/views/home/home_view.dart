import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/protocol_library.dart';
import '../../ui/controllers/app_controller.dart';
import '../../ui/pages/protocol_editor_page.dart';
import '../../widgets/desktop_title_bar.dart';
import '../../services/status_bar_service.dart';
import '../serial_port/serial_port_view.dart';
import '../firmware_upgrade/firmware_upgrade_view.dart';
import '../usb/usb_view.dart';
import '../network/network_view.dart';
import '../toolbox/toolbox_view.dart';
import '../i2c_tool/i2c_tool_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _currentIndex = 0;
  bool _navigationExpanded = true;
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

  static const _labels = [
    '串口通信',
    'USB通信',
    '网络通信',
    '工具箱',
    'CH34x调试',
    '固件升级',
    '协议编辑',
  ];
  static const _icons = [
    Icons.settings_input_component_outlined,
    Icons.usb_outlined,
    Icons.lan_outlined,
    Icons.handyman_outlined,
    Icons.memory_outlined,
    Icons.system_update_outlined,
    Icons.schema_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final expanded =
              _navigationExpanded &&
              constraints.maxWidth >= 1280 &&
              constraints.maxHeight >= 720;
          return Column(
            children: [
              DesktopTitleBar(
                navigationExpanded: expanded,
                onMenu: () =>
                    setState(() => _navigationExpanded = !_navigationExpanded),
              ),
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: expanded ? 200 : 56,
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
                          if (expanded)
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
                            if (index == 3) ...[
                              const SizedBox(height: 16),
                              if (expanded)
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
                              child: Tooltip(
                                message: expanded ? '' : _labels[index],
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
                                        mainAxisAlignment: expanded
                                            ? MainAxisAlignment.start
                                            : MainAxisAlignment.center,
                                        children: [
                                          if (expanded)
                                            const SizedBox(width: 12),
                                          Icon(
                                            _icons[index],
                                            size: 17,
                                            color: index == _currentIndex
                                                ? colors.primary
                                                : colors.onSurfaceVariant,
                                          ),
                                          if (expanded) ...[
                                            const SizedBox(width: 10),
                                            Text(
                                              _labels[index],
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                    index == _currentIndex
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                                color: index == _currentIndex
                                                    ? colors.primary
                                                    : colors.onSurface,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (expanded)
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
                      child: Column(
                        children: [
                          Expanded(
                            child: IndexedStack(
                              index: _currentIndex,
                              children: [
                                SerialPortView(),
                                UsbView(),
                                NetworkView(),
                                ToolboxView(),
                                I2cToolView(),
                                FirmwareUpgradeView(
                                  protocolLibrary: _protocolLibrary,
                                ),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: info.color ?? colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
