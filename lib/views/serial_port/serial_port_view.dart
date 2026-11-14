import '../../widgets/baud_rate_input.dart';
import 'package:clovecom/widgets/app_dropdown.dart';
// 串口通信视图文件
//
// 该文件实现了串口通信的用户界面，采用MVVM架构中的View层。
// 整体布局为左右分割，左侧为串口配置区，右侧为数据收发区。
//
// 左侧配置区分为三部分：
// - 串口配置：端口选择、波特率、数据位、停止位、校验、流控、连接按键
// - 接收配置：ASCII/HEX显示、日志模式、自动换行、隐藏接收、保存文件、自动滚动、清空接收区
// - 发送配置：ASCII/HEX显示、循环发送、发送间隔
//
// 右侧数据收发区：
// - 上方：数据日志（显示所有收发数据）
// - 下方：发送区（支持文本、十六进制、文件发送）

import 'dart:async';
import '../../widgets/serial_port_input.dart';
import 'package:flutter/material.dart';
import '../../ui/desktop_theme.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/serial_port_model.dart';
import '../../viewmodels/serial_port_viewmodel.dart';
import '../../utils/hex_input_formatter.dart';
import '../../protocols/protocol_registry.dart';
import '../../services/status_bar_service.dart';

/// 串口通信视图组件
class SerialPortView extends StatelessWidget {
  const SerialPortView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SerialPortViewModel(),
      child: const _SerialPortStatusBinder(child: _SerialPortViewContent()),
    );
  }
}

/// 监听 SerialPortViewModel 变化，在 listener 中上报状态栏
class _SerialPortStatusBinder extends StatefulWidget {
  const _SerialPortStatusBinder({required this.child});
  final Widget child;

  @override
  State<_SerialPortStatusBinder> createState() =>
      _SerialPortStatusBinderState();
}

class _SerialPortStatusBinderState extends State<_SerialPortStatusBinder> {
  late final SerialPortViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = context.read<SerialPortViewModel>();
    _vm.addListener(_updateStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateStatus();
    });
  }

  @override
  void dispose() {
    _vm.removeListener(_updateStatus);
    super.dispose();
  }

  void _updateStatus() {
    final vm = _vm;
    StatusBarService().update(
      0,
      StatusBarInfo(
        text: vm.state.isConnected
            ? '已连接 ${vm.config.portName} @ ${vm.config.baudRate}'
            : '未连接',
        icon: vm.state.isConnected ? Icons.check_circle : Icons.circle_outlined,
        color: vm.state.isConnected ? Colors.green : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 串口通信视图内容组件
class _SerialPortViewContent extends StatefulWidget {
  const _SerialPortViewContent();

  @override
  State<_SerialPortViewContent> createState() => _SerialPortViewContentState();
}

/// 串口通信视图内容状态类
class _SerialPortViewContentState extends State<_SerialPortViewContent> {
  static const Color _terminalBackground = Color(0xFFFFFFFF);
  static const Color _terminalPanel = Color(0xFFF5F5F5);
  static const Color _terminalBorder = Color(0xFFE5E5E5);
  static const Color _terminalText = Color(0xFF171717);
  static const Color _terminalMuted = Color(0xFF737373);
  static const Color _rxColor = Color(0xFF15A877);
  static const Color _txColor = Color(0xFF4B3FE3);

  final TextEditingController _sendController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _packetSizeController = TextEditingController(
    text: '1024',
  );
  final TextEditingController _intervalController = TextEditingController(
    text: '100',
  );
  final TextEditingController _loopIntervalController = TextEditingController(
    text: '1000',
  );

  StreamSubscription<String>? _errorSub;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = context.read<SerialPortViewModel>();
      _errorSub = viewModel.errorStream.listen((message) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message, style: const TextStyle(fontSize: 13)),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(12),
            ),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _sendController.dispose();
    _scrollController.dispose();
    _packetSizeController.dispose();
    _intervalController.dispose();
    _loopIntervalController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SerialPortViewModel>();
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // 顶部：端口选择行（横跨全宽）
              _buildPortBar(viewModel, colorScheme),
              const SizedBox(height: 12),
              Expanded(
                child: compact
                    ? LayoutBuilder(
                        builder: (context, innerConstraints) {
                          // 矮窗口下压缩配置区高度（面板自身可滚动），
                          // 保证数据面板至少能容纳日志标题栏与发送区。
                          final configHeight =
                              (innerConstraints.maxHeight - 250).clamp(
                                150.0,
                                230.0,
                              );
                          return Column(
                            children: [
                              Expanded(
                                child: _buildDataPanel(viewModel, colorScheme),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: configHeight,
                                child: _buildConfigPanel(
                                  viewModel,
                                  colorScheme,
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 270,
                            child: _buildConfigPanel(viewModel, colorScheme),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDataPanel(viewModel, colorScheme),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPanelHeader({
    required IconData icon,
    required String title,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 16, color: colorScheme.primary),
        ),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }

  Widget _buildFieldShell({
    required IconData icon,
    required String label,
    required Widget child,
    required ColorScheme colorScheme,
    int flex = 1,
    double? width,
  }) {
    final content = Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }

    return Expanded(flex: flex, child: content);
  }

  Widget _buildBaudRateField(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.speed, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '波特率',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 144,
          child: BaudRateInput(
            value: viewModel.config.baudRate,
            onChanged: viewModel.state.isConnected
                ? null
                : (rate) => viewModel.updateConfig(baudRate: rate),
          ),
        ),
      ],
    );
  }

  /// 构建顶部端口选择行（横跨全宽，对齐配置区和数据日志区）
  Widget _buildPortBar(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 端口选择
            _buildFieldShell(
              icon: Icons.device_hub,
              label: '端口',
              colorScheme: colorScheme,
              flex: 1,
              child: SerialPortInput(
                directory: viewModel.portDirectory,
                value: viewModel.config.portName,
                enabled: !viewModel.state.isConnected,
                onChanged: (value) {
                  final ports = viewModel.availablePorts.where(
                    (p) => p.portName == value,
                  );
                  viewModel.updateConfig(
                    portName: value,
                    portFriendlyName: ports.isEmpty
                        ? ''
                        : ports.first.friendlyName,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            // 刷新按钮
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: viewModel.refreshPorts,
              tooltip: '刷新串口列表',
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 12),
            // 波特率
            _buildBaudRateField(viewModel, colorScheme),
            const SizedBox(width: 12),
            // 连接按钮
            _buildConnectionButton(viewModel, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 构建连接按钮
  Widget _buildConnectionButton(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    final isConnected = viewModel.state.isConnected;
    return SizedBox(
      width: 120,
      child: FilledButton.icon(
        onPressed: () async {
          if (isConnected) {
            await viewModel.disconnect();
          } else {
            await viewModel.connect();
          }
        },
        icon: Icon(isConnected ? Icons.link_off : Icons.link, size: 16),
        label: Text(isConnected ? '断开连接' : '打开串口'),
        style: FilledButton.styleFrom(
          backgroundColor: isConnected
              ? colorScheme.error
              : colorScheme.primary,
          foregroundColor: isConnected
              ? colorScheme.onError
              : colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
  }

  /// 构建配置面板
  Widget _buildConfigPanel(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 串口配置
          _buildSerialConfig(viewModel, colorScheme),
          const SizedBox(height: 12),
          // 接收配置
          _buildReceiveConfig(viewModel, colorScheme),
          const SizedBox(height: 12),
          // 发送配置
          _buildSendConfig(viewModel, colorScheme),
        ],
      ),
    );
  }

  /// 构建串口高级配置（数据位、停止位、校验、流控）
  Widget _buildSerialConfig(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            _buildPanelHeader(
              icon: Icons.tune,
              title: '串口参数',
              colorScheme: colorScheme,
            ),
            const Divider(height: 16),
            // 数据位
            _buildDropdown<int>(
              label: '数据位',
              value: viewModel.config.dataBits,
              items: [5, 6, 7, 8]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                  .toList(),
              onChanged: viewModel.state.isConnected
                  ? null
                  : (v) => viewModel.updateConfig(dataBits: v!),
            ),
            const SizedBox(height: 8),
            // 停止位
            _buildDropdown<int>(
              label: '停止位',
              value: viewModel.config.stopBits,
              items: [1, 2]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                  .toList(),
              onChanged: viewModel.state.isConnected
                  ? null
                  : (v) => viewModel.updateConfig(stopBits: v!),
            ),
            const SizedBox(height: 8),
            // 校验
            _buildDropdown<String>(
              label: '校验',
              value: viewModel.config.parity,
              items: ['None', 'Odd', 'Even', 'Mark', 'Space'].map((v) {
                String label;
                switch (v) {
                  case 'None':
                    label = '无校验';
                  case 'Odd':
                    label = '奇校验';
                  case 'Even':
                    label = '偶校验';
                  case 'Mark':
                    label = '标记';
                  case 'Space':
                    label = '空格';
                  default:
                    label = v;
                }
                return DropdownMenuItem(value: v, child: Text(label));
              }).toList(),
              onChanged: viewModel.state.isConnected
                  ? null
                  : (v) => viewModel.updateConfig(parity: v!),
            ),
            const SizedBox(height: 8),
            // 流控
            _buildDropdown<String>(
              label: '流控',
              value: viewModel.config.flowControl,
              items: ['None', 'XON/XOFF', 'RTS/CTS', 'DTR/DSR'].map((v) {
                return DropdownMenuItem(value: v, child: Text(v));
              }).toList(),
              onChanged: viewModel.state.isConnected
                  ? null
                  : (v) => viewModel.updateConfig(flowControl: v!),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建通用下拉框
  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 45,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: AppDropdownFormField<T>(
            isExpanded: true,
            dropdownColor: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            menuMaxHeight: 260,
            iconEnabledColor: Theme.of(context).colorScheme.onSurfaceVariant,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
            initialValue: value,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// 构建接收配置
  Widget _buildReceiveConfig(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    final config = viewModel.displayConfig;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            _buildPanelHeader(
              icon: Icons.download_outlined,
              title: '接收配置',
              colorScheme: colorScheme,
            ),
            const Divider(height: 12),
            // 开关选项 - 使用 Wrap 布局更紧凑
            Wrap(
              spacing: 2,
              runSpacing: 0,
              children: [
                _buildCompactSwitch(
                  title: 'HEX显示',
                  value: config.receiveHex,
                  onChanged: (v) =>
                      viewModel.updateDisplayConfig(receiveHex: v),
                ),
                _buildCompactSwitch(
                  title: '日志模式',
                  value: config.logMode,
                  onChanged: (v) => viewModel.updateDisplayConfig(logMode: v),
                ),
                _buildCompactSwitch(
                  title: '自动换行',
                  value: config.autoWrap,
                  onChanged: (v) => viewModel.updateDisplayConfig(autoWrap: v),
                ),
                _buildCompactSwitch(
                  title: '隐藏接收',
                  value: config.hideReceive,
                  onChanged: (v) =>
                      viewModel.updateDisplayConfig(hideReceive: v),
                ),
                _buildCompactSwitch(
                  title: '保存文件',
                  value: config.saveToFile,
                  onChanged: (v) =>
                      viewModel.updateDisplayConfig(saveToFile: v),
                ),
                _buildCompactSwitch(
                  title: '自动滚动',
                  value: config.autoScroll,
                  onChanged: (v) =>
                      viewModel.updateDisplayConfig(autoScroll: v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建发送配置
  Widget _buildSendConfig(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    final config = viewModel.displayConfig;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            _buildPanelHeader(
              icon: Icons.upload_outlined,
              title: '发送配置',
              colorScheme: colorScheme,
            ),
            const Divider(height: 12),
            // 开关选项
            Wrap(
              spacing: 2,
              runSpacing: 0,
              children: [
                _buildCompactSwitch(
                  title: 'HEX发送',
                  value: config.sendHex,
                  onChanged: (v) {
                    if (_sendController.text.isNotEmpty) {
                      if (v) {
                        _sendController.text = viewModel.convertTextToHex(
                          _sendController.text,
                        );
                      } else {
                        final text = viewModel.convertHexToText(
                          _sendController.text,
                        );
                        if (text != null) {
                          _sendController.text = text;
                        }
                      }
                    }
                    viewModel.updateDisplayConfig(sendHex: v);
                  },
                ),
                _buildCompactSwitch(
                  title: '循环发送',
                  value: config.loopSend,
                  onChanged: (v) => viewModel.updateDisplayConfig(loopSend: v),
                ),
                _buildCompactSwitch(
                  title: '追加回车',
                  value: config.appendCR,
                  onChanged: (v) => viewModel.updateDisplayConfig(appendCR: v),
                ),
                _buildCompactSwitch(
                  title: '追加新行',
                  value: config.appendLF,
                  onChanged: (v) => viewModel.updateDisplayConfig(appendLF: v),
                ),
              ],
            ),
            // 循环发送间隔
            if (config.loopSend) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('间隔:', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _loopIntervalController,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        isDense: true,
                        suffixText: 'ms',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      onChanged: (value) {
                        final interval = int.tryParse(value);
                        if (interval != null && interval > 0) {
                          viewModel.updateDisplayConfig(loopInterval: interval);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建紧凑开关项（用于 Wrap 布局）
  Widget _buildCompactSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SizedBox(
      width: 118,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(7),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => onChanged(!value),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建数据收发面板
  Widget _buildDataPanel(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight;
          final sendHeight = _resolveSendAreaHeight(maxHeight);

          return Column(
            children: [
              // 数据日志
              Expanded(child: _buildLogArea(viewModel, colorScheme)),
              Divider(height: 1, color: colorScheme.outlineVariant),
              // 发送区保持稳定高度，避免标题、Tab 和按钮互相挤压。
              SizedBox(
                height: sendHeight,
                child: _buildSendArea(viewModel, colorScheme),
              ),
            ],
          );
        },
      ),
    );
  }

  double _resolveSendAreaHeight(double maxHeight) {
    if (maxHeight.isInfinite) return 260;
    if (maxHeight >= 640) return 220;
    if (maxHeight >= 480) return 200;
    // 矮窗口下保留发送区最低可用高度（Tab 栏 + 输入行 + 发送按钮列），
    // 避免文本发送页内的固定高度按钮列溢出。
    final preferred = maxHeight * 0.40;
    const floor = 176.0;
    if (preferred >= floor) return preferred;
    return floor <= maxHeight ? floor : maxHeight;
  }

  /// 构建数据日志区
  Widget _buildLogArea(SerialPortViewModel viewModel, ColorScheme colorScheme) {
    final messages = viewModel.messages;
    final displayConfig = viewModel.displayConfig;

    if (displayConfig.autoScroll && messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottom();
        }
      });
    }

    return RepaintBoundary(
      child: Container(
        color: _terminalBackground,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: const BoxDecoration(
                color: _terminalPanel,
                border: Border(bottom: BorderSide(color: _terminalBorder)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.article_outlined, size: 16, color: _txColor),
                  const SizedBox(width: 8),
                  Text(
                    '数据日志',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: _terminalText),
                  ),
                  const Spacer(),
                  _buildLogStat(
                    'RX',
                    viewModel.formatBytes(viewModel.stats.receivedBytes),
                    _rxColor,
                  ),
                  const SizedBox(width: 8),
                  _buildLogStat(
                    'TX',
                    viewModel.formatBytes(viewModel.stats.sentBytes),
                    _txColor,
                  ),
                  const SizedBox(width: 8),
                  _buildLogClearButton(viewModel),
                ],
              ),
            ),
            // 消息列表
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        '暂无数据',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _terminalMuted.withValues(alpha: 0.72),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return _buildMessageItem(
                          message,
                          displayConfig.receiveHex,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, fontFamily: 'Consolas'),
      ),
    );
  }

  Widget _buildLogClearButton(SerialPortViewModel viewModel) {
    return SizedBox(
      height: 26,
      child: OutlinedButton.icon(
        onPressed: viewModel.clearMessages,
        icon: const Icon(Icons.delete_outline, size: 13),
        label: const Text('清空接收区'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _terminalMuted,
          side: const BorderSide(color: _terminalBorder),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// 构建消息项
  Widget _buildMessageItem(SerialPortMessage message, bool showHex) {
    final timeStr = DateFormat('HH:mm:ss.SSS').format(message.timestamp);
    // HEX模式下优先显示hexData，无hexData时回退到data（如协议日志）
    final displayData = (showHex && message.hexData.isNotEmpty)
        ? message.hexData
        : message.data;
    final isSent = message.isSent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间戳
          Text(
            timeStr,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _terminalMuted,
              fontFamily: 'Consolas',
              fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          // RX/TX标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: (isSent ? _txColor : _rxColor).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isSent ? 'TX' : 'RX',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isSent ? _txColor : _rxColor,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 数据内容
          Expanded(
            child: Text(
              displayData,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _terminalText,
                fontFamily: 'Consolas',
                fontFamilyFallback: const ['Menlo', 'Courier New', 'MiSans'],
                fontSize: 12,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建发送区
  Widget _buildSendArea(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // Tab栏
          TabBar(
            tabs: const [
              Tab(text: '数据发送'),
              Tab(text: '文件发送'),
              Tab(text: '文件接收'),
            ],
            labelStyle: Theme.of(context).textTheme.labelSmall,
            unselectedLabelStyle: Theme.of(context).textTheme.labelSmall,
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            dividerHeight: 1,
            dividerColor: colorScheme.outlineVariant,
            indicatorColor: colorScheme.primary,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
          ),
          // Tab内容
          Expanded(
            child: TabBarView(
              children: [
                _buildTextSendArea(viewModel, colorScheme),
                _buildFileSendArea(viewModel, colorScheme),
                _buildFileReceiveArea(viewModel, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建文本发送区
  Widget _buildTextSendArea(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // HEX提示信息
          if (viewModel.displayConfig.sendHex) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'HEX格式：每两个十六进制字符用空格隔开，如：48 65 6C 6C 6F',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 输入框和发送按钮
          Expanded(
            child: Row(
              children: [
                // 输入框
                Expanded(
                  child: TextField(
                    controller: _sendController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: ['Menlo', 'Courier New', 'MiSans'],
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: viewModel.displayConfig.sendHex
                          ? '输入HEX数据'
                          : '输入文本数据',
                      contentPadding: const EdgeInsets.all(10),
                    ),
                    inputFormatters: viewModel.displayConfig.sendHex
                        ? [HexInputFormatter()]
                        : [],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: OutlinedButton.icon(
                          onPressed: _sendController.clear,
                          icon: const Icon(Icons.backspace_outlined, size: 14),
                          label: const Text('清空发送区'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: FilledButton.icon(
                          onPressed: viewModel.state.isConnected
                              ? () async {
                                  if (_sendController.text.isNotEmpty) {
                                    await viewModel.sendDataWithLoopCheck(
                                      _sendController.text,
                                    );
                                  }
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          icon: const Icon(Icons.send, size: 15),
                          label: const Text('发送'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建文件发送区
  Widget _buildFileSendArea(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 文件选择
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file_outlined,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          viewModel.fileSendConfig.fileName.isEmpty
                              ? '未选择文件'
                              : viewModel.fileSendConfig.fileName,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: viewModel.selectFile,
                child: const Text('选择文件'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 协议选择
          Row(
            children: [
              Text('协议:', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: 8),
              Expanded(
                child: AppDropdownFormField<String>(
                  isExpanded: true,
                  dropdownColor: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  menuMaxHeight: 240,
                  iconEnabledColor: colorScheme.onSurfaceVariant,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    isDense: true,
                  ),
                  initialValue: viewModel.fileSendConfig.protocolName,
                  items: ProtocolRegistry.protocols.map((p) {
                    return DropdownMenuItem(
                      value: p.name,
                      child: Text(p.name, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: viewModel.isTransferBusy
                      ? null
                      : (v) {
                          if (v != null) {
                            viewModel.updateFileSendConfig(protocolName: v);
                          }
                        },
                ),
              ),
            ],
          ),
          // 进度条
          if (viewModel.fileSendConfig.fileSize > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: viewModel.fileSendConfig.progress,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(viewModel.fileSendConfig.progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // 按钮
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      viewModel.state.isConnected && !viewModel.isTransferBusy
                      ? viewModel.startFileSend
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('开始发送'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.tertiary,
                    foregroundColor: colorScheme.onTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: viewModel.fileSendConfig.isSending
                      ? viewModel.stopFileSend
                      : null,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('停止'),
                  style: desktopActionStyle(DesktopActionKind.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建文件接收区
  Widget _buildFileReceiveArea(
    SerialPortViewModel viewModel,
    ColorScheme colorScheme,
  ) {
    final config = viewModel.fileReceiveConfig;
    final hasDefaultDir = config.defaultSaveDir.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 保存路径选择
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          config.savePath.isNotEmpty
                              ? config.fileName
                              : hasDefaultDir
                              ? '自动保存（使用发送端文件名）'
                              : '请设置存储路径',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: config.isReceiving
                    ? null
                    : viewModel.selectReceivePath,
                child: const Text('另存为'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 默认目录设置
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.download,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasDefaultDir ? config.defaultSaveDir : '未设置默认存储目录',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: config.isReceiving
                    ? null
                    : viewModel.selectDefaultReceiveDir,
                child: const Text('默认目录'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 协议选择
          Row(
            children: [
              Text('协议:', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: 8),
              Expanded(
                child: AppDropdownFormField<String>(
                  isExpanded: true,
                  dropdownColor: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  menuMaxHeight: 240,
                  iconEnabledColor: colorScheme.onSurfaceVariant,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    isDense: true,
                  ),
                  initialValue: config.protocolName,
                  items: ProtocolRegistry.receiveProtocols.map((p) {
                    return DropdownMenuItem(
                      value: p.receiveName,
                      child: Text(
                        p.receiveName,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: viewModel.isTransferBusy
                      ? null
                      : (v) {
                          if (v != null) {
                            viewModel.updateFileReceiveConfig(protocolName: v);
                          }
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 进度条
          if (config.isReceiving || config.receivedBytes > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: config.totalBytes > 0 ? config.progress : null,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  viewModel.formatBytes(config.receivedBytes),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // 按钮
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      viewModel.state.isConnected && !viewModel.isTransferBusy
                      ? viewModel.startFileReceive
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('开始接收'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: config.isReceiving
                      ? viewModel.stopFileReceive
                      : null,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('停止'),
                  style: desktopActionStyle(DesktopActionKind.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
